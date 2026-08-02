# <p align="center"><img src=".github/assets/logo.png" width="180" alt="Altair Logo"></p>

<h1 align="center">Altair</h1>

<p align="center">
  The batteries-included web framework for Crystal.
</p>

<p align="center">
  <strong>Fast.</strong> • <strong>Elegant.</strong> • <strong>Productive.</strong>
</p>

---

Altair is a modern, batteries-included web framework for Crystal, built around
the principles of convention over configuration and developer happiness.

Its goal is to provide an exceptional developer experience while taking
advantage of Crystal's native performance, low memory usage and single-binary
deployment.

> **Status:** early development (pre-alpha) — Phases 0–4 complete

## Under development

Altair is built in phases, each ending with something working and visible.
Phases 0–4 are complete: the application core, router, controllers, the
view stack, and the ORM (`Altair::Record`) all ship with passing specs.
The ORM supports SQLite3 and PostgreSQL, with migrations, schema generation,
CRUD, validations, associations, callbacks, and a contract test suite that
runs against both backends. The next milestone is the CLI
(`altair new`, `altair server`, `altair routes`), followed by generators,
sessions/flash/CSRF, and the remaining hardening work.

What is already in place:

| Area | What is implemented |
|------|---------------------|
| Application | subclassed per project, typed config, per-env settings, singleton instance, `rescue_from` exception mapping |
| HTTP | request/response wrappers, merged param bag (route > query > body), typed param fetching (`fetch`/`require`/`permit`), file streaming with `send_file`, JSON/HTML/redirect helpers |
| Routing | compile-time DSL, typed references to controller actions, path params, named helpers as real methods, 404/405 from the router |
| Controllers | per-request instances, `render`/`redirect_to`/`head`, `_method` override |
| Views | compile-time `.ecr` templates with typed locals, layouts, partials, helpers (incl. block components), form builder, auto-escaping |
| htmx | `hx_*` attributes, `hx_request?`, trigger/redirect/retarget response headers, fragment rendering |
| Middleware | `use`-based pipeline, request logging, static files with traversal protection |
| Errors | `rescue_from`, smart debug pages (404 suggestions, 405 methods, 500 diagnostics), plain in production |
| Hardening | 2 MB request-body limit, `413` before the body is read |
| ORM (`Altair::Record`) | adapter interface + SQLite3 and PostgreSQL adapters, connection pooling, migrations DSL + runner, `db/schema.cr` generation, CRUD + finders, validations (`valid?` + errors), timestamps + callbacks, associations (`belongs_to` / `has_many` / `has_one`) with batched eager loading, `dependent:` handling, `validates_uniqueness_of`, multi-database support via `ALTAIR_DB_URL` |

What is still missing (in rough order): the CLI, generators and scaffolding,
sessions/flash/CSRF, multipart parsing, `.env` / `database.yml` configuration,
background jobs, authentication, asset pipeline, rich query DSL, testing
utilities.

---

## Features

### Implemented

- **Application core** — a conventional application subclass with typed
  configuration, per-environment settings, a singleton application
  instance, and `rescue_from`, which maps exception classes to status
  codes or handler methods instead of a bare 500.
- **HTTP layer** — framework-owned request and response wrappers, a unified
  parameter bag (route, query and body precedence), typed parameter
  fetching — `params.fetch("id", Int32)` returns an `Int32` or raises a
  422, `params.require("title")`/`params.permit("title", "body")` for the
  strong-params pattern, `params.fetch_all("tags")` for repeated
  parameters — and `send_file`/`stream` for file downloads. JSON, HTML and
  redirect helpers included.
- **Routing** — a compile-time route DSL with `get`, `post`, `put`, `patch`,
  `delete`, `root`, `namespace` and `resources`; path parameters; named path
  helpers generated as real methods; 404/405 responses served by the
  router; and typed references to actions — `to: PagesController.index` —
  so renaming an action breaks the build instead of the page.
- **Controllers** — per-request instances of `Altair::Controller` with
  `render` (html/text/json), `redirect_to`, `head` and a merged parameter
  bag; generated path helpers available in controllers via the
  `RouteHelpers` module.
- **Views** — compile-time templates (`.ecr`) transpiled into typed
  `render_*` methods — locals are declared with their types, so a wrong
  local is a compile error — with auto-escaping (`<%= %>` escapes,
  `<%== %>` is raw), layouts with `yield`, partials, helpers including
  block components (`content_tag(:article, class: "card") { ... }`), and
  an optional htmx layer (`hx_*` attributes, `request.hx_request?`, the
  full set of response headers — `hx_trigger` variants, `hx_retarget`,
  `hx_stop_polling`, ... — and fragment rendering).
- **Middleware pipeline** — a `use`-based stack around the router, with
  built-in request logging and static-file serving from `public/` (with
  path-traversal protection).
- **Smart error pages** — in development, 404s link the routes closest to
  the requested path and show the exact route line to add (copyable with
  one click), 405s list the accepted methods and how to send them from a
  form, and 500s render a full diagnostic: request context, the route
  that was handling it, the exception chain and a highlighted source
  preview of the failing line. Production stays plain text so the route
  table never leaks.
- **Request hardening** — a 2 MB request-body limit out of the box
  (configurable, and disablable per environment), so oversized payloads
  get a `413 Payload Too Large` before they are ever read, and the
  response never echoes the rejected body.
- **Example applications** — `examples/hello_world`, a working demo with a RESTful resource, static assets and verified behavior over real HTTP; `examples/htmx`, showing the view stack and the htmx layer in the browser; `examples/blog`, the persistence demo with posts and comments surviving restarts (SQLite3 by default, PostgreSQL via `ALTAIR_DB_URL`); `examples/sqlite_crud` and `examples/postgresql_crud`, full MVC CRUD examples for the ORM on each backend.

### Planned

- CLI: `altair new`, `altair server`, `altair routes`
- Generators and scaffolding
- Sessions, flash and CSRF protection
- Multipart form parsing
- `.env` / `database.yml` configuration
- Background jobs, authentication, asset pipeline, rich query DSL,
  testing utilities

---

## Quick start

The fastest way to see Altair running is the bundled example application:

```bash
crystal run examples/hello_world/src/hello_world.cr
```

Then open <http://localhost:3000>. Routes are declared in a small,
expressive DSL:

```crystal
class HelloWorld < Altair::Application
  config.name = "Hello World"
  config.port = 3000

  rescue_from KeyError, to: 404

  routes do
    root to: PagesController.index
    get "/hello/:name", to: PagesController.hello, named: :greeting
    resources :posts
  end
end
```

Routes point at controller actions with **typed references** —
`to: PagesController.index` — so a typo or a renamed action fails at
compile time instead of answering 404 at request time. The
`resources :posts` line alone expands to seven RESTful routes and
generates their path helpers (`posts_path`, `post_path(5)`,
`edit_post_path(5)`), type-checked like any other method.

Controllers are plain classes with per-request instances, and params come
in typed when you ask for them that way:

```crystal
class PostsController < Altair::Controller
  include HelloWorld::RouteHelpers

  def show : Nil
    render html: "<h1>#{params.fetch("id", Int32)}</h1>"
  end

  def create : Nil
    params.require("title")
    redirect_to posts_path
  end
end
```

A missing or malformed `id` is a `422 Unprocessable Entity` — never a 500 —
and `require` raises before the action can do anything with missing data.

Every request dispatches to a fresh controller instance
(`PostsController.new(request, response).show`), and the middleware pipeline
— request logging and static files from `public/` by default — wraps the
router.

See [examples/hello_world/README.md](examples/hello_world/README.md) for a
full walkthrough with curl and HTTP client examples.

### Persistence with Altair::Record

Altair ships a full ORM — `Altair::Record` — with SQLite3 and PostgreSQL
adapters, migrations, validations, associations, and callbacks.

The bundled blog demo persists posts and comments across restarts:

```bash
ALTAIR_DB_URL="sqlite://db/development.sqlite3" crystal run examples/blog/src/blog.cr
```

Open <http://localhost:3000> to create, read, update, and delete posts
and comments. To use PostgreSQL instead:

```bash
ALTAIR_DB_URL="postgresql://postgres:postgres@localhost:5433/blog_development" crystal run examples/blog/src/blog.cr
```

Two standalone MVC CRUD examples are available — one for each backend:

| Example | Backend | Command |
|---------|---------|---------|
| `examples/sqlite_crud` | SQLite3 | `crystal run examples/sqlite_crud/src/sqlite_crud.cr` |
| `examples/postgresql_crud` | PostgreSQL | `ALTAIR_DB_URL="postgresql://postgres:postgres@localhost:5434/crud_development" crystal run examples/postgresql_crud/src/postgresql_crud.cr` |

Each exposes full CRUD for a `Product` resource at <http://localhost:4100>
(SQLite) or <http://localhost:4200> (PostgreSQL).

---

## Documentation

Documentation is under development. The architecture is described in
[ARCHITECTURE.md](ARCHITECTURE.md), and phase-by-phase implementation plans
live in [docs/architecture](docs/architecture).

---

## Roadmap

The project roadmap is maintained in [ROADMAP.md](ROADMAP.md).

---

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md)
before opening an issue or pull request.

---

## License

Altair is released under the [MIT License](LICENSE).
