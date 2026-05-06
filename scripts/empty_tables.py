"""Empty the lakehouse tables so `terraform destroy` can drop them cleanly.

S3 Tables doesn't let you delete a table that still holds data via the
DeleteTable API the AWS provider calls. Easiest workaround is to truncate via
DuckDB before tearing down the rest of the stack.

Run with::

    uv run python scripts/empty_tables.py
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
TF_DIR = ROOT / "infrastructure"


def _terraform_outputs() -> dict[str, str]:
    raw = subprocess.check_output(["terraform", "output", "-json"], cwd=TF_DIR)
    return {k: v["value"] for k, v in json.loads(raw).items()}


def main() -> int:
    outputs = _terraform_outputs()
    arn = outputs["table_bucket_arn"]
    namespace = outputs["namespace"]

    con = duckdb.connect()
    con.execute("INSTALL aws; INSTALL httpfs; INSTALL iceberg;")
    con.execute("LOAD aws; LOAD httpfs; LOAD iceberg;")
    con.execute("CREATE OR REPLACE SECRET aws_creds (TYPE s3, PROVIDER credential_chain);")
    con.execute(f"ATTACH '{arn}' AS lake (TYPE iceberg, ENDPOINT_TYPE s3_tables);")

    tables = con.execute(
        f"SELECT table_name FROM duckdb_tables() WHERE schema_name = '{namespace}' AND database_name = 'lake'"
    ).fetchall()

    if not tables:
        print("no tables to empty")
        return 0

    for (table,) in tables:
        full = f"lake.{namespace}.{table}"
        before = con.execute(f"SELECT COUNT(*) FROM {full}").fetchone()[0]
        if before == 0:
            print(f"{full}: already empty")
            continue
        con.execute(f"DELETE FROM {full}")
        after = con.execute(f"SELECT COUNT(*) FROM {full}").fetchone()[0]
        print(f"{full}: {before} -> {after}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
