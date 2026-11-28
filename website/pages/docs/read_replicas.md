# Read replicas

Set `config.db_replica_url` to open a second connection pool and route clean
`SELECT` statements to a replica. **This feature is experimental**: measure
replication lag for your workload and force the primary for any read that
must observe the latest committed state.

```crystal
class Blog < Altair::Application
  config.db_url = ENV["DATABASE_URL"]? || "postgres://primary/blog"
  config.db_replica_url = ENV["REPLICA_URL"]? || "postgres://replica/blog"
end
```

## Routing rules

- Clean `SELECT` statements go to the replica.
- Writes and explicit transactions always go to the primary, including reads
  inside a transaction.
- Checkout hooks, query instrumentation and the database admission gate
  preserve the same routing.

## Sticky reads and request cleanup

After a fiber writes, its reads stay on the primary so a handler never sees a
stale copy of its own write. The framework clears that per-fiber stickiness
in the request handler's `ensure` block, so a keep-alive connection cannot
leak it into the next request.

## Forcing the primary

```crystal
Post.all.on_primary.where(published: true)      # forced primary read
Post.all.on_primary.includes(:comments)         # eager loaders stay on primary
Altair::Record.connection.with_primary do
  Post.find!(1)                                 # every read in the block
end
```

`with_primary` is reference-counted, so nested blocks behave correctly. Use
either form when a read must be current despite replication lag.

## Failover and recovery

A failed replica checkout or a lost connection marks the replica unavailable
for a bounded **5-second cooldown**; reads fall back to the primary during
that window. A warning log records the failure and an info log records
recovery when the standby becomes usable again. Every failure increments the
failover counter.

## Instrumentation and metrics

Each `Altair::Record::QueryEvent` carries `target`, either `:primary` or
`:replica`, in addition to its timing breakdown, so `on_query` subscribers
can see where a statement actually ran.

With `config.observability = true`, `/metrics` exposes these exact Prometheus
series:

```
# TYPE altair_db_queries_total counter
altair_db_queries_total{target="primary"} ...
altair_db_queries_total{target="replica"} ...
# TYPE altair_db_replica_failovers_total counter
altair_db_replica_failovers_total ...
```

See the [Observability guide](/docs/observability.html).

## PostgreSQL `INSERT ... RETURNING`

`INSERT ... RETURNING` returns rows, but it is still a write: it is pinned to
the primary and marks the fiber as having written, so subsequent reads in the
same request also stay on the primary.

## Streaming replica demo

`examples/read_replica_postgres` in the framework source runs one Altair app
against a PostgreSQL primary and a physical streaming standby. Its `/items`
endpoint reports the selected target in `X-DB-Target` and the failover count
in `X-DB-Failovers`, supports `?source=primary`, and lets you stop and restart
the standby to watch failover and recovery through real HTTP requests. The
migration runs on the primary and reaches the replica through streaming
replication.

For the ORM side of routing and a shorter tour, see the
[Record guide](/docs/record.html) or run `altair docs read_replicas` offline.
