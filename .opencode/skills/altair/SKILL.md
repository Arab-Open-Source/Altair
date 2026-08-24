---
name: altair
description: Altair codebase guide. Use whenever working in the Altair repository — implementing a phase, fixing a bug, writing specs, or answering questions about the project's plan, phases, architecture, coding conventions, or testing workflow. Loads the project's context (roadmap phases, exit criteria, code layout, non-negotiables, testing commands) so changes fit the framework instead of fighting it.
---

# Altair — batteries-included web framework for Crystal

Context loaded from `AGENTS.md` (the authoritative, detailed source). This
summary is the quick orientation; read `AGENTS.md` before deep work.

## Non-negotiables

- Never mention "Rails" in code, comments, docs, or commits.
- Specs from day one; every phase ends with its specs passing.
- Never skip a phase's exit criterion — vertical slices, not scaffolding.
- No emojis. No obvious comments; short doc comments on public APIs only.
- Formatter clean, Ameba silent, `crystal spec` green on every change.

## Where the project stands

Phases 0–5 done (Foundation, Router, Controllers, Views, Record/ORM,
CLI + Generators). Smart error pages (404 route suggestions, 405 `_method`
hints, 500 diagnostics) already shipped. The router kept growing after
Phase 1 in three spec-first waves: `resources` blocks
(`member`/`collection`/nested), constraints (`constraints: {id: /\d+/}`) +
implicit format suffix, and `redirect` / glob segments / singular
`resource`. `examples/blog` is the persistence demo. The CLI builds a
standalone `altair` binary; inside a generated project `bin/altair` runs
`server`, `routes`, `db:migrate` / `db:rollback`, and the standalone
`altair` auto-forwards those app-context commands to the nearest project
from any directory. `altair install` copies the binary onto `PATH`;
`altair update` checks GitHub for the latest release, verifies the
download against `SHA256SUMS` and atomically replaces the running
executable (`--check` / `--force` supported). Distributions: `release.yml`
(pushed on `v*` tags)
builds Linux/macOS/Windows (amd64+arm64) binaries with `SHA256SUMS`, and
`scripts/install.sh` / `install.ps1` / `install.cmd` give a verified
one-command install on each platform.
Phase 6 hardening shipped in waves: sessions + flash + CSRF + auth
(`require_login` / `authenticate!` + `Altair::Auth::JWT`), file-driven
configuration (`.env` / `database.yml`), multipart uploads
(`params.upload`, `Altair::HTTP::UploadedFile`), and a security
middleware set (`SecurityHeaders`, `RequestId`, opt-in `Cors`) in the
default stack. The development console was redesigned with an enriched
boot banner and aligned, colored request logs (method/status colors,
request counter, slow-request highlighting). Phase 7 shipped its first
four features: testing utilities (`Altair::Test.boot` with a `configure:`
hook, the cookie-jar `Altair::Test::Client`, `migrate!`/`transactional`),
full authentication (`altair g auth` + `password_auth` + PBKDF2 hashing),
the asset pipeline (`assets:precompile`, manifest-backed helpers, immutable
caching) and background jobs (typed `params` jobs, lazy `altair_jobs`
table, atomic claiming, backoff retries, `jobs:work` / `jobs:stats`).
989 specs passing
(6 pending: the PostgreSQL contract suite on `ALTAIR_TEST_PG_URL`).
The record layer shipped a post-Phase-4 performance wave: `find_each`
keeps scoped `where` filters + `includes` preloaders across batches,
`Relation#count`/`size` run `COUNT(*)` without materializing rows (and
respect `limit`/`offset`), the
server resizes the execution context to the available workers on boot
(`CRYSTAL_WORKERS` honored, `config.parallel_execution` opt-out), pool
defaults are warm (`initial 2 / idle 2 / max 10`), and a development-mode
N+1 detector warns on identical SQL past `config.n_plus_one_threshold`
(3) — see `docs/architecture/performance-audit.md`.
The query DSL covers negation and alternatives (`where_not`, `or_where`
folding into the previous clause) with `:like`/`:in`/`:null`/`:not_null`
operators; finders `first`/`last` (+ bang-less nil forms), `take`,
`ids`, `pick`, `exists?`/`any?`/`none?`; bulk writes `update_all` /
`delete_all` bypass callbacks, validations and timestamps.
Lifecycle hooks: enqueue jobs in `after_commit`, never `after_save`;
`touch` / `increment!` / `decrement!` are direct writes.
Associations: `belongs_to ..., counter_cache: true` maintains an
atomic `<assoc>_count`; `dependent: :destroy` collapses to one DELETE
when children declare no destroy callbacks. Validations take
`if:`/`unless:`/`allow_nil:` everywhere; uniqueness takes
`case_sensitive: false`.
`change_column_null` works on every adapter — SQLite rebuilds the table.
Database ergonomics: `altair new -d postgresql` wires the pg shard, URLs
and adapter require; `bin/altair db:create` / `db:drop` manage every env
in `config/database.yml`; `ENV["DATABASE_URL"]` overrides at boot and in
those commands.

| Phase | Focus | Status |
|---|---|---|
| 0–5 | Foundation / Router / Controllers / Views / ORM / CLI + Generators | Completed |
| 6 | Hardening (sessions, CSRF, config, security) | Completed |
| 7 | Post-release (jobs, auth, assets, rich queries) | Completed — jobs, auth, assets, testing utilities, `joins`, `has_many :through` and polymorphic shipped; console intentionally deferred |

Exit criteria per phase and golden rules are in `ROADMAP.md`.

## Phase 7 additions (where things live)

```
auth/         password_hasher.cr (PBKDF2-SHA256 digests), model_auth.cr
              (`password_auth` macro on Record::Model), jwt.cr
assets/       pipeline.cr — fingerprints assets/ into public/assets/ +
              manifest.json; helpers resolve through it (stylesheet_link_tag,
              javascript_asset_tag, asset_url); Static adds immutable caching
              to fingerprinted URLs only
jobs/         job.cr (`params` macro -> typed enqueue/enqueue_in/enqueue_at),
              queue.cr (lazy altair_jobs table, atomic claim, backoff retries,
              test mode), worker.cr (poll loop, graceful signals)
testing/      test.cr (boot with configure: hook, migrate!, transactional),
              client.cr (cookie-jar HTTP client with redirects)
cli/          `altair g auth`, project commands assets:precompile,
              jobs:work, jobs:stats
```

- Jobs persist without a migration: the queue creates `altair_jobs`
  lazily. Specs set `Altair::Jobs::Queue.test_mode = true`, enqueue, then
  drain synchronously via `Worker#execute`.
- Auth flows in specs use `Altair::Test::Client` so the session cookie
  carries between requests; register -> protected page -> logout reads as
  plain requests.
- Asset specs build a temp project root, run `Pipeline#precompile`, then
  boot an app with `app.root = tmp` and assert manifest resolution.

## Code layout

`src/altair.cr` requires every component **in dependency order** — new
files must be registered there or they silently never load.

```
core/        Application, request handling, error pages
http/        Request, Response, Params
routing/     Router, DSL, Route, RouteSet, Segment (segment-based, no regex)
controller/  Controller base
middleware/  Base, Logger, Static, SecurityHeaders, RequestId, Cors
config/      Config, Env, environments/
support/     ANSI (console colors), Inflector, utilities
exceptions/  Exception hierarchy
server/      HTTP server wiring
record/      Adapter, SQLite3, Connection, Schema, migrations, N+1 detector
view/        ECR templates, layouts, partials, helpers, htmx layer
rendering/   Renderers (html, json, text, fragment)
cli/         CLI dispatcher, per-project commands, generators (incl. install)
testing/    Test helpers (Altair::Test.boot)
```

`spec/` mirrors `src/altair/`; `examples/hello_world/` is the runnable demo,
`examples/blog/` the persistent ORM demo.

## Architecture principles

1. Compile-time safety first — route helpers like `post_path(5)` are
   generated, type-checked methods; a wrong dispatch is a compile error.
2. Segment-based routing, not regex.
3. Middleware uses factories (`Proc(Application, Middleware)`) — calling
   `.new` on the base class widens the pipeline type to every subclass.
4. One `Altair::Application` subclass per project (`SpecApp` in specs).
5. Error pages are debug-mode only; production gets a plain message.
6. Escape everything rendered by default; never echo sensitive headers.

## Testing

```bash
crystal spec                              # full suite (currently 752)
crystal tool format --check src spec examples
crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent
```

- `spec/spec_helper.cr` pins `Altair.env = Altair::Env::Test`, defines
  `SpecApp` and the compile-time `StubController` hierarchy (DSL specs only
  register routes; controller specs exercise real dispatch).
- Integration specs bind an ephemeral port and wait until ready; reset the
  shared app instance in an `ensure` block.
- Bug fixes: write the reproducing spec first, watch it fail, then fix.

## Gotchas that cost real time

- `NamedTuple#select` does not exist — go through `to_a.select(...)`.
- `Exception#cause=` is not public API — chain in the constructor.
- `Log::IOBackend` needs `require "log/io_backend"`; sync specs need
  `dispatcher: Log::DispatchMode::Sync` (async races assertions).
- Prefer `Time.instant` over `Time.monotonic`.
- `MIME.from_extension?` takes the leading dot (`.css`).
- `HEAD` matches `GET` routes; the body is dropped automatically.
- `_method` override lets HTML forms send PUT/PATCH/DELETE; error hints
  must respect it and report `HEAD` as `GET`.
- `yield` + `ensure` widens return types to `| Nil` — use `.as(...)`.
- Welcome page renders when there are no routes and the path is `/`.
- Glob segments (`*path`) must be the last segment; the format-stripped
  scan skips them so `/files/a.txt` stays one capture.
- `redirect` routes register under method `ANY` and never appear in a 405
  `Allow` header.
- Never auto-format after a build; the workflow treats formatting as a check.
- `pkill` is unreliable here — kill dev servers by PID.
- Register new files in `src/altair.cr` in dependency order.

## Delivering changes

Branches: `feat-<slug>`, `issue-<n>-<slug>`, `fix-<slug>`. Conventional
Commits (`feat:`/`fix:`/`refactor:`/`docs:`/`test:`/`chore:`), imperative,
under 72 chars. Update `CHANGELOG.md` `[Unreleased]` for user-facing work.
Full guidance in `CONTRIBUTING.md`.
