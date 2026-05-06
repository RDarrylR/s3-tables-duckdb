"""Local DuckDB query API for the frontend.

Runs an http.server on localhost:8000 with two endpoints:

    GET  /api/health  -> {"ok": true, "table_bucket_arn": "..."}
    POST /api/query   -> {"columns": [{"name", "type"}, ...], "rows": [{...}, ...]}

The Vite dev server proxies /api/* here. Keeping the API stdlib-only avoids
adding fastapi/uvicorn just for a laptop tool.

Run with::

    uv run python scripts/local_api.py

Stop with Ctrl+C.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import date, datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
TF_DIR = ROOT / "infrastructure"
HOST = "127.0.0.1"
PORT = 8000


def _terraform_output(name: str) -> str:
    return subprocess.check_output(["terraform", "output", "-raw", name], cwd=TF_DIR).decode().strip()


def _build_connection() -> tuple[duckdb.DuckDBPyConnection, str]:
    arn = _terraform_output("table_bucket_arn")
    con = duckdb.connect()
    con.execute("INSTALL aws; INSTALL httpfs; INSTALL iceberg;")
    con.execute("LOAD aws; LOAD httpfs; LOAD iceberg;")
    con.execute("CREATE OR REPLACE SECRET aws_creds (TYPE s3, PROVIDER credential_chain);")
    con.execute(f"ATTACH '{arn}' AS lake (TYPE iceberg, ENDPOINT_TYPE s3_tables);")
    return con, arn


CON, TABLE_BUCKET_ARN = _build_connection()


def _to_jsonable(value):
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, bytes):
        return value.hex()
    return value


class Handler(BaseHTTPRequestHandler):
    def _set_headers(self, status: int = 200, body_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", body_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def _write_json(self, payload, status: int = 200) -> None:
        self._set_headers(status)
        self.wfile.write(json.dumps(payload, default=_to_jsonable).encode("utf-8"))

    def do_OPTIONS(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler convention)
        self._set_headers(204)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/api/health":
            self._write_json({"ok": True, "table_bucket_arn": TABLE_BUCKET_ARN})
            return
        self._write_json({"error": "not found"}, status=404)

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/api/query":
            self._write_json({"error": "not found"}, status=404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
        except json.JSONDecodeError as exc:
            self._set_headers(400, "text/plain")
            self.wfile.write(f"invalid JSON: {exc}".encode())
            return

        sql = (body or {}).get("sql", "").strip()
        if not sql:
            self._set_headers(400, "text/plain")
            self.wfile.write(b"missing 'sql' in request body")
            return

        try:
            cursor = CON.execute(sql)
            description = cursor.description or []
            columns = [{"name": col[0], "type": str(col[1])} for col in description]
            raw_rows = cursor.fetchall()
            rows = [
                {col["name"]: _to_jsonable(value) for col, value in zip(columns, row, strict=True)}
                for row in raw_rows
            ]
            self._write_json({"columns": columns, "rows": rows})
        except duckdb.Error as exc:
            self._set_headers(500, "text/plain")
            self.wfile.write(f"DuckDB error: {exc}".encode())

    def log_message(self, format, *args) -> None:  # noqa: A002
        sys.stderr.write(f"[local_api] {self.address_string()} - {format % args}\n")


def main() -> int:
    print(f"local_api: serving DuckDB queries on http://{HOST}:{PORT}")
    print(f"           table bucket: {TABLE_BUCKET_ARN}")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
