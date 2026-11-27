# Read replicas

Set `config.db_replica_url` to route plain SELECT statements to a replica.
The feature is experimental: measure replication lag and force the primary
for correctness-sensitive reads.

## Routing rules

Clean SELECTs go to the replica. Writes and explicit transactions always go
to the primary. Checkout hooks, query instrumentation and the database
admission gate preserve the same routing.

## Sticky reads

After a write on a fiber, its reads stay on the primary so a handler never
sees a stale copy of its own write. That state is cleared when the HTTP
request completes, so a keep-alive fiber does not leak it into the next
request.

## On primary

```crystal
Post.all.on_primary.where(published: true)      # force the primary
Altair::Record.connection.with_primary { ... }  # nested block form
```

Use these when a read must observe the latest committed state.

## Failover and recovery

A failed replica is skipped for a bounded cooldown (5 seconds) and retried
afterwards. A recovery log line is emitted when the standby becomes usable
again. While the replica is unavailable, reads fall back to the primary.

## Metrics

`QueryEvent#target` is `:primary` or `:replica`. `/metrics` exposes
`altair_db_queries_total{target="primary"}`,
`altair_db_queries_total{target="replica"}` and
`altair_db_replica_failovers_total` in Prometheus text format.

## INSERT RETURNING

PostgreSQL `INSERT ... RETURNING` returns rows but is still a write:
`query_one` routes it to the primary and pins the fiber.

## Demo

`examples/read_replica_postgres` in the framework source runs a primary and
a physical streaming standby with `pg_basebackup`. Its `/items` endpoint
shows the selected target in a response header and supports
`?source=primary`; `/metrics` shows target counters. It also demonstrates
stopping the standby to observe failover and restarting it to observe
recovery.
