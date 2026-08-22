# Altair Architecture

> **Status:** early development (pre-alpha) — Phases 0–4 complete.
> This document describes the architecture as it exists in the code today,
> not as a specification of future intent.

Altair is a batteries-included web framework for [Crystal](https://crystal-lang.org).
Its design is guided by three principles:

- **Convention over configuration.** Applications subclass a conventional
  `Altair::Application`; routes, controllers, views and models are discovered
  by compile-time conventions rather than runtime reflection.
- **Compile-time safety.** The router, the view layer and the ORM are built
  with Crystal macros. A typo in a route target, a missing template local, or
  a wrong model column is a *compile error*, never a runtime 500.
- **Single-binary deployment.** The framework sits on the standard library's
  `HTTP::Server` and the `DB` driver abstraction, so a whole application
  compiles to one native binary with no VM and no separate web server.

---

## 1. High-level request flow

```
                ┌─────────────────────────────────────────────┐
   HTTP request │  Altair::Server (wraps ::HTTP::Server)       │
        ───────▶│  installs SIGINT/SIGTERM handlers, prints    │
                │  the boot banner, then listens               │
                └───────────────────┬─────────────────────────┘
                                    │ ::HTTP::Handler
                                    ▼
                ┌─────────────────────────────────────────────┐
                │  Altair::Core::RequestHandler                 │
                │  wraps the raw context in Altair::HTTP::*;    │
                │  composes the middleware chain (use …) around │
                │  the router; owns the top-level error boundary │
                └───────────────────┬─────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────────┐
              ▼                     ▼                          ▼
     ┌────────────────┐   ┌──────────────────┐     ┌──────────────────────┐
     │ Middleware:    │   │ Middleware:       │     │ Altair::Routing::    │
     │ Logger         │   │ Static (public/) │     │ Router (find / 404 /  │
     └────────────────┘   └──────────────────┘     │ 405)                  │
                                                    └───────────┬──────────┘
                                                                │ match
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │ Controller action     │
                                                    │ render / redirect_to / │
                                                    │ head (+ params)       │
                                                    └───────────┬──────────┘
                                                                │
                                          ┌─────────────────────┼───────────────┐
                                          ▼                     ▼               ▼
                                  View (.ecr, typed       Altair::Record     Helpers
                                  locals, layouts,        (ORM)             (link_to,
                                  partials, htmx)                              form_for, …)
```

Every request flows through exactly one `RequestHandler`, which builds the
middleware chain **inside-out** so the first `use` runs first and the router is
the terminal link. Unknown paths raise `NotFound` (→ 404); a known path with the
wrong method raises `MethodNotAllowed` with an `Allow` header (→ 405). An
application with zero routes still answers `/` with a welcome page, so a fresh
project shows something useful before its first route is written.

---

## 2. Module map

```
src/altair/
├── altair.cr                # single require entry point (loads everything in dependency order)
├── core/
│   ├── application.cr       # Altair::Application — config, singleton, use/rescue_from, run!
│   ├── request_handler.cr   # per-request dispatch + error boundary
│   ├── error_handlers.cr    # rescue_from registry
│   ├── error_pages.cr       # dev 404/405/500 pages with route suggestions
│   └── version.cr           # Altair::VERSION
├── config/
│   ├── env.cr               # Altair.env (development/test/production)
│   ├── environments/base.cr # per-environment settings (debug?, max_body_size)
│   └── config.cr            # typed Altair::Config (name, host, port, middleware, db_url, …)
├── http/
│   ├── request.cr           # Altair::HTTP::Request (wraps ::HTTP::Request)
│   ├── response.cr          # Altair::HTTP::Response (wraps ::HTTP::Response)
│   └── params.cr            # Altair::HTTP::Params — typed, merged param bag
├── routing/
│   ├── segment.cr           # path segment model (literal vs. param)
│   ├── route.cr             # a compiled route + its handler
│   ├── route_set.cr         # per-application registry of routes + path helpers
│   ├── router.cr            # the matching engine (find / allowed_for / closest_to)
│   └── dsl.cr               # the compile-time routes DSL (get/post/…/resources/namespace)
├── controller/
│   └── base.cr              # Altair::Controller — render / redirect_to / head / params
├── view/
│   ├── template.cr          # the `templates` macro: compile-time .ecr transpiler
│   ├── helpers.cr           # link_to / content_tag / button_to / …
│   ├── form_builder.cr      # form_for and form-builder DSL
│   └── htmx.cr              # hx_* attributes + htmx response headers
├── middleware/
│   ├── base.cr              # Altair::Middleware::Base
│   ├── logger.cr            # request logging
│   └── static.cr            # static files from public/ (path-traversal protected)
├── server/
│   └── server.cr            # Altair::Server — lifecycle, signals, banner
├── exceptions/
│   ├── error.cr             # Altair::Error base
│   ├── configuration_error.cr
│   ├── http_error.cr        # NotFound / MethodNotAllowed / base HTTP error
│   ├── method_not_allowed.cr
│   └── payload_too_large.cr # → 413
├── support/
│   └── inflector.cr         # singularize/pluralize/camelcase tables
└── record/                  # Altair::Record — the ORM (see §6)
    ├── record.cr            # public entry: connection, on_query hook
    ├── adapter.cr           # Adapter interface
    ├── adapters/sqlite3.cr
    ├── adapters/postgresql.cr
    ├── connection.cr        # pooled DB::Database + transactions/savepoints
    ├── schema.cr            # generated META registry (db/schema.cr)
    ├── model.cr             # Model base: CRUD, finders, validations, callbacks
    ├── relation.cr          # Relation/query surface + includes (eager load)
    ├── association.cr       # belongs_to / has_many / has_one + batched preloaders
    └── migrations/
        ├── migration.cr     # Migration base + compile-time registry
        ├── runner.cr        # db:migrate / db:rollback
        └── schema_generator.cr # regenerates db/schema.cr
```

---

## 3. Application core

`Altair::Application` is an abstract class each project subclasses in
`config/application.cr`. Responsibilities:

- **Typed configuration** through the `config` accessor (`name`, `host`,
  `port`, `debug`, `max_body_size`, `db_url`, pool sizes, query timeout).
- **Singleton instance** — `Application.instance` lazily creates exactly one
  application object; defining a second subclass raises `ConfigurationError`.
  This enforces "one process runs exactly one application".
- **Middleware pipeline** via `use` (`config/application.cr`):
  ```crystal
  class Blog < Altair::Application
    use Altair::Middleware::Logger
    use Altair::Middleware::Static
  end
  ```
  Each `use` records a factory proc, expanded at compile time so middleware
  may keep any constructor signature. The chain is composed in
  `RequestHandler#build_chain`.
- **Exception mapping** via `rescue_from` (three forms: a fixed status, a
  handler method on the app, or a block receiving `|exception, request,
  response|`). Registrations are checked in declaration order, most specific
  first.
- **Boot** via `run!` / `start`, which builds the server, prints the boxed
  banner, and blocks on `listen`.

---

## 4. HTTP layer

- `Altair::HTTP::Request` and `Altair::HTTP::Response` wrap the standard
  library types so the framework owns the surface area and can add helpers
  (`response.html` / `.json` / `.text`, `request.hx_request?`, …).
- `Altair::HTTP::Params` is a **unified, merged param bag** over route, query
  and body parameters. Precedence is **route > query > body**. It is
  type-aware:
  - `params.fetch("id", Int32)` returns an `Int32` or raises `ParamsError`
    (→ 422), never a 500.
  - `params.require("title")` / `params.permit("title", "body")` implement
    the strong-params pattern.
  - `params.fetch_all("tags")` collects repeated parameters into an `Array`.
- **Request hardening:** a configurable 2 MB body limit (disabled per
  environment) returns `413 Payload Too Large` *before* the body is read, and
  the response never echoes the rejected payload.

---

## 5. Routing and controllers

### Routing DSL (compile-time)
Routes are declared with a macro `routes` block. Every verb macro
(`get`/`post`/`put`/`patch`/`delete`), `root`, `namespace` and `resources` runs
entirely at compile time, which yields three guarantees:

1. **Named path helpers are real methods** — `posts_path`, `post_path(5)`,
   `edit_post_path(5)` — type-checked by the compiler and gathered in the
   application's `RouteHelpers` module (controllers `include` it to call them
   bare).
2. **Typed action references** — `to: PostsController.index` resolves the
   controller and action at compile time, so a renamed or missing action fails
   the build instead of answering 404 at request time. String form
   `"posts#show"` is also supported.
3. **The route table is fully built when the application class loads**, before
   the first request.

`resources :posts` expands to the seven RESTful routes, `namespace :admin` adds
a path prefix and a `RouteHelpers` prefix, and inline handler blocks
(`get "/version" do |req, res| … end`) are supported for quick endpoints.

The `Router#find` walks the request path segment-by-segment against each
route's pre-parsed `Segment`s; the first definition-order match wins. `HEAD`
matches `GET` routes. `Router#closest_to` ranks registered patterns by edit
distance (param segments treated as wildcards) so development error pages can
suggest routes the developer may have meant.

### Controllers
`Altair::Controller` actions are plain **per-request instance methods**.
`to:` routing expands to `PostsController.new(request, response).show`, so an
action reads like ordinary Crystal and the request/response are in scope.
Controllers render with `render html:` / `text:` / `json:`, redirect with
`redirect_to`, answer headers-only with `head`, and read parameters through the
typed `params` bag. `_method` overrides (`_method=PUT|PATCH|DELETE`) are
respected for HTML forms, and `request.route` is available to actions.

---

## 6. The ORM — `Altair::Record`

The ORM is the largest component and the project's center of gravity. Its
design goal is the same compile-time safety as the rest of the framework:
**wrong columns and wrong types are compile errors**, and the database
differences are isolated behind a small adapter interface.

### 6.1 Layered design

```
Application
   └─ Altair::Record.connection        # lazy, app-scoped singleton
        └─ Connection                   # wraps a DB::Database pool
             ├─ adapter : Adapter        # SQLite3 | PostgreSQL (interface)
             ├─ exec / query / query_one # bound params only; notifies on_query
             └─ transaction / savepoint  # nested tx via SAVEPOINT

Model (Altair::Record::Model)           # one per table; column metadata from schema
   ├─ CRUD + finders (find / find_by_* / all / create / update / save / delete)
   ├─ validations (presence / length / numericality / uniqueness / custom)
   ├─ callbacks (before/after save|create|update|destroy)
   ├─ timestamps (created_at / updated_at, auto-applied)
   └─ associations (belongs_to / has_many / has_one) + batched eager loading

Migration / Runner / SchemaGenerator   # schema evolution + db/schema.cr generation
```

### 6.2 Adapter interface
Migrations, schema generation and finders talk to `Altair::Record::Adapter`,
never to a driver directly. The interface abstracts `connect`,
`quote_identifier`, `placeholder` (`?` vs `$1`), `limit_offset_clause`,
`autoincrement_pk_sql`, `last_insert_id`, `supports_returning?` and
`column_type_sql`. Adding a database means writing **one adapter**, not
touching the ORM. Two ship today: **SQLite3** (always available) and
**PostgreSQL** (opt-in — require `altair/record/adapters/postgresql` and add
`crystal-pg`; the connection picks the adapter from the URL scheme
`sqlite3://` vs `postgres(ql)://`). The adapter layer also enables **multi-database**
setups via the `ALTAIR_DB_URL` environment variable.

### 6.3 Connection and safety
`Connection` wraps a `DB::Database` pool sized from the application config
(`db_max_pool_size`, `db_checkout_timeout`, `db_query_timeout`). Every value
travels as a **bound parameter** — never interpolated into SQL. Inside a
transaction the statements run on the transaction's checked-out connection, so
the pool is never double-checked-out; nested transactions use `SAVEPOINT`s, and
`DB::Rollback` only aborts to the savepoint. Every executed statement passes
through the `Altair::Record.on_query` instrumentation hook (the base for query
logging and N+1 detection later).

### 6.4 Models and the schema
A model declares its table with the `table` macro; its column metadata is read
at compile time from the `META` constant defined by a **generated**
`db/schema.cr`:

```crystal
class Post < Altair::Record::Model
  table :posts
  has_many :comments, dependent: :destroy
  validates_presence_of :title
  before_save :normalize
end
```

The `table` macro generates typed attribute getters/setters, a typed
constructor, `find_by_<column>` finders (with `!` raising variants), `pluck`,
`create`/`update`/`save`, `valid?` + an `Errors` bag, and callback hooks. A
mismatch between the model and `db/schema.cr` is a **compile error** pointing
you at the migration to re-run — a wrong column can never reach production.

### 6.5 Validations and callbacks
Validations (`validates_presence_of`, `validates_length_of`,
`validates_numericality_of`, `validates_uniqueness_of`, and `validate :method`)
run in `valid?`, which clears and repopulates `errors`. `save` runs
validations then `before_*`/`after_*` callbacks and applies timestamps; on
failure it returns `false` (use `save!` to raise `RecordInvalid`). Callbacks
are per-subclass class variables populated by an `inherited` hook.

### 6.6 Associations and eager loading
`belongs_to`, `has_many` and `has_one` each generate a lazy, cached accessor
plus a **class-level batched preloader** registered in `@@preloaders`. Eager
loading is requested through `Relation#includes(:association)`, which runs one
`IN (…)` query per association and groups results by foreign key — eliminating
N+1 selects. `dependent:` reacts to the owner's deletion with `:destroy`
(delete children through their own callbacks), `:delete_all` (one query) or
`:nullify` (clear foreign keys).

### 6.7 Migrations and schema generation
`Migration` subclasses implement `up` (and optionally `down`). They register
themselves in a compile-time registry through an `inherited` hook, so the runner
discovers them in file order. The runner (`db:migrate` / `db:rollback`) applies
them and the `SchemaGenerator` regenerates `db/schema.cr` from the applied
schema, closing the loop between the database and the compile-time-typed models.

---

## 7. View layer

Altair does **not** use the standard library's ECR. The `templates` macro is a
self-contained **compile-time transpiler** that reads each `.ecr` file and
generates a plain `render_<name>(locals)` method. This gives the framework
ownership of the syntax and, critically, **safe defaults**:

- `<%= expr %>` HTML-escapes the expression — **XSS-safe by default**.
- `<%== expr %>` inserts raw (for trusted HTML).
- `<% code %>` embeds Crystal; `<%%` writes a literal `<%`.
- Locals are declared with their types in the `templates` macro, so a missing
  local or a missing file is a **compile error**.
- Layouts (`yield`), partials (`render "form"`) and helpers
  (`link_to`, `content_tag`, `button_to`, `form_for`) are all supported.
- The optional `htmx` layer adds `hx_*` attributes, `request.hx_request?`
  detection, full response headers (`HX-Trigger` variants, `HX-Retarget`,
  `HX-Stop-Polling`, …) and fragment rendering — so no-reload flows work while
  everything still works without JavaScript.

---

## 8. Middleware, errors and hardening

- **Middleware pipeline** — a `use`-based stack around the router. Built-ins:
  `Logger` (request logging) and `Static` (serves `public/` with
  path-traversal protection).
- **Smart error pages (development)** — 404 pages link the closest routes and
  show the exact line to add; 405 pages list the accepted methods; 500 pages
  render full diagnostics (request context, the handling route, the exception
  chain, a highlighted source preview). Production stays plain text so the
  route table never leaks.
- **Request hardening** — 2 MB body limit, `413` before the body is read.

---

## 9. Design invariants

These properties hold across the framework and are what make Altair "feel"
consistent:

1. **Compile-time over runtime.** DSLs (routing, views, ORM) are macros; the
   compiler is the integration test.
2. **Bound parameters everywhere.** No string interpolation of user input into
   SQL.
3. **Escape-by-default output.** Views escape unless explicitly marked raw.
4. **One application per process.** Enforced by the singleton instance.
5. **Specs from day one.** Each phase ships with passing specs (see `spec/`),
   including a contract suite that runs the ORM against both SQLite and
   PostgreSQL.

---

## 10. Examples

The `examples/` directory is the living documentation and the acceptance test
for the framework:

| Example | Demonstrates |
|---------|--------------|
| `hello_world` | minimal app, RESTful resource, static assets |
| `htmx` | the view stack + htmx layer (add/edit/delete without reload) |
| `blog` | persistence: posts + comments survive restarts (SQLite by default, PostgreSQL via `ALTAIR_DB_URL`) |
| `sqlite_crud` | full MVC CRUD on SQLite3 at `localhost:4100` |
| `postgresql_crud` | full MVC CRUD on PostgreSQL at `localhost:4200` |

---

## 11. Status and open areas

Implemented: application core, HTTP layer, routing, controllers, views,
middleware, smart errors, request hardening, the `Altair::Record` ORM
(SQLite + PostgreSQL, migrations, schema generation, CRUD/finders,
validations, callbacks, associations with batched eager loading, scopes,
nested includes, insert_all, dirty tracking, enum attributes, multi-db),
the CLI (`altair new` / `server` / `routes` / `db:*`), generators and
scaffolding, sessions/flash/CSRF/auth helpers, multipart parsing,
`.env`/`database.yml` config, security middleware, and testing utilities.

Not yet built (see `ROADMAP.md`): background jobs, authentication
(`altair g auth`), asset pipeline, a richer query DSL (joins,
`has_many :through`, polymorphic), prepared-statement caching, and
migration linting.
