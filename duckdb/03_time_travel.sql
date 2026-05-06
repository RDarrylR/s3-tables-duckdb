-- =============================================================================
-- 03_time_travel.sql - snapshots, version pinning, and "what did we know when"
-- =============================================================================
-- Every write to an Iceberg table creates a new snapshot. The S3 Tables snapshot
-- management config keeps snapshots for max_snapshot_age_hours (we set 168 in
-- terraform). Within that window, you can query any historical state.

-- List every snapshot for the measurements table.
SELECT *
FROM iceberg_snapshots('lake.airquality.measurements')
ORDER BY committed_at DESC;

-- How many rows did we have at each snapshot? (The cheap way: fetch counts at
-- each snapshot ID. DuckDB pushes the snapshot pin into the scan.)
SELECT
    snapshot_id,
    committed_at,
    (
        SELECT COUNT(*)
        FROM lake.airquality.measurements
        AT (VERSION => snapshot_id)
    ) AS rows_at_snapshot
FROM iceberg_snapshots('lake.airquality.measurements')
ORDER BY committed_at;

-- "What did the table look like an hour ago?" - useful for forensic re-runs of
-- a downstream pipeline that consumed bad data.
SELECT *
FROM lake.airquality.measurements
AT (TIMESTAMP => NOW() - INTERVAL 1 HOUR)
LIMIT 20;

-- Diff: which rows landed in the most recent commit?
WITH snapshots AS (
    SELECT snapshot_id
    FROM iceberg_snapshots('lake.airquality.measurements')
    ORDER BY committed_at DESC
    LIMIT 2
),
latest AS (SELECT MAX(snapshot_id) AS s FROM snapshots),
previous AS (SELECT MIN(snapshot_id) AS s FROM snapshots)
SELECT *
FROM lake.airquality.measurements AT (VERSION => (SELECT s FROM latest))
EXCEPT
SELECT *
FROM lake.airquality.measurements AT (VERSION => (SELECT s FROM previous))
LIMIT 50;

-- Manifest-level metadata - what files back this snapshot?
SELECT *
FROM iceberg_metadata('lake.airquality.measurements')
LIMIT 20;
