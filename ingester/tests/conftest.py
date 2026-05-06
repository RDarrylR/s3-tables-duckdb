"""Shared pytest fixtures and path setup."""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Make `ingester/src` importable as top-level modules without a package install.
SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

# Lambda env vars expected by handler.py at import time.
os.environ.setdefault("TABLE_BUCKET_ARN", "arn:aws:s3tables:us-east-1:000000000000:bucket/test")
os.environ.setdefault("NAMESPACE", "airquality")
os.environ.setdefault("MEASUREMENTS_TABLE", "measurements")
os.environ.setdefault("LOCATIONS_TABLE", "locations")
os.environ.setdefault("OPENAQ_SOURCE_BUCKET", "openaq-data-archive")
os.environ.setdefault("AWS_REGION", "us-east-1")
os.environ.setdefault("POWERTOOLS_SERVICE_NAME", "test")
os.environ.setdefault("POWERTOOLS_METRICS_NAMESPACE", "TestNamespace")


import pytest  # noqa: E402  pytest must import after env setup above


@pytest.fixture(autouse=True)
def _reset_powertools_metrics():
    """Powertools Metrics keeps a process-wide singleton; reset between tests."""
    from aws_lambda_powertools import Metrics

    metrics = Metrics()
    metrics.clear_metrics()
    metrics.clear_default_dimensions()
    yield
    metrics.clear_metrics()
    metrics.clear_default_dimensions()
