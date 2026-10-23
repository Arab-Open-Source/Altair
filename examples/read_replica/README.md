# read_replica — two SQLite databases, one Altair application.

Demonstrates `config.db_replica_url`: plain SELECT statements run against
a second pool (the replica) while writes and transactions stay on the
primary. A request fiber that has written keeps reading the primary for
its whole lifetime, so a handler never reads a stale copy of its own
writes.

## Run

```bash
shards install
crystal run scripts/db.cr -- migrate   # builds both databases
crystal run src/app.cr                 # serves on http://localhost:4000
```

Then:

```bash
curl localhost:4000/routing
# plain SELECTs route to: replica

curl -X POST localhost:4000/notes -d "body=first note"
# wrote note 1
# same-fiber read served by: primary -> first note
```

The write pinned its request fiber's reads to the primary, so the
handler's own read sees the row. A fresh request (`curl
localhost:4000/notes`) reads the replica again — which stays empty here,
because two local SQLite files do not replicate. That is the point of the
demo: it makes *which pool serves which statement* visible without
infrastructure. In production `replica_url` points at a
streaming-replication standby, where the same statement lands on a copy
that tracks the primary.
