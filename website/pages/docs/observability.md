# Observability

Generated projects set `config.observability = true`, which serves two
endpoints before route dispatch — no controller or route needed:

- `GET /health` returns `{"status":"ok"}` and is suitable for liveness checks
  and the generated Docker `HEALTHCHECK`.
- `GET /metrics` serves Prometheus text (`text/plain; version=0.0.4`) with
  request counters and the database target counters appended.

Set them to false with `config.observability = false` if you do not want the
endpoints. `config.health_path` (default `/health`) and `config.metrics_path`
(default `/metrics`) change the paths.

## Request metrics

The `/metrics` response starts with process-local request counters:

```
# TYPE altair_http_requests_total counter
altair_http_requests_total ...
# TYPE altair_http_server_errors_total counter
altair_http_server_errors_total ...
# TYPE altair_http_request_duration_microseconds_total counter
altair_http_request_duration_microseconds_total ...
```

Server errors are requests that answered 5xx; duration is the accumulated
microseconds of completed requests. Counters are process-local.

## Database metrics

When a [read replica](/docs/read_replicas.html) is configured, the same
response appends per-target statement counters:

```
# TYPE altair_db_queries_total counter
altair_db_queries_total{target="primary"} ...
altair_db_queries_total{target="replica"} ...
# TYPE altair_db_replica_failovers_total counter
altair_db_replica_failovers_total ...
```

`QueryEvent#target` is `:primary` or `:replica` for every instrumented
statement, and replica failures are also logged under
`altair.record.replica`.

## Structured logs

`config.structured_logs = true` switches the per-request line to one JSON
object with method, path, status, duration and request id. The default
human-readable line is aligned and colored for terminals; see the
[Console guide](/docs/console.html) for its knobs (`logger_colors`,
`logger_timestamps`, `logger_compact`, `slow_request_threshold`).

Sensitive data is never logged: cookies, `Authorization` and request bodies
are excluded from diagnostics.

## Request ids

The `RequestId` middleware reads an incoming `X-Request-Id` header or assigns
one. It echoes the id back in the response header and appends it to the
request log line, so a log entry can be correlated with a client trace.
`config.request_id_header` changes the header name. See the
[Security guide](/docs/security.html) for the rest of the default middleware
stack.

## Development helper

The development-mode N+1 detector warns when identical SQL fires more than
`config.n_plus_one_threshold` times in one request. It never runs in
production. See [Record](/docs/record.html).
