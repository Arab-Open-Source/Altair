# Observability

Generated projects set `config.observability = true`, which adds two
endpoints before route dispatch:

- `GET /health` returns `{"status":"ok"}` and is suitable for liveness checks.
- `GET /metrics` serves Prometheus text with request counts and latency
  histograms. Database query counters are appended to the same response.

`config.health_path` and `config.metrics_path` change the paths.
`config.structured_logs = true` emits one JSON object per request with
method, path, status, duration and request id; cookies, Authorization and
bodies are never logged. The `RequestId` middleware honours an incoming
`X-Request-Id` and echoes it back.

Read-replica deployments expose per-target counters on `/metrics`:
`altair_db_queries_total{target="primary"}`
`altair_db_queries_total{target="replica"}` and
`altair_db_replica_failovers_total` (see `altair docs read_replicas`).
