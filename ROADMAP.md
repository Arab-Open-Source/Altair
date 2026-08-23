# Altair Roadmap

> **Philosophy:** every phase ends with something working and visible —
> vertical slices, not horizontal scaffolding. Each phase has a clear exit
> criterion.

This roadmap tracks the build in phases. **Phases 0–5 are complete and ship
with passing specs**; the remaining phases are planned. The ORM (`Altair::Record`)
— originally a single large "Phase 5" — landed across three waves inside the
Phase 4 milestone, so the router/controller/view/ORM stack is now usable end to
end against both SQLite and PostgreSQL. Phase 5 delivered the CLI and the
generators on top of that stack.

## Current status

| Phase | Focus | Status |
|-------|-------|--------|
| 0 | Foundation (app core, HTTP, config) | Completed |
| 1 | Router | Completed |
| 2 | Controllers + middleware + smart errors | Completed |
| 3 | Views (templates, layouts, partials, htmx) | Completed |
| 4 | ORM (`Altair::Record`, 3 waves) | Completed |
| 5 | CLI + Generators & scaffolding | Completed |
| 6 | Hardening (sessions, flash, CSRF, config, security) | Completed |
| 7 | Post-release features | Mostly completed — jobs, auth, assets, testing utilities shipped; `joins` and `has_many :through`/polymorphic remain |
| 8 | Database ergonomics | Planned — `altair new -d postgresql` and `bin/altair db:create` |
| 9 | CLI ergonomics | Planned — destroy, job generator, db:status, server flags, assets/jobs helpers |

> **Note on the CLI:** the original Phase 4 plan listed `altair new` /
> `altair server` / `altair routes`. That CLI landed in Phase 5, together
> with the generators and scaffolding. Applications boot via the framework's
> standalone `altair` binary or, inside a generated project, through a
> `bin/altair.cr` launcher (`crystal run bin/altair server`). The standalone
> `altair` auto-forwards those app-context commands to the nearest project
> from any directory, so `altair server`, `altair routes` and the database
> commands work without a `bin/` prefix.

---

## Phase 0: Foundation (completed)

| Task | Exit criterion |
|------|----------------|
| Application core (`Altair::Application`) | App boots and answers a request |
| Request / Response abstractions + `Params` | Query, route and body params are readable and typed |
| Configuration system | Per-environment settings load correctly (`config/env`, `environments/base`) |

## Phase 1: Router (completed)

| Task | Exit criterion |
|------|----------------|
| Routing DSL: `get`/`post`/`put`/`patch`/`delete` + `namespace` | Routes written naturally, compile-time |
| Path params (`:id`) | `/users/5` yields `params["id"] == "5"` |
| Named routes (`user_path`) | Paths callable by name, type-checked |
| `resources` macro | One line generates seven REST routes + helpers |
| 404 / 405 handling | Wrong path → 404, wrong method → 405 with `Allow` |

## Phase 2: Controllers (completed)

| Task | Exit criterion |
|------|----------------|
| Controller base: `render` / `redirect_to` / `head` / typed `params` | A full controller works end to end |
| Middleware pipeline | `Logger` + `Static` (path-traversal protected) |
| Smart error pages | Dev 404/405/500 pages with route suggestions + diagnostics |

### Controller additions since Phase 2 (hardening wave, shipped)

| Wave | Delivered |
|------|-----------|
| W1 — hardening | `permit` drops absent keys, `button_to`/`form_for` escape actions, quoted `send_file` filenames, lazy route params, per-application-class error handler isolation, HEAD-body and `_method` integration specs |
| W2 — request/response DX | `render json:` serializes any JSON-able object, `redirect_back(fallback:)` with same-host protection, `request.format` (suffix > `Accept` > `:html`), JSON request bodies merged into `params`, bodyless `head` + `no_content` |
| W3 — action machinery | `before_action`/`after_action` + `skip_*` with `only:`/`except:` and inheritance, controller-level `rescue_from` (compiled matching, subclass-aware), `respond_to` with 406 fallback, chunked `stream`, and a segment-based route index for candidate-only matching |

## Phase 3: Views (completed)

| Task | Exit criterion |
|------|----------------|
| Auto-escaping by default (`<%= %>` escapes, `<%== %>` raw) | XSS-safe out of the box |
| Layouts + `yield`, partials, helpers, form builder | Live HTML demo viewable in the browser |
| Compile-time `templates` macro with typed locals | Wrong local or missing file is a compile error |
| htmx layer (`HX-Request`, fragment rendering, `hx_*`, response headers) | No-reload flows work; everything also works without JS |

## Phase 4: ORM — `Altair::Record` (completed, 3 waves)

| Wave | Delivered |
|------|-----------|
| Wave 1 — foundation | Adapter interface + SQLite3/PostgreSQL adapters, pooled `Connection`, transactions & savepoints, `on_query` instrumentation, multi-db via `ALTAIR_DB_URL` |
| Wave 2 — models | `Model` base, `table` macro + typed attributes, CRUD + finders (`find`/`find_by_*`/`create`/`update`/`save`/`delete`), `pluck`, validations (`presence`/`length`/`numericality`/`uniqueness`/custom), timestamps, callbacks (`before_*`/`after_*`) |
| Wave 3 — associations | `belongs_to` / `has_many` / `has_one` with lazy+cached accessors, **batched eager loading** via `Relation#includes`, `dependent:` (`:destroy` / `:delete_all` / `:nullify`) |
| Cross-cutting | Migrations DSL + runner (`db:migrate` / `db:rollback`), `db/schema.cr` generation, contract test suite running against **both** SQLite and PostgreSQL |

ORM exit criteria met: connect to a database; create/drop tables via
migrations; a wrong column is a compile error (via generated `schema.cr`);
natural row handling (`find_by_*`); `valid?` + errors; associations work;
automatic timestamps + safe transactions.

### Router additions since Phase 1 (3 waves, shipped)

The router kept growing after its Phase 1 milestone, in three spec-first
waves:

| Wave | Delivered |
|------|-----------|
| 1 — `resources` blocks | `member` / `collection` custom routes, nested `resources` with parent params and helpers, bare-symbol `only:`, smarter pluralization |
| 2 — constraints & formats | Per-route `constraints: {id: /\d+/}` (anchored whole-value match, propagated to nested routes) and the implicit `.{ext}` format suffix (`/posts/5.json` → `params["format"] = "json"`) |
| 3 — redirect, glob, singular | `redirect "/old", to: "/new"` (301 for every method, never in `Allow`), glob segments (`/files/*path` → `path` = `"a/b"`, format-safe), and singular `resource` (six id-less routes on `/profile`, plural controller, no-arg helpers, id-less member/collection, nesting in both directions) |

## Phase 5: Generators & the CLI (completed)

| Task | Exit criterion | Delivered |
|------|----------------|-----------|
| `altair new <name>` | Generates the standard layout: `app/`, `config/`, `db/`, `public/` | Layout with `src/`, `db/`, `public/`, `bin/altair.cr` + `bin/altair.cmd` launchers, runnable immediately |
| `altair server` | Single command to run the app | `bin/altair server` inside a generated project |
| `altair routes` | Prints the route table | `bin/altair routes` renders the compiled route table |
| `altair g model/migration/controller` | Ready-to-edit files generated | Typed column DSL, model/migration/controller + views and helper registrations |
| `altair install` | Binary available directly on PATH | `~/.local/bin` (Unix) / `%USERPROFILE%\.altair\bin` (Windows), SHA-256 verified, idempotent, refuses clobbering without `--force`, `--dir` / `ALTAIR_BIN` override |
| `altair update` | Update the installed binary from GitHub | Checks the latest release, verifies the download against `SHA256SUMS`, atomically replaces the running executable; `--check` (exit 0 current / 1 newer) and `--force` supported |
| App-context command delegation | `server` / `routes` / `db:migrate` / `db:rollback` / `db:seed` work from anywhere | The standalone `altair` auto-forwards to the nearest project (walking up the tree, preferring an executable `bin/altair`, falling back to `crystal run bin/altair.cr`), so no `bin/` prefix is ever needed inside a project |
| Distributed install | Prebuilt binary + one-command install for new users | `release.yml` (triggered by a `v*` tag) builds Linux/macOS/Windows (amd64+arm64) into a GitHub Release with `SHA256SUMS`; verified one-command installs on every platform — `scripts/install.sh` (`curl ... | sh`), `install.ps1` (`iex (irm ...)`) and `install.cmd` (`curl ... | cmd`) — each downloads, checksums, installs and refuses clobbering without `--force` |
| `altair g scaffold Post title:string body:text` | Model + migration + controller + views | Full RESTful scaffold incl. `resources` route and seeded `db/schema.cr` |
| Full blog demo via scaffold | New project + scaffold + server works out of the box | E2E-verified: `new` → `g scaffold` → `db:migrate` → `server` → POST/GET over real HTTP |

The CLI is built as a standalone binary (`shards build altair`). Generated
projects reference the published shard by default; this checkout can be used
in place via `--framework-path` (or `ALTAIR_PATH`) at scaffold time. Windows
and Linux are first-class end to end: the framework builds `.exe` binaries,
the project launchers are `bin/altair.cr` + `bin/altair.cmd` (no
POSIX-only scripts), and each platform has a native verified installer
(`install.sh`, `install.ps1`, `install.cmd`). Distribution goes live by
pushing a `v*` tag, which triggers `release.yml`.

## Phase 6: Hardening

| Task | Exit criterion | Status |
|------|----------------|--------|
| Sessions + flash + CSRF | Simple login works; state-changing forms protected | Completed |
| `database.yml` / `.env` config | Production-ready configuration, no code edits | Completed |
| Multipart form parsing | File uploads work through `params` | Completed |
| Security headers + CORS + request ID | Safe-by-default headers, opt-in cross-origin, traceable requests | Completed |
| Maintenance: Ameba (linter) + specs everywhere | Real-project quality gate | Completed |

> Note: "beautiful error pages in development" and the compile-time view
> safety already shipped early as pre-Phase-3 gifts and are live in the
> framework. Performance hardening also shipped early as a pre-Phase-6
> wave: parallel execution and warm pool defaults, `find_each` with
> scoped filters + preloaders, `Relation#count`, and the development N+1
> detector — see `docs/architecture/performance-audit.md`.

## Phase 7: Post-release

| Task | Exit criterion | Status |
|------|----------------|--------|
| Testing utilities | First-class spec helpers | Completed — `Altair::Test.boot` (with `configure:` hook) + stateless HTTP helpers + `Altair::Test::Client` cookie-jar client with redirect following, `Altair::Test.migrate!` and `Altair::Test.transactional` |
| Full authentication | Registration, login, logout | Completed — `altair g auth` writes model + migration (unique email), sessions/registrations controllers and views; `password_auth` hashes through PBKDF2-SHA256 (`Altair::Auth::PasswordHasher`); built on sessions/CSRF/JWT from Phase 6 |
| Asset pipeline | CSS/JS bundling and serving | Completed — `assets/` fingerprinted into `public/assets/` with manifest via `altair assets:precompile`; `stylesheet_link_tag` / `javascript_asset_tag` / `asset_url`; immutable caching on fingerprints |
| Background jobs | Scheduled work runs | Completed — typed `params` jobs with compile-checked `enqueue`/`enqueue_in`/`enqueue_at`, lazy `altair_jobs` table, atomic claiming, exponential-backoff retries, `altair jobs:work` / `jobs:stats`, in-memory test mode |
| Rich query DSL (joins, preload, scopes, nested `includes`) | Complex data access is natural | Partially completed — scopes, `merge`, nested `includes` shipped; `joins` deferred to its own wave |
| `has_many :through` + polymorphic associations | Advanced model relationships | Planned |

## Phase 8: Database ergonomics (planned — deferred)

Mirrors the `new -d` / `db:create` ergonomics of the reference framework,
without mentioning it in code — flag is `-d` / `--database`.

| Task | Exit criterion | Notes |
|------|---------------|-------|
| `altair new <name> -d postgresql` | Project generated with `pg` in `shard.yml`, `database.yml` on `postgres://`, and `require "altair/record/adapters/postgresql"` wired — `shards install && bin/altair db:migrate` works with no hand-edit | Defaults to `sqlite`; `-d sqlite` explicit is allowed; `ALTAIR_DATABASE` env fallback as with `--framework-path` |
| `bin/altair db:create` | Reads `config/database.yml` and creates the `development`/`test`/`production` databases (idempotent `CREATE DATABASE IF NOT EXISTS` semantics) | Complements `db:migrate`/`db:rollback`; uses `Connection.for` per env with `CREATE DATABASE` outside a transaction |
| `bin/altair db:drop` (optional) | Drops the same databases | Guarded by confirmation in `production` |

Deferred by request — no code changes in this commit. Implementation will
follow `docs/architecture/phase-7-status.md` → Phase 8 plan when scheduled.

## Phase 9: CLI ergonomics (planned — deferred)

Batteries-included polish for the command line — no new subsystems, just
less friction for daily use.

| Priority | Task | Exit criterion |
|----------|------|----------------|
| High | `altair g job <Name> field:type ...` | Generates a typed `params` job class with `perform` stub; `shards build` passes |
| High | `altair destroy <type> <Name>` / `g --destroy` | Inverse of every generator — removes model/migration/controller/scaffold/auth files, route line and `db/schema.cr` seed; `did_you_mean` suggests it on unknown type |
| Medium | `bin/altair db:status` / `db:version` | Lists `applied_versions` vs `migration_files` with pending marker; `version` prints last applied |
| Medium | `bin/altair server -p PORT -b HOST -e ENV` | Flags override `config.port`/`host`/`env` at launch; ephemeral port still works for `Test.boot` |
| Medium | `bin/altair assets:clean` / `assets:clobber` | `clean` prunes orphaned fingerprints; `clobber` removes `public/assets` entirely |
| Medium | `bin/altair jobs:clear` / `jobs:retry` | Admin helpers over `altair_jobs` status (`pending/failed`); `retry` re-queues by id |
| Medium | `altair help` for project commands | `help_for` covers `server/routes/db:*/assets:*/jobs:*` instead of falling back to generic `help` |
| Low | `altair about` / `doctor` | Prints Crystal version, adapter, env, root, middleware/route counts without booting the server |

Deferred by request — no code changes in this commit. Waves: A (job + destroy), B (db:status + server flags), C (assets/jobs helpers + help).

> Multi-tenancy is a later Phase 10 candidate: see
> `docs/architecture/orm-audit-and-tenancy-plan.md` for the audited gaps and
> the wave plan.

---

## Realistic estimate

Reaching **v0.1** (blog demo + scaffold + core ORM + CLI + generators +
distributed installs) was the bulk of the effort; the ORM consumed the
largest share, as expected — it is the heart of the framework. The
remaining phases (hardening, auth, asset pipeline) are incremental on top
of a working, spec-covered, installable stack.

## Golden rules

1. **Specs from day one** — each phase ends with its specs passing.
2. **Never skip a phase's exit criterion** — building a later phase before a
   working slice exists is wasted effort.
3. **Every week, something visible** — eyes on the demo, not just internals.
4. **Hold off the complex 20%** — polymorphic associations, STI and
   `has_many :through` come after the first release, not before.
