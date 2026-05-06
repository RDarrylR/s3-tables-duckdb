"""Smoke tests for the Lambda entrypoint. Mocks the network-touching pieces."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import patch

import pytest
from openaq import FetchResult


class _FakeContext:
    function_name = "test-fn"
    function_version = "$LATEST"
    invoked_function_arn = "arn:aws:lambda:us-east-1:000000000000:function:test-fn"
    memory_limit_in_mb = 1769
    aws_request_id = "00000000-0000-0000-0000-000000000000"
    log_group_name = "/aws/lambda/test-fn"
    log_stream_name = "test-stream"

    def get_remaining_time_in_millis(self) -> int:
        return 900_000


@pytest.fixture
def empty_fetch_result():
    return FetchResult()


def test_handler_short_circuits_with_no_measurements(empty_fetch_result):
    import handler

    with (
        patch.object(handler, "fetch_records", return_value=empty_fetch_result),
        patch.object(handler, "IcebergWriter") as mock_writer_cls,
    ):
        response = handler.lambda_handler({"stations": 1, "days": 1, "seed": 1}, _FakeContext())

    mock_writer_cls.assert_not_called()
    assert response["measurements_written"] == 0
    assert response["locations_upserted"] == 0
    assert response["files_attempted"] == 0


def test_handler_writes_when_data_present():
    import handler

    fetch = FetchResult(attempted=10, succeeded=8, missing=2, bytes_downloaded=1024)
    fetch.measurements = [{"location_id": 1}] * 8
    fetch.locations = {1: {"location_id": 1}}

    fake_writer = SimpleNamespace(
        append_measurements=lambda table_name, records: len(records),
        upsert_locations=lambda table_name, locations: len(locations),
    )

    with (
        patch.object(handler, "fetch_records", return_value=fetch),
        patch.object(handler, "IcebergWriter", return_value=fake_writer),
    ):
        response = handler.lambda_handler({"stations": 10, "days": 1, "seed": 1}, _FakeContext())

    assert response["files_attempted"] == 10
    assert response["files_succeeded"] == 8
    assert response["measurements_written"] == 8
    assert response["locations_upserted"] == 1
