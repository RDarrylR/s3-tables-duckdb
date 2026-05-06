/**
 * Pre-canned queries shown in the sidebar. Each one's SQL is exactly what you
 * could paste into a duckdb shell after `make query`.
 */

export const PRESETS = [
  {
    id: 'overview',
    label: 'Lakehouse overview',
    sql: `SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT location_id) AS stations,
    COUNT(DISTINCT parameter) AS parameters,
    MIN(datetime) AS earliest,
    MAX(datetime) AS latest
FROM lake.airquality.measurements;`,
  },
  {
    id: 'parameters',
    label: 'Parameter mix',
    sql: `SELECT parameter, units, COUNT(*) AS readings, AVG(value) AS mean
FROM lake.airquality.measurements
GROUP BY parameter, units
ORDER BY readings DESC;`,
  },
  {
    id: 'pm25_top',
    label: 'Top PM2.5 stations (last 7d)',
    sql: `SELECT
    location_id,
    location,
    AVG(value) AS avg_pm25,
    COUNT(*) AS readings
FROM lake.airquality.measurements
WHERE parameter = 'pm25'
  AND datetime >= NOW() - INTERVAL 7 DAY
GROUP BY location_id, location
HAVING COUNT(*) >= 5
ORDER BY avg_pm25 DESC
LIMIT 25;`,
  },
  {
    id: 'pm25_trend',
    label: 'PM2.5 daily trend',
    sql: `SELECT
    DATE_TRUNC('day', datetime) AS day,
    AVG(value) AS avg_pm25,
    COUNT(*) AS readings
FROM lake.airquality.measurements
WHERE parameter = 'pm25'
GROUP BY day
ORDER BY day;`,
  },
  {
    id: 'snapshots',
    label: 'Iceberg snapshots',
    sql: `SELECT sequence_number, snapshot_id, timestamp_ms
FROM iceberg_snapshots('lake.airquality.measurements')
ORDER BY timestamp_ms DESC;`,
  },
  {
    id: 'time_travel',
    label: 'Count, one hour ago',
    sql: `SELECT COUNT(*) AS rows_one_hour_ago
FROM lake.airquality.measurements
AT (TIMESTAMP => NOW() - INTERVAL 1 HOUR);`,
  },
  {
    id: 'locations',
    label: 'Most active locations',
    sql: `SELECT location_id, location, country, measurement_count, last_seen_at
FROM lake.airquality.locations
ORDER BY measurement_count DESC
LIMIT 50;`,
  },
];
