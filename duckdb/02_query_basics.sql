-- =============================================================================
-- 02_query_basics.sql - typical analytical queries against the lakehouse
-- =============================================================================
-- Run after 01_setup.sql has attached the catalog.

-- Row count and date range so you know what you're working with.
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT location_id) AS stations,
    COUNT(DISTINCT parameter) AS parameters,
    MIN(datetime) AS earliest,
    MAX(datetime) AS latest
FROM lake.airquality.measurements;

-- Pollutant mix - what is this dataset actually measuring?
SELECT parameter, units, COUNT(*) AS readings
FROM lake.airquality.measurements
GROUP BY parameter, units
ORDER BY readings DESC;

-- Daily PM2.5 averages for the worst-polluted stations in the last 7 days.
SELECT
    location_id,
    location,
    DATE_TRUNC('day', datetime) AS day,
    AVG(value) AS avg_pm25
FROM lake.airquality.measurements
WHERE parameter = 'pm25'
  AND datetime >= NOW() - INTERVAL 7 DAY
GROUP BY location_id, location, day
HAVING AVG(value) > 35.0
ORDER BY avg_pm25 DESC
LIMIT 25;

-- Daily 24h rolling max ozone per station - shows DuckDB's window functions
-- working straight against Iceberg.
SELECT
    location,
    datetime,
    value,
    MAX(value) OVER (
        PARTITION BY location_id, parameter
        ORDER BY datetime
        RANGE BETWEEN INTERVAL 24 HOURS PRECEDING AND CURRENT ROW
    ) AS rolling_24h_max
FROM lake.airquality.measurements
WHERE parameter = 'o3'
ORDER BY location, datetime
LIMIT 50;

-- Join measurements against the slowly-changing locations table.
SELECT
    m.parameter,
    AVG(m.value) AS mean_value,
    COUNT(*) AS readings,
    COUNT(DISTINCT l.location_id) AS distinct_stations
FROM lake.airquality.measurements AS m
JOIN lake.airquality.locations    AS l USING (location_id)
WHERE l.measurement_count >= 100
GROUP BY m.parameter
ORDER BY mean_value DESC;
