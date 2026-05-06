"""Unit tests for the OpenAQ source layer."""

from __future__ import annotations

import gzip
from datetime import UTC, datetime

import pytest
from openaq import FetchResult, _parse_into, build_plan

SAMPLE_CSV = (
    "location_id,sensors_id,location,datetime,lat,lon,parameter,units,value\n"
    "10000,31850,Test Site,2026-04-01T01:00:00+00:00,39.5989,109.8119,pm10,µg/m³,136.0\n"
    "10000,31850,Test Site,2026-04-01T02:00:00+00:00,39.5989,109.8119,pm25,µg/m³,72.5\n"
    "10000,,Test Site,bad-timestamp,39.5989,109.8119,o3,ppm,0.04\n"  # malformed - skipped
    "10000,31850,Test Site,2026-04-01T03:00:00+00:00,39.5989,109.8119,no2,ppb,12.3\n"
)


def test_build_plan_is_deterministic_with_seed():
    plan_a = build_plan(stations=10, days=3, seed=42)
    plan_b = build_plan(stations=10, days=3, seed=42)
    assert plan_a.station_ids == plan_b.station_ids
    assert plan_a.s3_keys == plan_b.s3_keys


def test_build_plan_key_format():
    plan = build_plan(stations=1, days=1, seed=1)
    assert len(plan.s3_keys) == 1
    key = plan.s3_keys[0]
    assert key.startswith("records/csv.gz/locationid=")
    assert "/year=" in key and "/month=" in key
    assert key.endswith(".csv.gz")


def test_build_plan_count():
    plan = build_plan(stations=5, days=4, seed=1)
    assert len(plan.station_ids) == 5
    assert len(plan.s3_keys) == 5 * 4


def test_parse_into_skips_malformed_rows_and_aggregates_locations():
    payload = gzip.compress(SAMPLE_CSV.encode("utf-8"))
    result = FetchResult()
    ingested_at = datetime(2026, 5, 1, 12, 0, tzinfo=UTC)

    _parse_into(payload, result, ingested_at)

    assert len(result.measurements) == 3  # bad-timestamp row skipped
    assert {m["parameter"] for m in result.measurements} == {"pm10", "pm25", "no2"}
    assert all(m["ingested_at"] == ingested_at for m in result.measurements)

    assert 10000 in result.locations
    location = result.locations[10000]
    assert location["measurement_count"] == 3
    assert location["first_seen_at"] < location["last_seen_at"]


def test_parse_into_handles_empty_payload():
    payload = gzip.compress(b"location_id,sensors_id,location,datetime,lat,lon,parameter,units,value\n")
    result = FetchResult()
    _parse_into(payload, result, datetime.now(tz=UTC))
    assert result.measurements == []
    assert result.locations == {}


@pytest.mark.parametrize(
    "stations,days,expected",
    [
        (1, 1, 1),
        (10, 7, 70),
        (500, 30, 500 * 30),
    ],
)
def test_plan_size_scales(stations: int, days: int, expected: int):
    plan = build_plan(stations=stations, days=days, seed=1)
    assert len(plan.s3_keys) == expected
