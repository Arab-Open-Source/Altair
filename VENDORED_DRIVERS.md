# Vendored PostgreSQL driver pins

Altair temporarily pins maintained forks of `crystal-pg` and `crystal-db`, plus a transitive `crystal-sqlite3` pin, so the PostgreSQL concurrency fixes reach generated applications and both adapters resolve the same patched `db` source.

## Current pins

| Dependency | Repository | Commit | Tag | Upstream pull request |
|------------|------------|--------|-----|-----------------------|
| `pg` | `Arab-Open-Source/crystal-pg` | `09165422b8fcac84d4359340bd4c35f5ff541e31` | `v0.32.0-altair.3` | https://github.com/will/crystal-pg/pull/319 |
| `db` | `Arab-Open-Source/crystal-db` | `161794a6c9c3ead9b7799b0cdd5d385fae3bb9c4` | `v0.15.0-altair.3` | https://github.com/crystal-lang/crystal-db/pull/235 |
| `sqlite3` | `Arab-Open-Source/crystal-sqlite3` | `219bc6f9d6552c79d018c7ba2eb086f603466104` | `v0.24.0-altair.3` | Transitive pin only |

The `pg` and `sqlite3` distribution commits both pin the same `db` fork internally, so Shards resolves one unambiguous source for every adapter. Both upstream PRs are ready for review and awaiting a maintainer merge.

## Ownership and maintenance policy

- All distribution forks are owned by the `Arab-Open-Source` organization.
- Production manifests pin exact commits; branches are never used as release inputs.
- Annotated `*-altair.3` tags mark the current audited pins.
- Each fork runs an `Altair compatibility` workflow on pushes, pull requests, manual dispatch, and a weekly schedule.
- Fork branches should be rebased onto the corresponding upstream release only when the full driver suite and Altair release smoke pass.
- Personal forks are temporary and are not referenced by Altair.

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
