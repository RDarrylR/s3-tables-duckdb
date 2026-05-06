# Lakehouse query latency

Captured 5 runs per query against the deployed lakehouse.

| Query | Min (ms) | Median (ms) | Mean (ms) | Max (ms) |
|---|---:|---:|---:|---:|
| `count_all` | 71.2 | 83.3 | 99.9 | 180.9 |
| `pm25_last_7d` | 96.7 | 110.0 | 688.2 | 2936.5 |
| `param_breakdown` | 96.1 | 133.5 | 375.3 | 1350.8 |
| `join_locations` | 206.9 | 243.3 | 1131.5 | 4661.3 |
| `rolling_o3` | 99.9 | 144.4 | 216.6 | 542.2 |

Raw JSON:

```json
[
  {
    "name": "count_all",
    "min_ms": 71.2,
    "mean_ms": 99.9,
    "max_ms": 180.9,
    "p50_ms": 83.3
  },
  {
    "name": "pm25_last_7d",
    "min_ms": 96.7,
    "mean_ms": 688.2,
    "max_ms": 2936.5,
    "p50_ms": 110.0
  },
  {
    "name": "param_breakdown",
    "min_ms": 96.1,
    "mean_ms": 375.3,
    "max_ms": 1350.8,
    "p50_ms": 133.5
  },
  {
    "name": "join_locations",
    "min_ms": 206.9,
    "mean_ms": 1131.5,
    "max_ms": 4661.3,
    "p50_ms": 243.3
  },
  {
    "name": "rolling_o3",
    "min_ms": 99.9,
    "mean_ms": 216.6,
    "max_ms": 542.2,
    "p50_ms": 144.4
  }
]
```
