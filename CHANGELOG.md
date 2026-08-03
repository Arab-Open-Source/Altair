# Changelog

All notable changes to Altair will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Configurable database pool warm-up**: `db_initial_pool_size` and
  `db_max_idle_pool_size` now control how many connections the pool opens
  up front and how many idle connections it keeps warm. The previous fixed
  defaults (initial 1, max idle 1) caused reconnect churn under concurrent
  load, which showed up as a long latency tail in the k6 benchmark.

- **List, range, format and confirmation validations**:
  `validates_inclusion_of` / `validates_exclusion_of` (against an array or
  integer range), `validates_format_of` (against a regex with `with:`), and
  `validates_confirmation_of` (pairing a column with a
  `#{attribute}_confirmation` accessor).

- **Fiber-safe connection state**: transaction scoping and savepoint counters
  are keyed by `Fiber.current` instead of shared singleton state, so
  concurrent requests no longer leak a fiber's connection or collide
  savepoint names. Proven by new concurrency specs that run for real on
  PostgreSQL, with SQLite correctly pending (it is single-writer).

- **Dirty tracking with partial updates**: `save` on a persisted record now
  writes only the columns that changed since load or the last save, so a
  no-op save emits no `UPDATE`. Timestamps and timestamp updates still flow
  through the setter path.

- **Transactional saves and deletes**: `save` and `delete` run inside a
  transaction, so a callback (or a database error) raises and rolls back
  the entire persist. Previously a raise after insert/update left the row
  written.

- **JSON columns**: `:json` is now a first-class model type mapped to
  `JSON::Any`, flowing through an adapter coercion layer — bound as text on
  PostgreSQL (cast into `JSONB`) and SQLite, parsed back on read.

- **BigInt primary keys**: a model whose id column is `:bigint` now types
  its primary key as `Int64` end to end (create, `find`, `exists?`, update,
  delete). `create_table`/`schema.table` accept `id: :bigint` and the
  adapters render the matching identity column (`BIGINT PRIMARY KEY
  AUTOINCREMENT` / `BIGINT GENERATED ALWAYS AS IDENTITY`).

- **Decimal columns**: `:decimal` maps to `BigDecimal` and flows through the
  same coercion layer as JSON — bound as text, cast into the backend's
  decimal type (`NUMERIC` on PostgreSQL, `TEXT` on SQLite) and parsed back
  with full precision. `t.decimal` is part of the migration DSL.
  `will/crystal-pg` adapter with `$n` placeholders, identity primary keys,
  `TEXT` string/text columns and `INSERT ... RETURNING`. SQLite remains the
  default; the adapter contract suite runs against SQLite always and against
  PostgreSQL when `ALTAIR_TEST_PG_URL` is configured. `examples/blog` accepts
  `ALTAIR_DB_URL` to run the same persistence demo on either backend.
  `examples/sqlite_crud` and `examples/postgresql_crud` provide complete MVC
  web applications with REST controllers, ECR views and ORM-backed CRUD.

- **Uniqueness validation**: models can declare
  `validates_uniqueness_of`, including an optional `scope:` and custom
  messages. The current record is excluded during updates and `nil` values
  are allowed.

- **`Altair::Record` wave 3 — associations**: `belongs_to`,
  `has_many` and `has_one` macros generate typed accessors with
  per-instance caching, plus setter support for `belongs_to`; the
  `class_name:`, `foreign_key:` and `dependent:` options cover
  `:destroy` / `:delete_all` / `:nullify` (destroy and nullify run as
  `before_destroy` callbacks). `Relation(T)` — returned by `all` —
  is an `Enumerable` whose `includes(:name)` preloads the association
  for every record in one extra query, so a loop over `post.comments`
  never runs N queries; an unknown association name is a compile-time
  error. `examples/blog` now has comments: a `Comment` model
  `belongs_to :post`, `has_many :comments, dependent: :destroy` on
  `Post`, a comments form on the post page (422 with the error inline)
  and comment counts on the index — comments survive restarts and are
  destroyed with their post.

- **`Altair::Record` wave 2 — CRUD, finders, validations, timestamps and
  callbacks**: the `table :name` macro reads compile-time column metadata
  from `db/schema.cr` and generates typed attributes, a defaults-aware
  `initialize`, `create`, `save`/`save!`, `update`, `delete`,
  `find`/`find!`, `all`, `count`, `exists?`, `find_by_*`/`find_by_*!`
  finders for every column and `pluck`. Validations cover presence,
  length and numericality (`validates_presence_of`,
  `validates_length_of`, `validates_numericality_of`) with custom
  messages and custom methods via `validate`; errors collect into
  `errors[:attribute]` / `errors.full_messages`. `created_at` /
  `updated_at` are maintained automatically, and the eight save/create/
  update/destroy callbacks (`before_save`, `after_destroy`, ...) run in
  the standard order. Transactions nest through savepoints, and an inner
  `DB::Rollback` discards only the inner work. The generated
  `db/schema.cr` now also carries a compile-time `META` constant (the
  model macros' source of truth) and its index lines are formatter-clean.
  `examples/blog` grew a real `Post` model with full CRUD (validations
  answer 422 with the error on the form; posts and their timestamps
  survive restarts).

- **`Altair::Record` wave 1 — the ORM foundation**: an adapter interface
  with a SQLite3 implementation, a pooled connection wired to
  `config.db_url` (`db_max_pool_size`, `db_checkout_timeout`,
  `db_query_timeout`), and an `on_query` instrumentation hook. The
  migrations layer ships a DSL (`create_table`, `drop_table`,
  `add_column`, `remove_column`, `add_index`, `remove_index`,
  `change_column_null`, typed columns) with timestamped files, a
  `schema_migrations` table, a runner (`migrate` / `rollback`) and
  automatic `db/schema.cr` regeneration — the schema file and the
  database can never drift apart. Every migration applies inside a
  transaction, so a failing migration rolls back completely. SQLite
  connections run in WAL journaling mode with a 5s busy timeout by
  default. `examples/blog` is the persistence demo: posts survive server
  restarts.
- **`rescue_from`**: map exceptions to responses instead of a bare 500.
  `rescue_from KeyError, to: 404` answers the given status;
  `rescue_from MyError, handler: :my_handler` calls an instance method on
  the application (with the exception, request and response); a block form
  takes `|exception, request, response|`. Registrations are checked in
  declaration order with subclass matching, so a 404-style catch-all can
  coexist with specific handlers. `Altair::HTTP::ParamsError` (422) and the
  other HTTP errors always win over `rescue_from`.

- **Typed parameter fetching** (`Altair::HTTP::Params`): `fetch("id",
  Int32)` returns a real `Int32` — missing or malformed values raise
  `Altair::HTTP::ParamsError` (422 Unprocessable Entity, never a 500).
  Overloads cover String, Int32, Int64, Float64 and Bool (true/1/yes/on,
  false/0/no/off); `fetch?` returns `nil` instead of raising;
  `fetch_all("tags")` returns repeated parameters in order; `require`
  + `permit` implement the strong-params pattern with `KeyError` on
  missing keys.

- **`send_file` and `stream`** on `Altair::HTTP::Response`: `send_file`
  streams a file with its MIME type, `Content-Length` and an inline
  `Content-Disposition`; `stream` hands over the response body for custom
  writing.

- **Typed route references**: the route DSL accepts `to:
  PagesController.index` — a typed, rename-safe reference to a controller
  action — alongside the classic `"pages#index"` strings. A renamed or
  mistyped action fails at compile time. `get`, `post`, `put`, `patch`,
  `delete` and `root` all accept both forms.

- **Typed render methods**: `templates`-generated `render_*` methods now
  take their locals as typed parameters (`render_index(posts :
  Array(Post))`) instead of an untyped bag — passing a wrong local is a
  compile error. The `render :index, locals: {...}` dispatch validates
  the bag at runtime for full-page renders.

- **Block components**: `content_tag` gained a block form —
  `content_tag(:article, class: "card") { ... }` — for composing small
  view components from other helpers.

- **htmx response headers, complete set**: `hx_trigger_after_settle`,
  `hx_trigger_after_swap`, `hx_retarget`, `hx_reselect` and
  `hx_stop_polling` join `hx_trigger`, `hx_redirect`, `hx_location`,
  `hx_refresh` and `hx_push_url` in `Altair::Htmx::Headers`.

- **Request body size limit**: requests are rejected with `413 Payload
  Too Large` when their body exceeds the configured limit. The default is
  2 MB; raise or lower it with `config.max_body_size`, or set it per
  environment (`config.environments.<env>.max_body_size`) — a `nil` limit
  disables the protection entirely. The body is read through a
  `IO::Sized` wrapper, so the limit applies to chunked requests too and
  never trusts the `Content-Length` header. The 413 response is plain
  text and never echoes the rejected body.

- **Boot banner**: `altair run` applications print a boxed summary at
  startup — environment, listening URL (shown as `localhost` when bound to
  `0.0.0.0`), and the application's route and middleware counts —
  replacing the two plain log lines that used to precede the request log.

- **Phase 3 — Views**: compile-time templates with safe defaults, layouts,
  partials and an optional htmx layer.
  - The `templates` macro: `.ecr` files are
    transpiled at compile time into typed `render_*` methods. `<%= %>`
    escapes HTML by default, `<%== %>` is raw and `<%%` writes a literal
    `<%`. Locals are declared per template (`index: {posts: Array(Post)}`),
    and a missing file or a wrong local raises a clear error.
  - `render :index` renders a full page inside the layout; `render :index,
    layout: false` renders a bare fragment — the building block of htmx
    flows; `render "form", locals: {...}` renders a partial returning a
    String. The same actions serve both worlds.
  - Layouts with `yield` (`layouts/application.ecr`), declared per
    controller in the `templates` call.
  - Helpers (`Altair::View::Helpers`): `link_to`, `content_tag`,
    `button_to` (with the `_method` override for non-GET verbs) and
    `javascript_include_tag :htmx`.
  - Form builder: `form_for` in templates (the transpiler passes the
    output buffer automatically) with `label`, `text_field`,
    `email_field`, `password_field`, `hidden_field` and `submit` — every
    helper escapes its values.
  - htmx is a convention, not a dependency: any `hx_*` attribute becomes
    `hx-*` in the helpers, `request.hx_request?` detects `HX-Request`,
    `hx_trigger(:event)` sets the `HX-Trigger` response header, and
    `javascript_include_tag :htmx` resolves the script source from the
    `from:` argument, `config.htmx_src`, `config.htmx_version` or the
    pinned default CDN (`Altair::Htmx::VERSION = "2.0.10"`).
  - `examples/htmx` — a no-reload tasks demo: add, inline-edit and delete
    tasks with fragment swaps and a toast driven by `HX-Trigger`.
  - 7 new end-to-end view specs (full page, fragments, escaping, partials,
    htmx create) — 162 total.

- **Smart error pages**: development-mode responses that help when things
  break, before the Phase 3 developer-experience push.
  - `Altair::Core::ErrorPages` — debug-mode pages for 404, 405 and 500 in
    the welcome page's visual family.
  - A 404 suggests nearby routes ("Did you mean?") ranked by edit
    distance, with param segments counting as wildcards; clickable routes
    link to the suggested path, and every suggestion shows the exact
    route line to add (`get "/post", to: "posts#index"`) with a copy
    button.
  - A 405 lists the methods the path accepts and shows the hidden
    `_method` field that sends the rejected method from a form.
  - A 500 renders a full diagnostic: the request context (method, path,
    parameters, safe headers — `Authorization` and `Cookie` are never
    shown), the route that was handling the request, the exception chain
    down to the root cause, a source preview highlighting the failing
    line, and the complete backtrace.
  - Every page carries an environment strip (application, version, env,
    route and middleware counts), and every echoed value is
    HTML-escaped.
  - `Altair::Routing::Router#closest_to` — the route-suggestion engine.
  - Outside debug mode responses stay plain text with the standard
    `Allow` header: the route table never leaks in production.
  - 25 new specs: the suggestion engine and end-to-end error pages in
    both debug and production modes.

- **Phase 2 — Controllers**: instance controllers with rendering, redirects
  and middleware.
  - `Altair::Controller` base class: per-request instances with
    `request` / `response` / `params` accessors, a `render` API
    (`render html:`, `render text:`, `render json:` with optional status),
    `redirect_to` and `head`.
  - Route dispatch through instance controllers: `posts#show` expands to
    `PostsController.new(request, response).show`, so actions are plain
    instance methods checked by the compiler.
  - Generated path helpers now live in the application's `RouteHelpers`
    module: still callable on the subclass (`Blog.post_path(5)`) and
    includable by controllers for bare calls (`posts_path`).
  - Middleware pipeline: `Altair::Middleware` base class with a
    `call(request, response, chain)` contract, a `use` macro on
    `Altair::Application` and a `config.middleware` factory-proc stack.
  - `Altair::Middleware::Logger` — one line per request (method, path,
    status, duration) through the application's logger.
  - `Altair::Middleware::Static` — serves `public/` with content-type
    mapping and path-traversal protection.
  - `Altair::HTTP::Response#text` — plain-text responses.
  - `examples/hello_world` rewritten on instance controllers: an
    `ApplicationController` base including the generated helpers, a
    stylesheet served from `public/` and the full posts lifecycle
    (create, edit, update, delete) over real HTTP.
  - 32 new specs: controller base, end-to-end controller integration,
    middleware chain contract, logger, static files (including traversal
    attempts) and the `RouteHelpers` module.

- **Phase 1 — Router**: a conventional routing layer built with
  compile-time macros.
  - `routes do ... end` DSL with `get` / `post` / `put` / `patch` / `delete`,
    `root`, `namespace` and `resources`, plus `to:` actions, inline handler
    blocks and `named:` routes.
  - `resources :posts` expands to the seven RESTful routes in conventional
    order with `only:` / `except:` filters and generated helpers
    (`posts_path`, `new_post_path`, `post_path(5)`, `edit_post_path(5)`).
  - `namespace :admin` prefixes paths, controllers and helper names
    (`admin_posts_path`), with full nesting (`api/v1` → `api_v1_users_path`).
  - Compile-time path helpers: `user_path(5)` → `/users/5`, generated as
    class methods on the application subclass.
  - `Altair::Routing` — `Segment` / `Route` / `RouteSet` / `Router` matching
    engine: segment-wise static/parameter matching, definition-order
    priority, HEAD-requests-GET, URI-decoded params and 405 detection.
  - Dispatch in `Altair::Core::RequestHandler` through the router with
    404 for unknown paths and 405 + `Allow` header for wrong methods;
    the welcome page now only appears while the route set is empty.
  - `Altair::HTTP::MethodNotAllowed` exception with the allowed methods.
  - `_method` form override for `PUT` / `PATCH` / `DELETE` submissions.
  - `Altair::HTTP::Request#form_params` for
    `application/x-www-form-urlencoded` bodies.
  - `examples/hello_world` routes and controllers: a live pages + posts
    demo verified over real HTTP (params, redirects, 404/405).
  - 52 new routing specs: route set, router matching, DSL, resources,
    namespaces, named routes and end-to-end HTTP integration.

- **Phase 0 — Foundation**: the application core and HTTP layer.
  - `Altair::Application` — conventional application subclass with a `config`
    accessor, singleton `instance`, automatic root detection and `run!`.
  - `Altair::Config` — typed application configuration with per-environment
    settings bags (`development`, `production`, `test`), mirroring
    `config/environments/*.rb`.
  - `Altair::Env` — environment enum resolved from `ALTAIR_ENV`, defaulting
    to `development`.
  - `Altair::Server` — lifecycle management over `HTTP::Server` with
    graceful shutdown via `Process.on_terminate`.
  - `Altair::Core::RequestHandler` — request entry point with a
    welcome page for `/`, 404 handling and a top-level error boundary.
  - `Altair::HTTP::Request` / `Response` / `Params` — framework-owned HTTP
    abstractions: unified parameter bags (route > query > body precedence),
    JSON/HTML/redirect helpers and typed status setting.
  - `Altair::Support::Inflector` — pluralize / singularize / camelize /
    underscore with irregular and uncountable noun support.
  - Exception hierarchy rooted at `Altair::Error`, including
    `Altair::ConfigurationError` and `Altair::HTTP::Error` /
    `Altair::HTTP::NotFound`.
  - `examples/hello_world` — a minimal working Altair application with a
    conventional `config/application.cr`.
  - CI pipeline (format check, Ameba, specs, example build) and Ameba as a
    development dependency.
