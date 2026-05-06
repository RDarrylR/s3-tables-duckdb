# Frontend

A small React + Vite app that lets you click around the lakehouse from a browser.

It's a thin client over a local Python sidecar that runs DuckDB against the same S3 Tables catalog the rest of the project uses. The sidecar (`scripts/local_api.py`) talks to AWS via your usual credential chain; the browser just sends SQL strings and renders the JSON response. No browser-side AWS credentials, no CORS dance with the S3 Tables endpoint.

## Run it

From the project root:

```bash
# 1. Start the local DuckDB API on http://localhost:8000
make local-api

# 2. In a second terminal, start Vite on http://localhost:5173
make frontend
```

Open http://localhost:5173. The sidebar has pre-canned queries; you can also edit the SQL freely. Cmd+Enter (Ctrl+Enter on non-mac) runs whatever's in the editor.

## Layout

```
frontend/
|-- index.html
|-- package.json
|-- vite.config.js          # /api/* proxies to localhost:8000
`-- src/
    |-- App.jsx
    |-- api.js
    |-- queries.js          # pre-canned queries
    |-- styles.css
    `-- components/
        |-- LineChart.jsx
        `-- ResultTable.jsx
```

## Why a sidecar instead of DuckDB-Wasm?

DuckDB-Wasm can absolutely query Iceberg, including S3 Tables (see [DuckDB's "Iceberg in the browser" post](https://duckdb.org/2025/12/16/iceberg-in-the-browser)). What it can't do cleanly is:

- Pick up SigV4-signed credentials from your local AWS profile without putting them in a place the browser can read.
- Avoid embedding credentials in the URL hash for sharing, which the DuckDB team has flagged as a security concern.
- Negotiate CORS with the S3 Tables Iceberg REST endpoint, which is server-to-server today.

For a laptop dev tool the sidecar is the simpler, safer choice. The Python process is the credential boundary; the browser only sees query results.

If you want to swap to DuckDB-Wasm anyway, replace `src/api.js` with a `@duckdb/duckdb-wasm` instance and follow the DuckDB Iceberg-in-the-browser guide for credentials. The query strings in `src/queries.js` work unchanged.
