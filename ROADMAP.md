# Altair Roadmap

> **Philosophy:** every phase ends with something working and visible —
> vertical slices, not horizontal scaffolding. Each phase has a clear exit
> criterion.

This roadmap tracks the build in phases. **Phases 0–4 are complete and ship
with passing specs**; the remaining phases are planned. The ORM (`Altair::Record`)
— originally a single large "Phase 5" — landed across three waves inside the
Phase 4 milestone, so the router/controller/view/ORM stack is now usable end to
end against both SQLite and PostgreSQL.

## Current status

| Phase | Focus | Status |
|-------|-------|--------|
| 0 | Foundation (app core, HTTP, config) | Completed |
| 1 | Router | Completed |
| 2 | Controllers + middleware + smart errors | Completed |
| 3 | Views (templates, layouts, partials, htmx) | Completed |
| 4 | ORM (`Altair::Record`, 3 waves) | Completed |
| 5 | CLI + Generators & scaffolding | Planned |
| 6 | Hardening (sessions, flash, CSRF, config) | Planned |
| 7 | Post-release features | Planned |

> **Note on the CLI:** the original Phase 4 plan listed `altair new` /
> `altair server` / `altair routes`. That CLI has **not been built** — the
> ORM was the part of Phase 4 that actually landed. Applications currently
> boot by `crystal run` of the project's entry file (no `bin/altair` exists).
> The CLI is now tracked as the first item of Phase 5.

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

## Phase 5: Generators & the CLI (next)

| Task | Exit criterion |
|------|----------------|
| `altair new <name>` | Generates the standard layout: `app/`, `config/`, `db/`, `public/` |
| `altair server` | Single command to run the app (replaces `crystal run …`) |
| `altair routes` | Prints the route table |
| `altair g model/migration/controller` | Ready-to-edit files generated |
| `altair g scaffold Post title:string body:text` | Model + migration + controller + views |
| Full blog demo via scaffold | New project + scaffold + server works out of the box |

## Phase 6: Hardening

| Task | Exit criterion |
|------|----------------|
| Sessions + flash + CSRF | Simple login works; state-changing forms protected |
| `database.yml` / `.env` config | Production-ready configuration, no code edits |
| Multipart form parsing | File uploads work through `params` |
| Maintenance: Ameba (linter) + specs everywhere | Real-project quality gate |

> Note: "beautiful error pages in development" and the compile-time view
> safety already shipped early as pre-Phase-3 gifts and are live in the
> framework.

## Phase 7: Post-release

| Task | Exit criterion |
|------|----------------|
| Background jobs | Scheduled work runs |
| Full authentication | Registration, login, logout |
| Asset pipeline | CSS/JS bundling and serving |
| Rich query DSL (joins, preload, scopes) | Complex data access is natural |
| Testing utilities | First-class spec helpers |
| `has_many :through` + polymorphic associations | Advanced model relationships |

---

## Realistic estimate

Reaching **v0.1** (blog demo + scaffold + core ORM + CLI) was the bulk of the
effort; the ORM consumed the largest share, as expected — it is the heart of
the framework. The remaining phases (CLI, generators, hardening, auth, asset
pipeline) are incremental on top of a working, spec-covered stack.

## Golden rules

1. **Specs from day one** — each phase ends with its specs passing.
2. **Never skip a phase's exit criterion** — building a later phase before a
   working slice exists is wasted effort.
3. **Every week, something visible** — eyes on the demo, not just internals.
4. **Hold off the complex 20%** — polymorphic associations, STI and
   `has_many :through` come after the first release, not before.
