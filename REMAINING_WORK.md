# Remaining Work Report

A logical map of everything left to build, verified against the tree on
2026-08-22 at v0.2.1. Companion to [`ROADMAP.md`](ROADMAP.md): that file
tracks what each phase promised; this one tracks what is actually left,
in dependency order, with exit criteria.

## Health snapshot at time of writing

| Check | Result |
|-------|--------|
| Specs | 706 examples, 0 failures, 6 pending (PG concurrency contract tests, gated on `ALTAIR_TEST_PG_URL`) |
| Formatter | clean |
| Ameba | silent (pinned to master commit `f53fcd3` until a stable release supports current Crystal) |
| Binary | `shards build altair` OK, reports 0.2.1 |
| Examples | hello_world, htmx, sqlite_crud, postgresql_crud, showcase all build |
| CI on main | green |
| Latest release | v0.2.1 published with binaries + SHA256SUMS |

## Shipped beyond the original roadmap (context)

These landed as waves between phases and are done: router waves 1-3
(constraints/formats, redirect/glob/singular resource), controller waves
W1-W3 (callbacks, `rescue_from`, `respond_to`, streaming), the pre-phase-6
performance wave (`find_each`, `Relation#count`, warm pools, N+1 detector,
admission control), the website redesign, and `examples/showcase`.

---

## Tier 1 — ORM completion gaps

Small, self-contained items deferred from earlier phases. They round out
the Record layer before anything builds on top of it.

| Item | State in tree | Exit criterion |
|------|---------------|----------------|
| `insert_all` bulk inserts | absent | `Model.insert_all(rows)` issues one multi-row statement, returns count; specs both adapters |
| Public dirty tracking | internal `@dirty` set drives partial UPDATEs; no public API | `changed?`, `changed_attributes`, `restore_attributes` public with specs |
| Enum columns | absent | `column status: {enum: [:draft, :live]}` type-checks values, stores the string |
| JSON columns | absent | typed read/write of a JSON column round-trips through both adapters |

## Tier 2 — Phase 7 developer experience

| Item | State in tree | Exit criterion |
|------|---------------|----------------|
| Rich query DSL (`joins`, `preload`, named scopes, nested `includes`) | `Relation` has only `where/order/limit/offset/count/includes/find_each` | join-based queries run without N+1; scopes chain like `where`; nested `includes` preloads two levels batched |
| Console + seeds | no CLI commands | `altair console` opens a REPL with models loaded; `db:seed` runs `db/seeds.cr` idempotently |
| Testing utilities | `src/altair/testing/` is an empty placeholder | shipped helpers to boot a test app, reset state between specs, and exercise controllers over real HTTP without hand-rolled servers |

## Tier 3 — New subsystems (Phase 7)

Independent of each other; order within the tier is preference, not
dependency. Full authentication builds directly on the shipped sessions +
auth helpers.

| Item | Depends on | Exit criterion |
|------|------------|----------------|
| Full authentication | sessions/CSRF/JWT (shipped) | `altair g auth` generates registration/login/logout end to end with hashed passwords |
| Background jobs | none | jobs enqueue, survive restart via a table adapter, execute with retry; demo shows a delayed job |
| Asset pipeline | none | CSS/JS fingerprinted, served from `public/`, manifest generated in dev and release modes |
| `has_many :through` + polymorphic associations | eager loading (shipped) | both association kinds work lazily, eagerly and with `dependent:` handling |

## Phase 8 backlog (performance tooling)

Prepared-statement caching, `explain`, migration linter. Deliberately
last: they optimize and guard an already-correct layer.

---

## Suggested sequencing

1. **Wave A (quick wins):** Tier 1 entirely — four small vertical slices,
   each shippable in isolation.
2. **Wave B:** rich query DSL, then console/seeds, then testing utilities
   (utilities make every later wave cheaper to verify).
3. **Wave C:** pick one Tier 3 subsystem at a time; authentication first is
   the natural demo vehicle.
4. **Wave D:** Phase 8 backlog.

Golden rules apply unchanged: specs from day one, never skip an exit
criterion, every week something visible, complex 20% last.

## Known debt / notes

- The 6 pending specs are the PostgreSQL concurrency contract tests; the
  fuller PG suite runs when `ALTAIR_TEST_PG_URL` is set. Worth wiring into
  CI as an optional job eventually.
- `docs/architecture/` plans are intentionally untracked (gitignored);
  user-facing documentation lives in `website/`.
- `fix_plan.md` at the repo root is the historical performance remediation
  plan; its work has shipped (see CHANGELOG 0.2.x entries).
- Revisit the ameba pin when a stable release compatible with current
  Crystal lands, and return to floating releases.
