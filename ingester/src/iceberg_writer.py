"""PyIceberg writer for the S3 Tables Iceberg REST endpoint.

Two operations: append measurements, upsert locations. Both are append-only at
the Iceberg level for now; rare row-level updates against the locations table
are handled via DELETE-then-INSERT from DuckDB (see duckdb/04_writes.sql).
"""

from __future__ import annotations

import pyarrow as pa
from aws_lambda_powertools import Logger, Tracer
from pyiceberg.catalog import load_catalog
from pyiceberg.table import Table

logger = Logger(child=True)
tracer = Tracer()


# Arrow schemas - keep these in lock-step with the Iceberg schemas defined in
# infrastructure/s3tables.tf. PyIceberg will reject writes if the columns don't
# line up by name and type.
MEASUREMENTS_ARROW_SCHEMA = pa.schema(
    [
        pa.field("location_id", pa.int64(), nullable=False),
        pa.field("sensors_id", pa.int64()),
        pa.field("location", pa.string()),
        pa.field("datetime", pa.timestamp("us", tz="UTC"), nullable=False),
        pa.field("lat", pa.float64()),
        pa.field("lon", pa.float64()),
        pa.field("parameter", pa.string(), nullable=False),
        pa.field("units", pa.string()),
        pa.field("value", pa.float64()),
        pa.field("ingested_at", pa.timestamp("us", tz="UTC"), nullable=False),
    ]
)

LOCATIONS_ARROW_SCHEMA = pa.schema(
    [
        pa.field("location_id", pa.int64(), nullable=False),
        pa.field("location", pa.string()),
        pa.field("country", pa.string()),
        pa.field("lat", pa.float64()),
        pa.field("lon", pa.float64()),
        pa.field("first_seen_at", pa.timestamp("us", tz="UTC")),
        pa.field("last_seen_at", pa.timestamp("us", tz="UTC"), nullable=False),
        pa.field("measurement_count", pa.int64()),
    ]
)


class IcebergWriter:
    """Thin wrapper around PyIceberg's REST catalog talking to S3 Tables."""

    def __init__(self, table_bucket_arn: str, namespace: str, region: str) -> None:
        self.namespace = namespace
        self._catalog = load_catalog(
            "s3tables",
            **{
                "type": "rest",
                "warehouse": table_bucket_arn,
                "uri": f"https://s3tables.{region}.amazonaws.com/iceberg",
                "rest.sigv4-enabled": "true",
                "rest.signing-name": "s3tables",
                "rest.signing-region": region,
            },
        )
        logger.debug("catalog loaded", extra={"warehouse": table_bucket_arn})

    @tracer.capture_method
    def append_measurements(self, table_name: str, records: list[dict]) -> int:
        if not records:
            return 0
        arrow_table = pa.Table.from_pylist(records, schema=MEASUREMENTS_ARROW_SCHEMA)
        return self._append(table_name, arrow_table)

    @tracer.capture_method
    def upsert_locations(self, table_name: str, locations: dict[int, dict]) -> int:
        if not locations:
            return 0
        arrow_table = pa.Table.from_pylist(list(locations.values()), schema=LOCATIONS_ARROW_SCHEMA)
        return self._append(table_name, arrow_table)

    def _append(self, table_name: str, arrow_table: pa.Table) -> int:
        table = self._load_table(table_name)
        table.append(arrow_table)
        rows = arrow_table.num_rows
        logger.info(
            "appended to iceberg table",
            extra={"table": table_name, "rows": rows, "bytes": arrow_table.nbytes},
        )
        return rows

    def _load_table(self, table_name: str) -> Table:
        return self._catalog.load_table(f"{self.namespace}.{table_name}")
