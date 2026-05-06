"""OpenAQ ingester Lambda entry point.

Reads daily gzipped CSVs from the public openaq-data-archive bucket, normalizes
them, and appends rows to two Iceberg tables in an S3 Tables bucket.

Event shape::

    {
        "stations": 500,    # how many station IDs to sample
        "days": 30,         # how many days back from today to read per station
        "seed": 42          # optional, makes station sampling reproducible
    }

Returns counts so the caller (CLI or a chained step function) can verify
progress::

    {
        "files_attempted": 15000,
        "files_succeeded": 14217,
        "measurements_written": 312445,
        "locations_upserted": 487,
        "elapsed_seconds": 312.4
    }
"""

from __future__ import annotations

import os
import time
from typing import Any

from aws_lambda_powertools import Logger, Metrics, Tracer
from aws_lambda_powertools.metrics import MetricUnit
from aws_lambda_powertools.utilities.typing import LambdaContext
from iceberg_writer import IcebergWriter
from openaq import IngestPlan, build_plan, fetch_records

logger = Logger()
tracer = Tracer()
metrics = Metrics()

TABLE_BUCKET_ARN = os.environ["TABLE_BUCKET_ARN"]
NAMESPACE = os.environ["NAMESPACE"]
MEASUREMENTS_TABLE = os.environ["MEASUREMENTS_TABLE"]
LOCATIONS_TABLE = os.environ["LOCATIONS_TABLE"]
SOURCE_BUCKET = os.environ["OPENAQ_SOURCE_BUCKET"]
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")


@logger.inject_lambda_context(log_event=True)
@tracer.capture_lambda_handler
@metrics.log_metrics(capture_cold_start_metric=True)
def lambda_handler(event: dict[str, Any], context: LambdaContext) -> dict[str, Any]:
    started = time.monotonic()

    stations = int(event.get("stations", 500))
    days = int(event.get("days", 1))
    seed = event.get("seed")

    plan: IngestPlan = build_plan(stations=stations, days=days, seed=seed)
    logger.info(
        "ingest plan ready",
        extra={"stations": len(plan.station_ids), "files": len(plan.s3_keys), "days": days},
    )

    metrics.add_dimension(name="Namespace", value=NAMESPACE)
    metrics.add_metric(name="FilesPlanned", unit=MetricUnit.Count, value=len(plan.s3_keys))

    fetch_result = fetch_records(bucket=SOURCE_BUCKET, keys=plan.s3_keys, max_workers=128)
    metrics.add_metric(name="FilesAttempted", unit=MetricUnit.Count, value=fetch_result.attempted)
    metrics.add_metric(name="FilesSucceeded", unit=MetricUnit.Count, value=fetch_result.succeeded)
    metrics.add_metric(name="FilesMissing", unit=MetricUnit.Count, value=fetch_result.missing)
    metrics.add_metric(name="BytesDownloaded", unit=MetricUnit.Bytes, value=fetch_result.bytes_downloaded)

    if not fetch_result.measurements:
        logger.warning("no measurements fetched - nothing to write")
        return _build_response(fetch_result, 0, 0, started)

    writer = IcebergWriter(
        table_bucket_arn=TABLE_BUCKET_ARN,
        namespace=NAMESPACE,
        region=AWS_REGION,
    )

    measurements_written = writer.append_measurements(
        table_name=MEASUREMENTS_TABLE,
        records=fetch_result.measurements,
    )
    metrics.add_metric(name="MeasurementsWritten", unit=MetricUnit.Count, value=measurements_written)

    locations_upserted = writer.upsert_locations(
        table_name=LOCATIONS_TABLE,
        locations=fetch_result.locations,
    )
    metrics.add_metric(name="LocationsUpserted", unit=MetricUnit.Count, value=locations_upserted)

    return _build_response(fetch_result, measurements_written, locations_upserted, started)


def _build_response(
    fetch_result: Any,
    measurements_written: int,
    locations_upserted: int,
    started: float,
) -> dict[str, Any]:
    elapsed = round(time.monotonic() - started, 2)
    return {
        "files_attempted": fetch_result.attempted,
        "files_succeeded": fetch_result.succeeded,
        "files_missing": fetch_result.missing,
        "measurements_written": measurements_written,
        "locations_upserted": locations_upserted,
        "elapsed_seconds": elapsed,
    }
