# Lakehouse query latency

Captured 5 runs per query against the deployed lakehouse.

| Query | Min (ms) | Median (ms) | Mean (ms) | Max (ms) |
|---|---:|---:|---:|---:|
| `count_all` | 73.4 | 79.1 | 96.0 | 172.6 |
| `pm25_last_7d` | 92.2 | 94.0 | 257.5 | 846.8 |
| `param_breakdown` | 86.5 | 95.0 | 126.7 | 262.9 |
| `join_locations` | 178.2 | 194.3 | 435.7 | 1325.8 |
| `rolling_o3` | 87.7 | 100.6 | 108.6 | 150.4 |

Raw JSON:

```json
[
  {
    "name": "count_all",
    "min_ms": 73.4,
    "mean_ms": 96.0,
    "max_ms": 172.6,
    "p50_ms": 79.1
  },
  {
    "name": "pm25_last_7d",
    "min_ms": 92.2,
    "mean_ms": 257.5,
    "max_ms": 846.8,
    "p50_ms": 94.0
  },
  {
    "name": "param_breakdown",
    "min_ms": 86.5,
    "mean_ms": 126.7,
    "max_ms": 262.9,
    "p50_ms": 95.0
  },
  {
    "name": "join_locations",
    "min_ms": 178.2,
    "mean_ms": 435.7,
    "max_ms": 1325.8,
    "p50_ms": 194.3
  },
  {
    "name": "rolling_o3",
    "min_ms": 87.7,
    "mean_ms": 108.6,
    "max_ms": 150.4,
    "p50_ms": 100.6
  }
]
```
