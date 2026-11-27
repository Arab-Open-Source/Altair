# read_replica_postgres — primary plus a streaming standby

This example runs the same Altair application against two PostgreSQL
servers: a primary on `55440` and a physical streaming replica on `55441`.
Plain SELECTs use the replica, writes and transactions stay on the primary,
and each response includes `X-DB-Target` plus `X-DB-Failovers` so routing is
visible over real HTTP.

## Run

```bash
docker compose up -d --wait
shards install
crystal run scripts/db.cr -- migrate
crystal run src/read_replica_postgres.cr
```

The migration runs on the primary; the table reaches the replica through
streaming replication.

## Walkthrough

```bash
# Replica read
curl -i localhost:4000/items

# Write, then read in the same request through the sticky primary window
curl -i -X POST localhost:4000/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"first item","price":12.5}'

# Explicit primary read
curl -i 'localhost:4000/items?source=primary'

# Database target counters
curl localhost:4000/metrics | grep altair_db
```

The normal list header is `X-DB-Target: replica`. The POST response reports
`"read_target":"primary"` because the same request fiber has written. The
explicit list and the post-write read report `primary` as well.

## Replica failure

```bash
docker compose stop postgres-replica
curl -i localhost:4000/items
docker compose start postgres-replica
docker compose exec -T postgres-replica pg_isready -U altair -d altair_demo
sleep 10
curl -i localhost:4000/items
```

While the replica is stopped, reads fall back to the primary and
`X-DB-Failovers` becomes `1`. After the cooldown (5 seconds) and recovery,
the list returns to the replica. The application logs one warning for the
outage and one recovery line.

## What this proves

- `QueryEvent#target` and the per-target metrics track the actual pool.
- `Relation#on_primary` bypasses the replica.
- Replica checkout failures fall back to the primary during a bounded
  cooldown.
- Replica recovery is automatic after the cooldown.
- Write stickiness keeps the same request on the primary without pinning
  later requests.
