-- =============================================================================
-- 05_local_to_cloud.sql - migrate a local DuckDB database to S3 Tables
-- =============================================================================
-- The story: you've been prototyping in a local .duckdb file, and you're ready
-- to push everything to managed Iceberg in one command.
--
-- Run scripts/seed_local.py first to populate /tmp/openaq_local.duckdb with a
-- handful of stations and a few days of data.

-- Attach the local prototype as `local`, alongside the cloud catalog `lake`.
ATTACH '/tmp/openaq_local.duckdb' AS local (READ_ONLY);

-- Sanity check - what's in the local file?
SELECT 'measurements' AS source, COUNT(*) AS rows FROM local.measurements
UNION ALL
SELECT 'locations', COUNT(*) FROM local.locations;

-- Make sure the destination namespace exists. CREATE SCHEMA IF NOT EXISTS is
-- a one-liner against the S3 Tables catalog.
CREATE SCHEMA IF NOT EXISTS lake.airquality_local;

-- The migration. COPY FROM DATABASE walks every table in `local` and writes
-- it into the destination catalog/schema in one statement. Each destination
-- table inherits the source's schema; partition spec is left empty (which is
-- exactly what we want for DuckDB-driven UPDATE/DELETE).
COPY FROM DATABASE local TO lake (SCHEMA airquality_local);

-- Verify what landed.
SHOW TABLES FROM lake.airquality_local;

SELECT
    parameter,
    COUNT(*) AS rows,
    MIN(datetime) AS earliest,
    MAX(datetime) AS latest
FROM lake.airquality_local.measurements
GROUP BY parameter
ORDER BY rows DESC;

-- Optional: drop the staged copy once you're done validating.
-- DROP SCHEMA lake.airquality_local CASCADE;
