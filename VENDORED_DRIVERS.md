# Vendored PostgreSQL driver pins

Altair temporarily pins maintained forks of `crystal-pg` and `crystal-db`, plus a transitive `crystal-sqlite3` pin, so the PostgreSQL concurrency fixes reach generated applications and both adapters resolve the same patched `db` source.

## Current pins

| Dependency | Repository | Commit | Upstream pull request |
|------------|------------|--------|-----------------------|
| `pg` | `HMH-3080/crystal-pg` | `6854d35d8a29a411436d95dbc9b58c12958bb10d` | https://github.com/will/crystal-pg/pull/319 |
| `db` | `HMH-3080/crystal-db` | `6adf6ffaa948999a93bc95fdddf300b8426eaf0e` | https://github.com/crystal-lang/crystal-db/pull/235 |
| `sqlite3` | `HMH-3080/crystal-sqlite3` | `9e3c4c60630b01c94f6aacbdfeccb8d0f0685943` | Transitive pin only |

The `pg` and `sqlite3` distribution commits both pin the same `db` fork internally, so Shards resolves one unambiguous source for every adapter. Both upstream PRs are ready for review and awaiting a maintainer merge.

## Fixes included

### crystal-pg

- Reentrant per-fiber synchronization around the complete extended-query exchange.
- Synchronization around result-set movement and reads.
- `PQ::ProtocolError` for frame-state mismatches.
- Conversion of protocol and I/O failures into `DB::ConnectionLost`, so the pool discards dirty sockets.

Named prepared-statement caching is deliberately not included. It was evaluated and rejected because reused server-side plans became stale after DDL and broke the driver contract suite.

### crystal-db

- `PoolRetryAttemptsExceeded` preserves the last pool resource loss or refusal as its cause.

## Verification

With PostgreSQL running:

```bash
ALTAIR_TEST_PG_URL=postgres://postgres:postgres@localhost:5433/altair_test \
  crystal spec spec/record/postgresql_protocol_spec.cr

scripts/postgres_release_smoke.sh
```

The release-smoke script generates a fresh PostgreSQL project, installs its dependencies from the pinned commits, and runs a concurrent single-connection workload.

## Removal plan

When both upstream pull requests are merged and released:

1. Update the pins to the official fixed releases.
2. Re-run the PostgreSQL protocol contract and release smoke.
3. Remove this document and its release-packaging entry.
4. Close https://github.com/Arab-Open-Source/Altair/issues/21.
