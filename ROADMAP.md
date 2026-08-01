# Altair Roadmap

> **Philosophy:** every phase ends with something working and visible —
> vertical slices, not horizontal scaffolding. Each phase has a clear exit
> criterion.

## Current status

| Phase | Focus | Status |
|---|---|---|
| 0 | Foundation | Completed |
| 1 | Router | Completed |
| 2 | Controllers | Next |
| 3 | Views | Planned |
| 4 | CLI | Planned |
| 5 | ORM | Planned |
| 6 | Generators | Planned |
| 7 | Hardening | Planned |
| 8 | Post-release | Planned |

---

## Phase 0: Foundation (completed)

| Task | Exit criterion |
|---|---|
| Application core (`Altair::Application`) | App boots and answers a request |
| Request / Response abstractions + params | Query params and body are readable |
| Configuration system | Per-environment settings load correctly |

## Phase 1: Router (completed)

| Task | Exit criterion |
|---|---|
| Routing DSL: `get` / `post` / `put` / `patch` / `delete` + `namespace` | Routes written naturally |
| Path params (`:id`) | `/users/5` yields `params["id"] == "5"` |
| Named routes (`user_path`) | Paths callable by name |
| `resources` macro | One line generates seven REST routes |
| 404 / 405 handling | Wrong path and wrong method return proper responses |

## Phase 2: Controllers

| Task | Exit criterion |
|---|---|
| Controller base: render, redirect, params | A full controller works end to end |
| Middleware pipeline | Logger + static files |

## Phase 3: Views

| Task | Exit criterion |
|---|---|
| Auto-escaping by default (`<%= %>` escapes, `<%== %>` raw) | XSS-safe out of the box |
| Layouts + `yield` | Pages share a header and footer |
| Partials (`render "form"`) | File reuse |
| Helpers: `link_to`, `content_tag`, basic form builder | Live HTML demo viewable in the browser |

## Phase 4: CLI

| Task | Exit criterion |
|---|---|
| `altair new blog` | Generates the standard project layout: `app/`, `config/`, `db/` |
| `altair server` | Single command to run |
| `altair routes` | Prints the route table |

## Phase 5: ORM — `Altair::Record` (the big one)

| Task | Exit criterion |
|---|---|
| Connection + config (SQLite first, PostgreSQL ready) | App connects to a database |
| Migrations DSL + `db:migrate` / `db:rollback` | Table created and dropped |
| `schema.cr` generation | Wrong column is a compile error |
| CRUD + finders (`find_by_*`) | Natural row handling |
| Validations | `valid?` + errors |
| Associations: `belongs_to` / `has_many` / `has_one` | `user.posts` works |
| Callbacks + transactions | Automatic saves + safe operations |

## Phase 6: Generators (the magic moment)

| Task | Exit criterion |
|---|---|
| `altair g model/migration/controller` | Ready-to-edit files generated |
| `altair g scaffold Post title:string body:text` | Full generator: model + migration + controller + views |
| Full blog demo (scaffold + validations + associations) | New project + scaffold + server works out of the box |

## Phase 7: Hardening

| Task | Exit criterion |
|---|---|
| Sessions + flash + CSRF | Simple login works |
| Beautiful error pages in development | Fast debugging experience |
| `database.yml` / `.env` config | Production-ready project |
| Maintenance: Ameba (linter) + specs everywhere | Real project quality |

## Phase 8: Post-release

| Task | Exit criterion |
|---|---|
| Background jobs | Scheduled work runs |
| Full authentication | Registration, login, logout |
| Asset pipeline | CSS/JS bundling and serving |
| Rich query DSL (joins, preload, scopes) | Complex data access is natural |
| Testing utilities | First-class spec helpers |
| `has_many :through` + polymorphic associations | Advanced model relationships |

---

## Realistic estimate

**3.5 – 5 months** of serious work to reach v0.1 (blog demo + scaffold + core
ORM). The ORM will consume roughly 40% of the time — expected, it is the
heart of the framework.

## Golden rules

1. **Specs from day one** — each phase ends with its specs passing.
2. **Never skip a phase's exit criterion** — building the ORM before a
   working demo exists is wasted effort.
3. **Every week, something visible** — eyes on the demo, not just internals.
4. **Hold off the complex 20%** — polymorphic associations and STI come after
   the first release, not before.
