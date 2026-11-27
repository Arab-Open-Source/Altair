# Configuration

`config/database.yml` holds one URL per environment; `ENV["DATABASE_URL"]`
overrides it at boot. `.env` values are merged first, real environment
variables win over `.env`, and `.env.<environment>` overrides `.env`.

Important deployment variables (never commit real values):

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | Primary database URL; overrides `config/database.yml` |
| `SECRET_KEY_BASE` | Cookie/JWT signing secret; required in production |
| `ALTAIR_ENV` | `development`, `test` or `production` |
| `PORT` | Listener port, default 3000 |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Compose database credentials |

Application settings live on `config`, for example `config.port`,
`config.observability`, `config.db_max_pool_size` and `config.cors.origins`.
Generated projects enable observability so `/health` and `/metrics` are
available in every environment.

## Read replicas

Set `replica_url` per environment in `config/database.yml` (or
`config.db_replica_url` in code) to route plain SELECTs to a replica. Writes
and transactions stay on the primary; use `Relation#on_primary` or
`Connection#with_primary` for reads that must observe the latest commit.
See `altair docs read_replicas` for sticky reads, failover, recovery and the
`altair_db_queries_total{target=...}` metrics.

## Logging and health

`config.observability` enables `/health` and `/metrics`;
`config.health_path` and `config.metrics_path` change the paths.
`config.structured_logs = true` emits one JSON object per request with the
method, path, status, duration and request id. Cookies, Authorization headers
and request bodies are never logged.
