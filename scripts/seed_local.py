"""Build a small local DuckDB database from the OpenAQ archive.

Used by duckdb/05_local_to_cloud.sql to demo the COPY FROM DATABASE migration.
Mirrors the schema of the cloud tables so the copy lands cleanly.

Run with::

    uv run python scripts/seed_local.py
"""

from __future__ import annotations

import gzip
import io
import sys
from pathlib import Path

import boto3
from botocore import UNSIGNED
from botocore.config import Config

import duckdb

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ingester" / "src"))

from openaq import build_plan  # noqa: E402

LOCAL_DB = "/tmp/openaq_local.duckdb"
SOURCE_BUCKET = "openaq-data-archive"


def main() -> int:
    plan = build_plan(stations=20, days=7, seed=2026)
    print(f"plan: {len(plan.s3_keys)} keys for {len(plan.station_ids)} stations")

    s3 = boto3.client("s3", config=Config(signature_version=UNSIGNED))

    Path(LOCAL_DB).unlink(missing_ok=True)
    con = duckdb.connect(LOCAL_DB)
    con.execute("""
        CREATE TABLE measurements (
            location_id  BIGINT NOT NULL,
            sensors_id   BIGINT,
            location     VARCHAR,
            datetime     TIMESTAMPTZ NOT NULL,
            lat          DOUBLE,
            lon          DOUBLE,
            parameter    VARCHAR NOT NULL,
            units        VARCHAR,
            value        DOUBLE,
            ingested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    con.execute("""
        CREATE TABLE locations (
            location_id        BIGINT NOT NULL,
            location           VARCHAR,
            country            VARCHAR,
            lat                DOUBLE,
            lon                DOUBLE,
            first_seen_at      TIMESTAMPTZ,
            last_seen_at       TIMESTAMPTZ NOT NULL,
            measurement_count  BIGINT
        )
    """)

    rows_landed = 0
    files_landed = 0
    for key in plan.s3_keys:
        try:
            response = s3.get_object(Bucket=SOURCE_BUCKET, Key=key)
        except s3.exceptions.NoSuchKey:
            continue
        except Exception:
            continue

        files_landed += 1
        payload = gzip.decompress(response["Body"].read())
        rel = duckdb.read_csv(io.BytesIO(payload), header=True)  # noqa: F841 -- referenced by `FROM rel` in the SQL below via DuckDB replacement scan
        before = con.execute("SELECT COUNT(*) FROM measurements").fetchone()[0]
        con.execute(
            """
            INSERT INTO measurements
            SELECT
                CAST(location_id AS BIGINT),
                TRY_CAST(sensors_id AS BIGINT),
                location,
                CAST(datetime AS TIMESTAMPTZ),
                TRY_CAST(lat AS DOUBLE),
                TRY_CAST(lon AS DOUBLE),
                parameter,
                units,
                TRY_CAST(value AS DOUBLE),
                NOW()
            FROM rel
            WHERE TRY_CAST(value AS DOUBLE) IS NOT NULL
            """
        )
        rows_landed += con.execute("SELECT COUNT(*) FROM measurements").fetchone()[0] - before

    con.execute(
        """
        INSERT INTO locations
        SELECT
            location_id,
            ANY_VALUE(location) AS location,
            NULL AS country,
            ANY_VALUE(lat) AS lat,
            ANY_VALUE(lon) AS lon,
            MIN(datetime) AS first_seen_at,
            MAX(datetime) AS last_seen_at,
            COUNT(*) AS measurement_count
        FROM measurements
        GROUP BY location_id
        """
    )

    print(f"seeded {LOCAL_DB}: {files_landed} files, {rows_landed} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
