"""OpenAQ source fetcher.

Builds a list of S3 keys to try, downloads them in parallel, and parses the
resulting daily gzipped CSVs into measurement and location records.

The public archive bucket layout is::

    records/csv.gz/locationid=<N>/year=<YYYY>/month=<MM>/location-<N>-<YYYYMMDD>.csv.gz

Not every station has data for every day, so we tolerate 404s rather than
failing the whole batch.
"""

from __future__ import annotations

import csv
import gzip
import io
import random
import time
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta

import boto3
from aws_lambda_powertools import Logger, Tracer
from botocore.config import Config
from botocore.exceptions import ClientError

logger = Logger(child=True)
tracer = Tracer()

# OpenAQ station IDs are sparsely populated - most random IDs in the upper range
# return 404 for recent dates because the station has been decommissioned. The
# 1-50000 band has the highest density of currently-reporting sensors.
MIN_STATION_ID = 1
MAX_STATION_ID = 50_000


@dataclass(frozen=True)
class IngestPlan:
    station_ids: list[int]
    s3_keys: list[str]


@dataclass
class FetchResult:
    attempted: int = 0
    succeeded: int = 0
    missing: int = 0
    bytes_downloaded: int = 0
    measurements: list[dict] = field(default_factory=list)
    locations: dict[int, dict] = field(default_factory=dict)


def build_plan(stations: int, days: int, seed: int | None = None) -> IngestPlan:
    """Pick station IDs and the S3 keys covering the most recent ``days``."""
    rng = random.Random(seed)
    station_ids = sorted(rng.sample(range(MIN_STATION_ID, MAX_STATION_ID), stations))

    today = date.today()
    target_days = [today - timedelta(days=offset) for offset in range(1, days + 1)]

    keys = [_key_for(station_id, day) for station_id in station_ids for day in target_days]
    return IngestPlan(station_ids=station_ids, s3_keys=keys)


def _key_for(station_id: int, day: date) -> str:
    return (
        f"records/csv.gz/locationid={station_id}/"
        f"year={day.year}/month={day.month:02d}/"
        f"location-{station_id}-{day.strftime('%Y%m%d')}.csv.gz"
    )


@tracer.capture_method
def fetch_records(bucket: str, keys: Iterable[str], max_workers: int = 128) -> FetchResult:
    """Download keys in parallel, parse, and accumulate measurements + locations."""
    keys_list = list(keys)
    result = FetchResult(attempted=len(keys_list))

    s3 = boto3.client(
        "s3",
        config=Config(
            max_pool_connections=max_workers,
            retries={"max_attempts": 3, "mode": "standard"},
            user_agent_extra="openaq-lakehouse-ingester/0.1",
        ),
    )

    started = time.monotonic()
    ingested_at = datetime.now(tz=UTC)

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {pool.submit(_get_object, s3, bucket, key): key for key in keys_list}
        for future in as_completed(futures):
            payload = future.result()
            if payload is None:
                result.missing += 1
                continue
            result.succeeded += 1
            result.bytes_downloaded += len(payload)
            _parse_into(payload, result, ingested_at)

    logger.info(
        "fetch complete",
        extra={
            "attempted": result.attempted,
            "succeeded": result.succeeded,
            "missing": result.missing,
            "bytes": result.bytes_downloaded,
            "elapsed_s": round(time.monotonic() - started, 2),
        },
    )
    return result


def _get_object(s3, bucket: str, key: str) -> bytes | None:
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        return response["Body"].read()
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code")
        if code in {"NoSuchKey", "404", "AccessDenied"}:
            return None
        raise


def _parse_into(payload: bytes, result: FetchResult, ingested_at: datetime) -> None:
    with gzip.open(io.BytesIO(payload), "rt", encoding="utf-8") as gz:
        reader = csv.DictReader(gz)
        for row in reader:
            try:
                location_id = int(row["location_id"])
                value = float(row["value"])
                lat = _maybe_float(row.get("lat"))
                lon = _maybe_float(row.get("lon"))
                dt = _parse_iso(row["datetime"])
            except (KeyError, ValueError, TypeError):
                continue

            result.measurements.append(
                {
                    "location_id": location_id,
                    "sensors_id": _maybe_int(row.get("sensors_id")),
                    "location": row.get("location") or None,
                    "datetime": dt,
                    "lat": lat,
                    "lon": lon,
                    "parameter": row.get("parameter") or "unknown",
                    "units": row.get("units") or None,
                    "value": value,
                    "ingested_at": ingested_at,
                }
            )

            entry = result.locations.get(location_id)
            if entry is None:
                result.locations[location_id] = {
                    "location_id": location_id,
                    "location": row.get("location") or None,
                    "country": _country_from_location(row.get("location")),
                    "lat": lat,
                    "lon": lon,
                    "first_seen_at": dt,
                    "last_seen_at": dt,
                    "measurement_count": 1,
                }
            else:
                entry["measurement_count"] += 1
                if dt > entry["last_seen_at"]:
                    entry["last_seen_at"] = dt
                if dt < entry["first_seen_at"]:
                    entry["first_seen_at"] = dt


def _maybe_float(value: str | None) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def _maybe_int(value: str | None) -> int | None:
    if value in (None, ""):
        return None
    try:
        return int(value)
    except ValueError:
        return None


def _parse_iso(value: str) -> datetime:
    # OpenAQ timestamps include offsets like "+08:00". fromisoformat handles this
    # natively from python 3.11+.
    return datetime.fromisoformat(value).astimezone(UTC)


def _country_from_location(location: str | None) -> str | None:
    """OpenAQ doesn't include a country column, so we leave this blank for now.
    A future enhancement would join against the OpenAQ /v3/locations API."""
    return None
