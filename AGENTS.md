# AGENTS.md — Working with Altair

This file gives human and AI contributors the context they need to work on
Altair effectively: where the project stands, what to build next, how to
write code that fits, and how to verify it. Read it before touching the
codebase, and treat it as a contract for every change you make.

---

## What Altair is

Altair is a **batteries-included web framework for Crystal**. Batteries
included means it ships the full stack — routing, controllers, views,
configuration, an ORM, generators, CLI — with sane defaults, so that
building a web app with Crystal feels like the framework is working *for*
you, not against you.

The driving philosophy, from the roadmap:

> Every phase ends with something working and visible — vertical slices,
> not horizontal scaffolding. Each phase has a clear exit criterion.

Nothing ships unless someone can look at it, click it, and see it work.

## Non-negotiables

- **Do not mention "Rails"** — not in code, comments, docs, or commit
  messages. It is an old house rule; keep it that way. Performance and API
  comparisons to other frameworks are fine in conversation, just never
  "Rails" in the repo.
- **Specs from day one.** Every phase ends with its specs passing.
- **Never skip a phase's exit criterion.** Building the ORM before a
  working demo exists is wasted effort.
- **No emojis in code or docs.**
- **No code comments that state the obvious.** Use short doc comments above
  public classes and methods (Crystal doc style), matching the existing
  code.

## Current status

- **Phases 0–5 done** (Foundation, Router, Controllers, Views, Record/ORM,
  CLI + Generators). `examples/blog` is the always-running persistence demo
  — its posts and comments survive restarts.
- 817 specs passing (6 pending: the PostgreSQL concurrency contract
  tests, plus the fuller PostgreSQL contract suite gated on
  `ALTAIR_TEST_PG_URL`), formatter clean, Ameba silent on framework sources.
- Phase 7 shipped four features: **testing utilities** (`Altair::Test.boot`
  with a `configure:` hook, the cookie-jar `Altair::Test::Client` with
  browser-like redirects, `migrate!`, `transactional`),
  **full authentication** (`altair g auth` generating model + migration +
  sessions/registrations controllers + views + routes; the `password_auth`
  macro hashing through `Altair::Auth::PasswordHasher` — PBKDF2-SHA256,
  no new dependencies), the **asset pipeline** (`assets/` fingerprinted
  into `public/assets/` with a manifest by `altair assets:precompile`;
  `stylesheet_link_tag` / `javascript_asset_tag` / `asset_url`; immutable
  caching on fingerprints only), and **background jobs** (typed `params`
  with compile-checked `enqueue`/`enqueue_in`/`enqueue_at`, a lazily-created
  `altair_jobs` table, atomic claiming so concurrent workers never
  double-run, exponential-backoff retries inside a per-job budget,
  `altair jobs:work` / `jobs:stats` commands, and an in-memory test mode).
  `examples/blog` demonstrates all of it end to end. Remaining Phase 7:
  only the deferred console. `joins` (with table-qualified where,
  DISTINCT, COUNT(DISTINCT)), `has_many :through` (inferred source)
  and polymorphic (`belongs_to ... polymorphic:` / `has_many ..., as:`
  with batched-per-type eager loading) shipped in the closing wave.
- Phase 6 hardening shipped in waves: sessions + flash + CSRF + auth
  (`require_login` / `authenticate!` + `Altair::Auth::JWT`), then a
  configuration wave — `.env` (real env vars win; `.env.<environment>`
  overrides `.env`) and `config/database.yml` per-environment settings are
  merged into `config` at boot by `Altair::Config::DotEnv` /
  `Altair::Config::Database`, and `altair new` generates both files so a
  fresh project's configuration is file-driven, not code-driven — and a
  multipart wave: `multipart/form-data` bodies parse into the parameter
  bag (scalar fields as params, files as `Altair::HTTP::UploadedFile` via
  `params.upload("avatar")`, with `UploadedFile#save` + `#content`). The
  default middleware stack shipped a security wave:
  `SecurityHeaders` (default `nosniff` / `SAMEORIGIN` / referrer policy,
  driven by `config.security_headers`), `RequestId` (`request.request_id`,
  echo-back through `config.request_id_header`, appended to the request log
  line), and opt-in `Cors` (`config.cors.origins` enables it; preflight
  answered directly).
- The router shipped three post-Phase-1 waves: `resources` blocks
  (`member`/`collection`/nested, Phase 1 era), constraints + implicit
  format suffix, and `redirect` / glob segments / singular `resource`
  (Wave 3, current).
- The controller layer shipped a post-Phase-2 hardening wave: JSON-object
  rendering, `redirect_back`, `request.format`, JSON request bodies, clean
  `head`, `respond_to`, callbacks (`before_action` / `after_action` /
  `skip_*` with inheritance), controller-level `rescue_from`, chunked
  `stream`, and a segment-based route index.
- The record layer shipped a post-Phase-4 performance wave: `find_each`
  streams batches that keep scoped `where` filters and `includes`
  preloaders; `Relation#count`/`size` run `COUNT(*)` without materializing
  rows; the server resizes the execution context to the available workers
  on boot (`CRYSTAL_WORKERS` honored, `config.parallel_execution` opt-out);
  pool defaults are warm (`initial 2 / idle 2 / max 10`); and a
  development-mode N+1 detector counts identical SQL per request and warns
  past `config.n_plus_one_threshold` (3); and a database admission-control
  gate (`config.db_max_active_queries`, off by default) parks excess
  request fibers on a FIFO `Altair::Concurrency::Semaphore` outside the
  pool, bounding tail latency under saturation. The generic
  `Altair::Record.on_checkout` seam it subscribes to wraps each connection
  acquisition (one per transaction, never per statement inside one). The
  audit and attribution live in
  `docs/architecture/performance-audit.md`.
- Smart error pages (404 with route suggestions, 405 with `_method`
  explanation, detailed 500 diagnostics) shipped early as a pre-Phase-3
  gift — they live in the framework already.

| Phase | Focus | Status |
|---|---|---|
| 0 | Foundation | Completed |
| 1 | Router | Completed |
| 2 | Controllers | Completed |
| 3 | Views | Completed |
| 4 | Record (ORM) | Completed |
| 5 | CLI + Generators | Completed |
| 6 | Hardening | Completed |
| 7 | Post-release | Planned |

## The phases

Detailed phase-by-phase implementation plans live in
[`docs/architecture/`](docs/architecture) and the authoritative status
table in [`ROADMAP.md`](ROADMAP.md). The exit criteria — the contract for
"done" — are:

### Phase 3: Views (done)
- Auto-escaping by default: `<%= %>` escapes, `<%== %>` raw — XSS-safe out
  of the box.
- Layouts + `yield`: pages share a header and footer.
- Partials (`render "form"`): file reuse.
- Helpers: `link_to`, `content_tag`, basic form builder — a live HTML demo
  viewable in the browser (`examples/htmx`).

### Phase 4: ORM — `Altair::Record` (the big one, ~40% of total effort)
Three vertical waves, each ending green with something visible:
- Wave 1 (done, in the tree): adapter interface + SQLite3, connection +
  pool config + `on_query` instrumentation, migrations DSL + runner
  (timestamped files, `schema_migrations` table, auto-regenerated
  `db/schema.cr`), `examples/blog` persists across restarts.
- Wave 2 (done, in the tree): CRUD + finders (`find_by_*`), validations
  (`valid?` + errors), timestamps + callbacks.
- Wave 3 (done, in the tree): associations (`belongs_to` / `has_many` /
  `has_one`) with batched eager loading via `Relation#includes`;
  `dependent:` handling.
- Deferred to later phases: `has_many :through`, prepared-statement
  caching, `explain`, migration linter
  (Phase 8); console/seeds (Phase 7); enums/JSON columns/dirty tracking
  (Phase 6); `insert_all` (Phase 6). `find_each` is implemented in the
  tree (keeps scoped `where` filters and `includes` preloaders across
  batches).

### Phase 5: CLI + Generators
- `altair new blog` generates the standard layout (`src/`, `db/`,
  `public/`, `bin/altair.cr` + `bin/altair.cmd`).
- `altair g model/migration/controller` generates ready-to-edit files.
- `altair g scaffold Post title:string body:text` — the full magic: model +
  migration + controller + views + `resources` route + seeded
  `db/schema.cr`.
- Inside a project, `bin/altair` runs `server`, `routes`, `db:migrate` /
  `db:rollback` / `db:seed`; the framework builds a standalone `altair` binary via
  `shards build altair`. The standalone `altair` auto-forwards those
  app-context commands to the nearest project from any directory (walking
  up to the project root, preferring an executable `bin/altair`, falling
  back to `crystal run bin/altair.cr`).
- `altair install` copies the built binary onto your `PATH`
  (`~/.local/bin` on Unix, `%USERPROFILE%\.altair\bin` on Windows), prints
  its SHA-256 digest, is idempotent, refuses clobbering an unrelated file
  without `--force`, and honors `--dir` / `ALTAIR_BIN`.
- `altair update` checks GitHub for the latest release, verifies the
  downloaded binary against `SHA256SUMS` and atomically replaces the
  running executable; `--check` (exit 0 current / 1 newer) and `--force`
  are supported.
- Distributed install: `release.yml` builds the binary for Linux/macOS/
  Windows (amd64 + arm64) and publishes it with `SHA256SUMS`; the fail-safe
  `scripts/install.sh` (`curl ... | sh`), `install.ps1` (`iex (irm ...)`)
  and `install.cmd` (`curl ... | cmd`) download, verify and install.
  Pushing a `v*` tag triggers it.
- Full blog demo works out of the box: new project + scaffold + server.

### Phase 6: Hardening
- Sessions + flash + CSRF — a simple login works.
- `database.yml` / `.env` config — production-ready project.
- Multipart form parsing + security middleware set.
- Maintenance: Ameba + specs everywhere — real project quality.

### Phase 7: Post-release
- Shipped: background jobs, full authentication, asset pipeline, testing
  utilities (scopes + nested `includes` landed earlier in the query DSL).
- Shipped in the closing wave: `joins` (table-qualified where, DISTINCT),
  `has_many :through` (inferred source) and polymorphic associations.
  Multi-tenancy remains a Phase 12 candidate.

Golden rules from the roadmap: specs from day one, never skip an exit
criterion, every week something visible, and hold off the complex 20%
(polymorphic associations, STI) until after the first release.

---

## Codebase layout

The entry point is `src/altair.cr` — it requires every component **in
dependency order**. Any new file must be added there in the correct
position, or it will not be loaded.

```
src/altair/
  core/          Application, request handling, error pages
  http/          Request, Response, Params
  routing/       Router, DSL, Route, RouteSet, Segment
  controller/    Controller base
  middleware/    Base, Logger, Static
  config/        Config, Env, environments/
  support/       Inflector and other utilities
  exceptions/    The exception hierarchy
  server/        HTTP server wiring
  record/        Adapter, SQLite3, Connection, Schema, migrations, N+1 detector
  auth/          PasswordHasher (PBKDF2), password_auth model macro, JWT
  assets/        Pipeline: fingerprint assets/ -> public/assets/ + manifest
  jobs/          Job (params macro), Queue (lazy table, claim), Worker
  concurrency/   Semaphore (FIFO permit gate primitive)
  view/          ECR templates, layouts, partials, helpers, htmx layer
  rendering/     Renderers (html, json, text, fragment)
  cli/           CLI dispatcher, per-project commands, generators
  plugins/       (planned — empty placeholder)
  concerns/      (planned — empty placeholder)
  testing/       (planned — empty placeholder)
spec/            Mirrors src/altair, plus controller/routing integration specs
examples/        hello_world is the always-running demo app; examples/blog
                 is the persistence demo (Phase 4)
docs/architecture/  Phase-by-phase implementation plans
```

Modules nest under `Altair`: `Altair::Routing::Router`, `Altair::Controller`,
etc.

### Architecture principles to preserve

1. **Compile-time safety first.** The framework leans on Crystal's type
   system hard. Route helpers like `post_path(5)` are generated methods,
   type-checked like any other code. A wrong method on a dispatch is a
   compile error, not a runtime 500. Prefer constructs that fail at compile
   time over runtime checks.
2. **Segment-based routing, not regex.** The router parses URL segments
   directly. Any new routing behavior should stay on that path.
3. **Middleware factories, not class instantiation.** `Middleware.new(app)`
   on a base class widens to every subclass — the pipeline uses factory
   procs (`Proc(Application, Middleware)`) to keep each middleware concrete.
4. **One application subclass.** `Altair::Application` is subclassed once
   per project (the specs use `SpecApp`). The framework is built around
   that single-instance reality.
5. **Debug pages are for development.** Error pages with route suggestions,
   request context and source previews render in debug mode only.
   Production serves a plain, minimal message. Never leak request bodies or
   headers.
6. **Escape everything rendered by default.** HTML values shown to the user
   are escaped unless explicitly marked raw. Sensitive headers
   (Authorization, Cookie, ...) are never echoed into diagnostics.

---

## How to write code here

Follow the official Crystal style — the formatter is the authority:

```bash
crystal tool format --check src spec examples
```

- Match the surrounding style of the file you are editing.
- Short doc comment above each public class and method, as the existing
  code does.
- Keep the linter silent:

```bash
crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent
```

### Workflow
- Branches are named after the change or issue: `feat-named-routes`,
  `issue-42-fix-405-header`, `fix-route-param-decoding`.
- Commits follow Conventional Commits: `feat:`, `fix:`, `refactor:`,
  `docs:`, `test:`, `chore:` — imperative mood, lowercase, under 72 chars.
  Use the body for the "why".
- Update `CHANGELOG.md` `[Unreleased]` for user-facing changes.
- Real contributor guidance lives in [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## Testing

The suite is `crystal spec` (currently 817 examples, 6 of them pending: the PostgreSQL concurrency contract tests, with the
fuller PostgreSQL contract suite gated on `ALTAIR_TEST_PG_URL`). Run it before and
after every change:

```bash
crystal spec
```

Rules:

- Every behavior you add gets a spec. When fixing a bug, add the
  reproducing spec **first**, watch it fail, then fix.
- Specs live in `spec/` mirroring `src/altair/`. Look at `spec/routing/`
  for the routing-layer patterns and `spec/controller/integration_spec.cr`
  for real HTTP request/response coverage.
- The suite pins `Altair.env = Altair::Env::Test` in
  `spec/spec_helper.cr` and defines `SpecApp`, the single shared
  application.
- Routing-DSL specs use the compile-time `StubController` hierarchy from
  `spec_helper.cr` — actions are registered but never invoked there; real
  dispatch is covered by the controller specs.
- Integration specs bind the server on an ephemeral port and wait until it
  is ready before issuing `HTTP::Client` requests. Reset the shared
  application instance in an `ensure` block so specs do not leak state.
- **Acceptance bar for any PR:** formatter clean, Ameba silent,
  `crystal spec` green, CHANGELOG updated.

---

## Hard-won gotchas (Crystal / this codebase)

These cost real debugging time once — internalize them:

- **Every value travels as a bind parameter.** Never interpolate values
  into SQL strings — the connection's `exec`/`query` take `*args` and bind
  them. SQL strings stay constant; identifiers go through
  `Adapter#quote_identifier`.
- **`NamedTuple#select` does not exist.** To filter a `NamedTuple`, go
  through `to_a.select(...)` or restructure.
- **`Exception#cause=` is not public API.** Build the chain in the
  constructor: `Exception.new(message, cause)`, not by assigning after the
  fact.
- **`Log::IOBackend` needs `require "log/io_backend"`.** In synchronous
  specs, pass `dispatcher: Log::DispatchMode::Sync` — the default async
  dispatcher races with assertions.
- **Prefer `Time.instant` over `Time.monotonic`** (deprecated in newer
  Crystal).
- **`MIME.from_extension?` takes the leading dot** — `".css"`, not `"css"`.
- **`HEAD` requests match `GET` routes** and the response body is dropped
  automatically.
- **`_method` override.** HTML forms can override the verb via a `_method`
  field (PUT/PATCH/DELETE). 405 error hints must respect it, and a `HEAD`
  request is reported as `GET`.
- **`yield` + `ensure` interplay:** inside a method with `yield`, Crystal
  widens return types to `| Nil` when you guard with `ensure`. Use
  `.as(Path)` or restructure rather than fighting the compiler.
- **The welcome page renders when there are no routes and the path is `/`.**
- **`crystal tool format` is a check** in this workflow — never auto-format
  *after* a build; it will fail CI. Format first, or use `--check`.
- **Middleware type widening:** `klass.new(app)` where `klass` is the base
  `Middleware` class widens the pipeline type to every subclass — this is
  why factories exist. Keep the factory pattern.
- **`pkill` does not work reliably from this environment's terminal.**
  Kill dev servers by PID (`kill <pid>`).
- **New files must be registered in `src/altair.cr`** in dependency order
  or they silently never load.

---

## Running things

```bash
shards install          # fetch dev dependencies (ameba)
crystal spec            # full test suite
crystal run src/altair.cr  # boot the framework (see examples/)
crystal tool format --check src spec examples
crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent
```

`examples/hello_world/` is a self-contained runnable app — the reference
for what a real Altair project looks like (its README explains how to run
it). Keep it running and demonstrable; it is the "every week, something
visible" vehicle.
