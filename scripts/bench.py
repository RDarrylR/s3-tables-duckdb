"""Latency benchmarks for the lakehouse, captured into docs/perf.md.

Runs a fixed query battery N times each, records min/mean/max in milliseconds,
and dumps a markdown table to docs/perf.md.

Run with::

    uv run python scripts/bench.py
"""

from __future__ import annotations

import json
import statistics
import subprocess
import time
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
TF_DIR = ROOT / "infrastructure"
OUT = ROOT / "docs" / "perf.md"

ITERATIONS = 5

QUERIES: list[tuple[str, str]] = [
    ("count_all", "SELECT COUNT(*) FROM lake.airquality.measurements"),
    (
        "pm25_last_7d",
        """
        SELECT location_id, AVG(value) AS mean
        FROM lake.airquality.measurements
        WHERE parameter = 'pm25' AND datetime >= NOW() - INTERVAL 7 DAY
        GROUP BY location_id
        ORDER BY mean DESC
        LIMIT 50
        """,
    ),
    (
        "param_breakdown",
        """
        SELECT parameter, units, COUNT(*) AS n, AVG(value) AS mean
        FROM lake.airquality.measurements
        GROUP BY parameter, units
        ORDER BY n DESC
        """,
    ),
    (
        "join_locations",
        """
        SELECT m.parameter, AVG(m.value) AS mean, COUNT(DISTINCT l.location_id) AS stations
        FROM lake.airquality.measurements AS m
        JOIN lake.airquality.locations    AS l USING (location_id)
        WHERE l.measurement_count >= 100
        GROUP BY m.parameter
        ORDER BY mean DESC
        """,
    ),
    (
        "rolling_o3",
        """
        SELECT location_id, datetime, value,
               MAX(value) OVER (PARTITION BY location_id, parameter
                                ORDER BY datetime
                                RANGE BETWEEN INTERVAL 24 HOURS PRECEDING AND CURRENT ROW) AS rolling
        FROM lake.airquality.measurements
        WHERE parameter = 'o3'
        LIMIT 100
        """,
    ),
]


def _attach(con: duckdb.DuckDBPyConnection, arn: str) -> None:
    con.execute("INSTALL aws; INSTALL httpfs; INSTALL iceberg;")
    con.execute("LOAD aws; LOAD httpfs; LOAD iceberg;")
    con.execute("CREATE OR REPLACE SECRET aws_creds (TYPE s3, PROVIDER credential_chain);")
    con.execute(f"ATTACH '{arn}' AS lake (TYPE iceberg, ENDPOINT_TYPE s3_tables);")


def _terraform_output(name: str) -> str:
    return subprocess.check_output(["terraform", "output", "-raw", name], cwd=TF_DIR).decode().strip()


def main() -> int:
    arn = _terraform_output("table_bucket_arn")
    con = duckdb.connect()
    _attach(con, arn)

    # Warm up - first query primes the catalog cache.
    con.execute("SELECT COUNT(*) FROM lake.airquality.measurements").fetchone()

    rows = []
    for name, sql in QUERIES:
        durations: list[float] = []
        for _ in range(ITERATIONS):
            start = time.perf_counter()
            con.execute(sql).fetchall()
            durations.append((time.perf_counter() - start) * 1000)
        rows.append(
            {
                "name": name,
                "min_ms": round(min(durations), 1),
                "mean_ms": round(statistics.mean(durations), 1),
                "max_ms": round(max(durations), 1),
                "p50_ms": round(statistics.median(durations), 1),
            }
        )
        print(f"{name}: {rows[-1]}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w") as fh:
        fh.write("# Lakehouse query latency\n\n")
        fh.write(f"Captured {ITERATIONS} runs per query against the deployed lakehouse.\n\n")
        fh.write("| Query | Min (ms) | Median (ms) | Mean (ms) | Max (ms) |\n")
        fh.write("|---|---:|---:|---:|---:|\n")
        for row in rows:
            fh.write(f"| `{row['name']}` | {row['min_ms']} | {row['p50_ms']} | {row['mean_ms']} | {row['max_ms']} |\n")
        fh.write("\nRaw JSON:\n\n")
        fh.write("```json\n")
        fh.write(json.dumps(rows, indent=2))
        fh.write("\n```\n")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
