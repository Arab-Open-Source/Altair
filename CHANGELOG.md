# Changelog

All notable changes to Altair will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Granular query instrumentation**: `Altair::Record.on_query_event`
  receives a `QueryEvent` per statement with `checkout_wait`, `sql_time`
  and `decode_time` reported separately — so pool and admission wait are
  never mistaken for SQL time. The event also carries the operation type
  (`Query`/`Insert`/`Update`/`Delete`/`Other`), the adapter name and a
  `success` flag, and it fires in an `ensure` so failed statements are
  reported too (without ever exposing bind values). The legacy `on_query`
  hook keeps its single-total-duration contract unchanged. A bare app with
  no handler still pays zero clock reads.
- **`Connection#pool_stats`**: on-demand open/idle/in-flight/max connection
  counts for observability; opt-in and never on the hot path.
- **Bounded admission wait**: `config.db_admission_timeout` (default 5s)
  caps how long a request waits on the FIFO permit gate for a database
  permit. Past the deadline the request raises
  `Altair::Concurrency::Timeout` (a 503 by default) instead of parking in
  the gate forever, and any partially-acquired permit is released.

### Changed

- **`Altair::Record.connection` is lock-free once open**: the steady path
  reads the cached connection directly; the init mutex is only taken to
  open, close or reopen the pool (double-checked). High-concurrency first
  touch still opens exactly one pool.
- **The admission gate is clamped to the pool's maximum** — a
  `db_max_active_queries` larger than `db_max_pool_size` caps nothing, so
  it is clamped (and logged) instead of arming a meaningless bound.
- **`belongs_to` memoizes an explicitly preloaded/assigned `nil`**, so
  touching an eager-loaded owner whose foreign key has no row never issues
  a per-record query — the loader no longer degrades into an N+1 when a
  foreign key is missing.

- **Database admission control**: `config.db_max_active_queries` caps how
  many fibers may hold a pooled connection at once. Requests past the
  limit wait on a FIFO permit gate outside the pool, so under overload the
  tail latency degrades gracefully instead of stacking on the pool's deep
  wait queue. `0` (the default) disables the gate and costs nothing. The
  generic `Altair::Record.on_checkout` hook it subscribes to is also
  available for tracing and query profiling.
- **benchmark_k6 example upgraded to admission control**: the Altair server
  reads `BENCH_ACTIVE` (`db_max_active_queries`) and `scripts/bench.sh`
  wires it through, so the same 200-connection budget now parks excess VUs
  on the gate's FIFO. Under the committed profile this collapsed the tail
  (read max 991 → 617 ms, write max 1,782 → 918 ms) with no throughput
  loss.
- **`render json:` accepts any JSON-able object** — hashes, named tuples,
  arrays and `JSON::Serializable` models are serialized with `to_json`
  before the response is written; a pre-serialized JSON string still passes
  through untouched.
- **`Relation#count` and `Relation#size`** run `COUNT(*)` with the scoped
  `where` clauses instead of materializing the table — and reuse the
  cached rows once the relation is loaded. Counting a relation is one
  query and no row loading.
- **Development N+1 detector**: in the Development environment the
  framework counts identical SQL within each request and logs a warning
  when a statement fires more than `config.n_plus_one_threshold` (3)
  times — the signature of lazy association access in a loop. Production
  never registers the hook; disable with `config.detect_n_plus_one =
  false`.
- **Parallel execution by default**: the server resizes Crystal's
  execution context to the available workers on boot instead of running
  on the runtime's single default OS thread. Honors `CRYSTAL_WORKERS`
  (set it to your CPU limit in containers); disable with
  `config.parallel_execution = false`.
- **`redirect_back(fallback:)`** redirects to the `Referer` header when it
  points at the same host, falling back to the given path otherwise —
  open-redirect protection built in.
- **`request.format`** reports the requested format as a `Symbol` — the
  path's format suffix (`/posts.json` → `:json`) wins over the `Accept`
  header, which wins over the `:html` default.
- **JSON request bodies**: an `application/json` body is parsed into
  `request.json` (`JSON::Any`), and its top-level scalar values join
  `params` alongside query and form values (query wins on conflicts).
  Malformed JSON bodies are ignored instead of crashing the request.
- **`head` answers bodyless**: the response suppresses any body written
  after `head`, so an action that calls `head` and then renders still
  answers empty. `no_content` is a convenience wrapper for a bare 204.
- **Controller callbacks**: `before_action` / `after_action` run around the
  action, filtered by `only:` / `except:` and inherited across the
  controller hierarchy. A before callback that writes a response (render,
  redirect, head) halts the chain — the action and its after callbacks are
  skipped. `skip_before_action` / `skip_after_action` remove an inherited
  filter for selected actions without affecting sibling controllers. The
  dispatch wrapper lives in the router, and callback ancestry is recorded
  at class-definition time so resolution needs no runtime reflection.
- **`rescue_from`**: a controller names an exception class and a handler
  method (`rescue_from InvalidParams, handle_with: :render_bad_request`);
  when an action or its callbacks raise a matching exception, the handler
  answers instead of the error bubbling to the debug pages. Subclass
  exceptions match the registered type, `only:` / `except:` filter the
  actions, handlers inherit across the hierarchy, and unmatched exceptions
  re-raise. Matching is compiled per declaration (`e.is_a?(Foo)`), never
  runtime reflection.
- **`respond_to`**: one action, several format handlers. The block declares
  `format.html { }`, `format.json { }` and `format.text { }`; the handler
  matching `request.format` (path suffix, then `Accept`, then `:html`) runs,
  and a request for an undeclared format answers 406 Not Acceptable.
- **Streaming bodies**: the controller `stream(content_type)` helper opens
  a chunked response body — writes to the yielded `IO` reach the client as
  they happen, with the content type set first. The building block of large
  responses and server-sent events.

### Changed

- **Warmer connection-pool defaults**: `db_initial_pool_size 2`,
  `db_max_idle_pool_size 2`, `db_max_pool_size 10` (was 1/1/5) — the pool
  no longer reconnects after every burst, and concurrent reads have room
  to run.
- **Segment-based route index**: the router buckets routes by their first
  segment (literal, parameter, glob, root) at registration time, so a
  request only tests the routes that can match it. Definition-order
  precedence is preserved by merging the buckets by registration index.

### Fixed

- **`find_each` keeps the scoped filters and eager loading across
  batches**: batches now inherit `where` clauses, bound values and
  `includes` preloaders, and the scan stops without a trailing probe
  query. Previously the filters were silently dropped — `where`
  conditions were ignored entirely and `includes` degraded into one query
  per record inside the loop.

- **`_method` override end-to-end**: a `_method=DELETE` form now reaches the
  destroy action, verified over real HTTP in the routing integration suite.
- **HEAD answers keep their body dropped on the wire**: the integration spec
  now asserts the body is empty, not just the status, so the framework's
  behavior is pinned against the stdlib.
- **`rescue_from` registrations are isolated per application class.** The
  registry no longer keys on a `Hash` of class metaclasses — Crystal's exact
  key-type check rejected subclass metaclasses, silently downgrading every
  debug 500 to a plain error — and instead filters a flat list by
  application class, so several application classes in one process never
  leak handlers into each other.
- **`send_file` quotes special characters in the filename** for the
  `Content-Disposition` header, so a file named `we"ird name.txt` is served
  with a valid header instead of an unparseable one.

### Changed

- **`Params#permit` drops absent keys instead of raising.** Strong params
  now compose: `params.require("title").permit("title", "optional")` keeps
  the required-field enforcement while optional fields simply vanish when
  missing. `require` remains the presence gate.
- **`button_to` and `form_for` escape their actions**, so a
  `"/posts?from=1&to=2"` path renders as `from=1&amp;to=2` in the HTML
  markup instead of an ambiguous raw ampersand.
- **`Route#match` builds its params hash lazily**, avoiding an allocation
  on the hot path when the route has no dynamic segments; a matched static
  route still reports empty params.

### Chore

- **Lint green again**: the `.ameba.yml` exclusion now covers the nested
  vendored `lib/` trees under the examples (`examples/**/lib/**`), and the
  remaining Ameba offenses in `src/` and `spec/` were fixed. `src spec
  examples` lints clean, unblocking the CI Lint step.

## [v0.1.2] — 2026-08-05

### Added

- **`altair update`**: the binary updates itself from the latest GitHub
  release — it downloads the platform binary, verifies its SHA-256 digest
  against the published `SHA256SUMS`, and swaps it in atomically via a
  temporary file. `--check` reports whether a newer version exists without
  installing (exit `0` when current, `1` when an update is available);
  `--force` reinstalls even when already up to date.

### Changed

- **App-context delegation**: `altair server`, `altair routes`,
  `altair db:migrate` and `altair db:rollback` no longer require the
  `bin/` prefix. From anywhere inside a project directory (subfolders
  included) the global binary walks up to the nearest project and forwards
  the command to its launcher — an executable `bin/altair` when present,
  otherwise `crystal run bin/altair.cr` for projects generated before the
  launcher existed. The old `Unknown command` hint is gone.

## [v0.1.1] — 2026-08-05

### Fixed

- **`shards install` inside a generated project**: the framework no longer


  declares `executables` in `shard.yml`, which made Shards look for a
  prebuilt `lib/altair/bin/altair` in the fetched checkout and abort with
  `Could not find executable "altair" for "altair"`. `shards build altair`
  is unaffected (it uses `targets`).
- **Project launcher**: `altair new` now writes an executable `bin/altair`
  (a POSIX `sh` wrapper that execs `crystal run bin/altair.cr`, chmod +x on
  Unix) in addition to `bin/altair.cr` and `bin/altair.cmd`, so `bin/altair
  server`, `bin/altair routes` and `bin/altair db:migrate` work exactly as
  documented. The post-`new` message and generated README now show
  `bin/altair server`.
- **Project-command hint**: running `altair server`, `altair routes`,
  `altair db:migrate` or `altair db:rollback` through the global binary
  inside a generated project points you at `bin/altair <command>` instead
  of a bare `Unknown command`.

### Added

- **Website**: a simple documentation site at
  `https://arab-open-source.github.io/Altair/`, generated from markdown in
  `website/` (landing page, install, usage, features, CLI reference), styled
  after the Altair logo palette, deployed to GitHub Pages by
  `.github/workflows/website.yml`.
- **CLI + generators (Phase 5)**: a standalone `altair` binary
  (`shards build altair`) that scaffolds, generates and drives projects.
  `altair new <name>` writes the standard layout — `src/app/{controllers,
  models,views}`, `src/config/{application,routes}.cr`, `db/schema.cr`,
  `db/migrations/`, `public/`, and `bin/altair` (a POSIX `sh` wrapper over
  `bin/altair.cr`, plus `bin/altair.cmd` on Windows) — runnable immediately. `altair g model` / `g migration` /
  `g controller` / `g scaffold Post title:string body:text` write
  ready-to-edit files; scaffold produces a RESTful controller + views, a
  `resources` route (inserted into `routes do`) and a seeded
  `db/schema.cr` so the model compiles before the first migration. Inside a
  generated project, `bin/altair server`, `bin/altair routes`,
  `bin/altair db:migrate` and `bin/altair db:rollback` drive the app. A
  generated project depends on the published shard by default or a local
  checkout via `--framework-path` (or `ALTAIR_PATH`). Windows and Linux are
  first-class — `bin/altair` works on POSIX via `sh`, `crystal run
  bin/altair.cr` works everywhere, and `bin/altair.cmd` covers Windows.

- **`altair install`**: `altair install` copies the running binary onto your
  `PATH` — `~/.local/bin` on Unix, `%USERPROFILE%\.altair\bin` on Windows —
  so the command is available directly from any shell. It prints the
  installed binary's SHA-256 digest for verification, is idempotent (a
  matching copy is a no-op), refuses to silently overwrite an existing,
  different file (pass `--force` to replace it), and honors `--dir DIR` to
  pick a location or `ALTAIR_BIN` to set the default.

- **Distributed installs**: a GitHub release pipeline
  (`.github/workflows/release.yml`) builds the `altair` binary for Linux,
  macOS and Windows (amd64 + arm64), publishes them with a `SHA256SUMS`
  file, and fail-safe installers — `scripts/install.sh` (`curl ... | sh`),
  `install.ps1` (`iex (irm ...)`) and `install.cmd` (`curl ... | cmd`) —
  download the platform binary, verify its digest against `SHA256SUMS` and
  install it onto `PATH`, overwriting nothing without `--force`/`-Force`.

- **Singular `resource`**: `resource :profile` expands to the six
  RESTful actions on `/profile` — no `index`, no `:id` — dispatching to
  the plural `ProfilesController` and generating the no-argument helpers
  `profile_path`, `new_profile_path` and `edit_profile_path`.
  `only:` / `except:` and `constraints:` work as on `resources`. The block
  mirrors `resources`: `member` / `collection` routes carry no id
  (`member { get :preview }` → `GET /profile/preview` +
  `preview_profile_path`), and nested `resources` — or another singular
  `resource` — hang off the singular path without a parent parameter
  (`/account/comments`, `account_comments_path`). A singular `resource`
  can also nest under a plural `resources` (`/users/:user_id/avatar`, with
  `:user_id` the only helper argument).

- **Glob path segments**: `get "/files/*path"` matches any multi-segment
  remainder, captured into `params["path"]` URI-decoded and joined with
  `/` (`/files/a/b` → `"a/b"`). The glob must be the last segment and
  needs a name. Because the glob owns the rest of the path, a format
  suffix is never stripped from it (`/files/a.txt` → `path` = `"a.txt"`),
  and a glob-only router answers 404 on the bare prefix. `named:` helpers
  take the captured string (`files_path("a/b")`).

- **Permanent redirects**: `redirect "/old/draft", to: "/posts"` answers
  every method on `/old/draft` with 301 (Moved Permanently) and a
  `Location` header. Redirects match any method (`ANY`) but never appear
  in a 405 `Allow` header, and they nest inside `namespace` blocks.

- **`resources` blocks**: `resources :posts do ... end` now accepts a block
  with custom `member` / `collection` routes and nested `resources`. Member
  actions expand to `/posts/:id/<action>` with a `<action>_<singular>_path`
  helper (`get :preview` → `GET /posts/:id/preview`, `preview_post_path(id)`);
  collection actions expand to `/posts/<action>` with a
  `<action>_<plural>_path` helper (`get :export` → `GET /posts/export`,
  `export_posts_path`); `named:` overrides the helper name. Nested
  `resources :comments` expand to `/posts/:post_id/comments` (and friends)
  with helpers like `post_comments_path(post_id)`, and nest inside
  namespaces too. Collection routes register before the standard seven so
  `/posts/export` is not swallowed by `/posts/:id`. `only:` / `except:` now
  also accept a bare symbol (`resources :posts, only: :create`) in addition
  to an array.

- **Smarter pluralization for `resources`**: words whose plural is plain
  `+s` (`notes`, `courses`, `addresses` handled correctly) no longer get
  mangled by the `+es` rule; sibilant and `-o` stems (`boxes`,
  `churches`, `heroes`) keep their `+es` handling.

- **Implicit format suffix**: any path ending in `.{ext}` is also tried
  with the extension stripped, and the extension lands in
  `params["format"]` — `/posts/5.json` dispatches `GET /posts/:id` with
  `id` = `5`, `format` = `json`. The exact path is tried second, so a
  literal dotted route such as `/sitemap.xml` still matches unchanged.
  Works for `HEAD` and 405 detection too.

- **Route constraints**: every verb route and `resources` block accepts
  `constraints: { id: /\d+/ }`. A route only matches when each
  constrained parameter satisfies its regex, with the whole value
  anchored (`/\d+/` rejects `"55x"`). Constraints propagate to
  `member`/`collection` routes and nested `resources`, and invalid
  parameter paths answer 404 instead of 405.

### Fixed

- **Lock-free connection lookup outside transactions**:
  `Altair::Record::Connection#active_connection` no longer takes the
  connection mutex for every statement. An `Atomic(Int32)` transaction
  counter gives a cheap fast path: when no transaction is open the lookup
  returns nil without touching the mutex (the mutex still protects the map
  during register/clear). Under benchmark load this removed a global lock
  acquisition from every single-statement query.

- **Thread-safe transaction state**: `Altair::Record::Connection` now guards
  its per-fiber transaction map and savepoint counters with a mutex. Under
  parallel load the unsynchronized map could corrupt — a fiber would freeze
  inside the transaction teardown and strand its pooled connection open
  (`idle in transaction`) until the pool was exhausted and requests started
  failing with `DB::PoolTimeout`. Proven by a new adapter-contract churn spec
  that hammers a 50-connection PostgreSQL pool from 8 threads and asserts
  every connection returns to the pool.

### Changed

- **Fair cross-framework benchmark**: the k6 comparison now runs all three
  frameworks (Altair, Express, Fiber) under the **same 200-connection budget**
  (PostgreSQL `max_connections=220`), instead of Altair at 200 against
  Express/Fiber at 8×50. The runner (`examples/benchmark_k6/scripts/bench.sh`)
  now exports p99/p99.9 trend stats and the summary includes them. The README's
  pool claims, results tables, and the tail-latency investigation write-up were
  updated to match the fair numbers (Altair read 14,096 req/s / write 11,889
  req/s). A parallel **Rails-vs-Altair** comparison
  (`examples/rails-vs-altair`) stages the same 500/1000/2000-tiered k6 load
  against a 2-CPU/3-GB PostgreSQL and runs both stacks on the host with the
  same 200-connection budget; its runner always stops leftover apps first so a
  stale server's pooled connections can no longer starve a run.

- **Per-statement timing only when instrumented**:
  `Altair::Record::Connection#exec` / `#query` / `#query_one` only read the
  clock and call the `on_query` hook when a handler is registered
  (`Altair::Record.query_handlers?`). With no handler, both `Time.instant`
  calls and the hook dispatch are skipped entirely.

- **Single-statement saves for callback-free models**: `save` no longer wraps
  the insert or update in a transaction when the model has no callbacks — one
  round trip instead of three. Models with callbacks keep the transactional
  guarantee that a raise rolls everything back.

- **The connection pool opens exactly once**: `Altair::Record.connection`
  synchronizes its lazy open, so first-touch load from many threads can no
  longer construct several pools and blow past the database's connection
  limit.

### Added

- **Compile-time SELECT prefix**: the `table` macro now emits a
  `self.select_sql` constant containing `SELECT "col1", "col2", ... FROM
  "table"`, so `find` / `find_by` / `first` no longer build the SELECT prefix
  by concatenating strings on every call.

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
