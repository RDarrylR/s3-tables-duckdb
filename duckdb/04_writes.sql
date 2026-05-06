-- =============================================================================
-- 04_writes.sql - INSERT, UPDATE, DELETE patterns from DuckDB
-- =============================================================================
-- Heads up: DuckDB-Iceberg write support is version-sensitive. Up to
-- DuckDB 1.4.2, UPDATE and DELETE were limited to non-partitioned,
-- non-sorted tables and used merge-on-read positional deletes. DuckDB
-- 1.5.2 (April 2026) added updates and deletes from partitioned tables,
-- plus TRUNCATE and bucket partitions. Both tables in this project are
-- non-partitioned anyway, since that keeps the demo simple to follow.

-- ---------- INSERT ---------------------------------------------------------
-- Useful for backfilling synthesized records, or fixing a missed batch from
-- the ingester.

INSERT INTO lake.airquality.measurements VALUES (
    9999999,                              -- location_id
    NULL,                                 -- sensors_id
    'manual-correction',                  -- location
    TIMESTAMPTZ '2026-04-30 10:00:00+00', -- datetime
    NULL, NULL,                           -- lat, lon
    'pm25',                               -- parameter
    'ug/m3',                              -- units
    27.4,                                 -- value
    NOW()                                 -- ingested_at
);

-- ---------- UPDATE ---------------------------------------------------------
-- Fix a known sensor calibration error - one location reported PM10 in the
-- wrong unit for a window we know about. Multiplying by 1.0 and re-tagging
-- units shows the row-level UPDATE working end-to-end.

UPDATE lake.airquality.measurements
SET value = value / 1000.0,
    units = 'mg/m3'
WHERE location_id = 9999999
  AND parameter = 'pm10'
  AND units = 'ug/m3';

-- ---------- DELETE ---------------------------------------------------------
-- The ingester will sometimes pick up rows from a station that was later
-- flagged as faulty. Drop everything for that station from the last 24 hours.

DELETE FROM lake.airquality.measurements
WHERE location_id = 9999999
  AND datetime >= NOW() - INTERVAL 24 HOURS;

-- ---------- "Update with a bigger hammer" ---------------------------------
-- For a partitioned production table, UPDATE/DELETE wouldn't be available.
-- The standard workaround is: copy out, transform, copy back via a temporary
-- staging table. Demonstrated against the locations table.

CREATE OR REPLACE TEMP TABLE locations_fixed AS
SELECT
    location_id,
    -- normalize whitespace in location names
    TRIM(REGEXP_REPLACE(location, '\s+', ' ', 'g')) AS location,
    country, lat, lon,
    first_seen_at, last_seen_at, measurement_count
FROM lake.airquality.locations;

DELETE FROM lake.airquality.locations;

INSERT INTO lake.airquality.locations
SELECT * FROM locations_fixed;

-- Confirm the rewrite landed by walking the snapshot history.
SELECT snapshot_id, committed_at, summary
FROM iceberg_snapshots('lake.airquality.locations')
ORDER BY committed_at DESC
LIMIT 5;
