# Changelog

All notable changes to Altair will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`after_commit` / `after_rollback` lifecycle hooks**: fire once the
  record's save or delete transaction lands (or on rollback, before the
  exception re-raises). The safe place to enqueue background jobs and
  invalidate caches — `after_save` runs inside the transaction where the
  data is not yet visible and a rollback would orphan the side effects.
- **Direct-write helpers**: `Model#touch(*columns)` bumps `updated_at`
  (plus listed timestamp columns) with one UPDATE; `increment!` /
  `decrement!` apply atomic `col = col ± n` writes. All three bypass
  callbacks, validations and dirty tracking by design.
- **Query DSL completion** (`Relation`): `where_not` (keyword pairs or a
  single column/value), `or_where` — whose alternatives fold into the
  preceding condition as one parenthesized OR group instead of ANDing with
  the whole scope — and new operators on `where`: `:like`, `:in` (an empty
  list matches nothing without hitting bind limits), and the bind-free
  `:null` / `:not_null`.
- **Relation finders**: `first` / `first?` (primary key ascending unless
  the scope orders), `last` / `last?` (reverses the scope's explicit
  ordering), `take(n)`, `ids`, `pick(:column)` and the LIMIT-1 existence
  probes `exists?` / `any?` / `none?`.
- **Bulk writes**: `Relation#update_all(**fields)` and `Relation#delete_all`
  run one statement per scope and return affected-row counts. They bypass
  callbacks, validations and timestamps by design, refuse joined relations,
  and ignore order/limit/offset (no portable meaning across engines).
- `change_column_null` now works on SQLite via table rebuild; adapters
  declare in-place capability through `Adapter#supports_alter_column_null?`.

### Fixed

- **`change_column_null` was broken on SQLite** (the default adapter): it
  emitted PostgreSQL's `ALTER TABLE ... ALTER COLUMN ... SET/DROP NOT NULL`,
  which SQLite rejects outright. Adapters now declare whether they can alter
  nullability in place (`Adapter#supports_alter_column_null?`); SQLite takes
  a rebuild path that reads the live shape with `PRAGMA table_info` (each
  migration runs against a fresh schema state, so the table may be unknown
  to it), creates a temp copy with the flipped constraint, copies the rows,
  swaps the tables and recreates the explicit indexes captured beforehand.
- **`Relation#count` ignored `limit` and `offset`** — `Post.all.limit(5).count`
  returned the full table size. The count now wraps a bounded subquery, so a
  limited relation counts exactly the rows `to_a` would return; joins keep
  their distinct-pk collapsing inside the subquery.
- **A bare `offset` crashed every query on SQLite**: `LIMIT -1 OFFSET n` is
  required there (SQLite rejects `OFFSET` without `LIMIT`) — affected both
  `count` and materialized reads on offset-only relations.

## [0.3.3] — 2026-08-24

### Fixed

- **`Altair::Cable.broadcast(channel, message)` recursed into itself until
  the process died**: the two-argument raw-message call also matched the
  three-argument envelope overload (`data : JSON::Any? = nil`), and Crystal
  resolves such ties in favor of the last-defined overload — which then
  called `broadcast(channel, envelope)`, matching itself again. Each level
  re-wrapped and re-escaped the payload, doubling its size, until
  serialization blew up as a confusing `IO::EOFError`. Any two-argument
  broadcast crashed this way, including the WebSocket handler's own
  client-message rebroadcast, so every real-world Cable deployment was
  one POST away from a 500. The overloads are now disjoint (the envelope
  form requires all three arguments), delivery goes through a private
  `deliver`, and new specs cover raw delivery, envelope delivery and the
  zero-subscriber no-op end to end.

### Added

- **Dynamic redirect**: `redirect "/t/:id", to: "/tweets/:id"` now interpolates route params into the Location header and preserves format suffixes.
- **Cache layer**: `Altair::Cache::MemoryStore` with bounded entries, TTL expiry, `fetch` block; accessible as `Altair.cache`.
- **API mode**: `altair new --api` generates a JSON-only project (no views/assets) with CORS enabled.
- **Observability**: `/health` and `/metrics` endpoints (Prometheus format) behind `config.observability = true`.
- **Storage abstraction** — `DiskStore` (local uploads under `public/uploads/`) and `S3Store` (AWS SigV4, path-style and virtual-hosted); both share a common `upload/delete/url` contract.
- **`has_one_attached` macro**: attach/purge files against any persisted model via lazy `altair_attachments` table; PG-compatible placeholders.
- **WebSocket (`Altair::Cable`)**: channel-based broadcaster at `/cable` with automatic subscriber cleanup.
- **Admin generator**: `altair g admin Post` writes a namespaced controller with `require_login` and registers `/admin/posts` routes.
- **Structured logs**: `config.structured_logs = true` emits one JSON object per request (method/path/status/duration/request_id).
- **`Relation#joins` / `left_joins`**: `Post.all.joins(:comments).where("comments.body", "hi")`
  emits a real INNER JOIN with table-qualified `where`/`order` columns. Joins on
  `has_many` automatically enable `SELECT DISTINCT` and `COUNT(DISTINCT pk)` so
  duplicate child matches never inflate results; `left_joins` keeps unmatched
  owners. Unknown associations raise at first use.
- **`has_many :through`**: `has_many :tags, through: :post_tags` works lazily
  (single JOIN query per owner), eagerly (`includes(:tags)` loads all owners in
  one batched JOIN with an extra grouping column), and composes with `joins`.
  The source association is inferred from the association name's singular;
  pass `source:` explicitly when inference is ambiguous (compile-time error
  otherwise).
- **Polymorphic associations**: `belongs_to :commentable, polymorphic: true`
  stores `<name>_id` + `<name>_type` (type stored as the full class name,
  validated at runtime against the model registry); `has_many :comments,
  as: :commentable` filters by owner type and supports `dependent:
  :destroy/:nullify`. Eager loading batches one query per distinct type.
- **`t.references :name, polymorphic: true`** migration helper generates the
  id/type column pair plus composite index; plain `references` adds the FK
  column + index.
- **`Relation#reload`** clears the cached records so the next access re-runs the query.
- **`Model#reload`** re-reads all attributes from the database on a persisted record.
- **`Record.clear_handlers!`** clears instrumentation hooks between test examples.

### Changed

- **`Relation#order` accumulates** instead of overwriting — `order(:a).order(:b)`
  produces `ORDER BY a, b`. Use `reorder` to replace or `unscope_order` to clear.

### Fixed

- **`IN (...)` chunking in preload loaders**: eager loading (`includes`,
  polymorphic batched-per-type, `has_many :through`) now splits oversized id
  lists into consecutive queries at a 500-bind ceiling, so large collections
  no longer trip SQLite's variable limit.
- **Custom primary keys**: `table :posts, primary_key: :uuid` generates typed
  accessors, finders and CRUD against the named column; string PKs
  auto-generate `SecureRandom.uuid` before insert. All SQL paths (update,
  delete, finders, loaders) respect the custom name.

## [0.3.2] — 2026-08-23

### Fixed

- **v0.3.1 regression: jobs worker broke every fresh app**: the
  polymorph half of the jobs design lived only in the `params` macro —
  outside the framework's own suite (which always contains example jobs)
  the base `Altair::Jobs::Job` had no `self.from_payload`, so any project
  with zero job subclasses (every `altair new` then `scaffold` → `migrate`)
  failed to compile with `undefined method 'from_payload' for Job+.class`.
  The base now declares a runtime-guarded default raising a clear
  `Altair::Error`; subclasses override it via the macro, and a regression
  spec calls `Altair::Jobs::Job.from_payload` directly to force the
  `Job.class` dispatch the workers rely on.
- `shard.yml` `version:` raised from 0.3.0 to 0.3.1 in the previous
  release was missed — now corrected to 0.3.2 so
  `Shard "altair" version (...) doesn't match tag version (...)`
  no longer warns on every `shards install`.

## [0.3.1] — 2026-08-23

### Added

- **Pure-Crystal Redis client (`Altair::Redis`)**: built from scratch —
  RESP2 protocol, connection pool with idle timeout, TLS support, AUTH +
  SELECT, auto-reconnect, pipeline (batch in one round trip), transactions
  (MULTI/EXEC/DISCARD/WATCH), pub/sub with dedicated listener fiber.
  Covers strings, hashes, lists, sets, sorted sets and key commands.
- **Cache::RedisStore**: implements the Cache::Store contract on top of
  `Altair::Redis::Client`, so cached values survive process restarts and
  are shared across all application instances.
- **Offline framework installs**: every release now ships the framework
  source as `altair-src-v<version>.tar.gz` / `.zip` assets (shard.yml +
  src/, checksummed alongside the binaries). The installers gain a
  framework switch (`--framework` on sh/cmd, `-Framework` on PowerShell)
  that downloads and unpacks it into `~/.altair/framework/<version>/`,
  giving air-gapped machines a real dependency path via
  `altair new app --framework-path <that directory>`.
- `altair new` now tells the truth about dependencies: its next-steps
  message includes `shards install` and points offline users at
  `--framework-path`, instead of implying the scaffold runs standalone.
- **Background jobs**: `altair g`-style job classes declare their typed
  parameters once with `params user_id : Int64, ...`; the macro generates a
  typed constructor, the JSON payload codec, and an `enqueue` / `enqueue_in`
  / `enqueue_at` trio whose arguments fail to compile when they do not
  match. Jobs persist in a lazily-created `altair_jobs` table (no migration
  required — same pattern as `schema_migrations`), claiming is a conditional
  `UPDATE` so concurrent workers never double-run a row, failures retry
  with exponential backoff (2s doubling, capped at 5 minutes) inside a
  per-job attempt budget, and `altair jobs:work` runs the worker with
  graceful SIGINT/SIGTERM shutdown while `altair jobs:stats` prints status
  counts. Test mode collects enqueues in memory for synchronous draining.
- **Asset pipeline**: `assets/` sources compile into
  `public/assets/<name>-<sha256-digest>.<ext>` via `altair assets:precompile`,
  with a `manifest.json` mapping logical paths to fingerprinted URLs.
  `stylesheet_link_tag`, `javascript_asset_tag` and `asset_url` resolve
  through the manifest when compiled (falling back to plain copies so
  development never requires a build). Fingerprinted responses carry
  `Cache-Control: public, max-age=31536000, immutable`; plain copies stay
  cache-neutral. Recompiles rotate digests and prune stale files of rebuilt
  paths; reruns without changes are byte-identical.
- **Full authentication (`altair g auth`)**: the generator writes a complete
  registration/login stack for a user model — model with
  `validates_uniqueness_of :email`, a `CreateUsers` migration carrying a
  unique email index, sessions and registrations controllers, login/register
  views, and the `/login`, `/register`, `/logout` routes. Passwords hash
  through PBKDF2-HMAC-SHA256 (OpenSSL stdlib — no new dependencies) behind
  the new `password_auth` model macro: staged plain passwords never persist,
  length and confirmation validate as ordinary record errors, and
  `authenticate_password(candidate)` gates logins. `altair g auth [User]`
  accepts an optional model name and is idempotent on rerun.
- **`Altair::Auth::PasswordHasher`**: self-describing digest strings
  (`pbkdf2-sha256$<iterations>$<salt>$<digest>`) so the iteration count can
  rise over time; `verify` treats malformed digests like wrong passwords,
  and `stale?` flags digests to rehash on the next successful login.
- **Stateful test client (`Altair::Test::Client`)**: an HTTP test client that
  keeps the server's cookies in a jar between requests — a sign-in carries
  into every later request without manual header plumbing — with browser-like
  redirect following (`follow_redirects: true`, 301/302/303 downgrade to GET,
  cookies collected along the chain, expired cookies dropped from the jar).
- **Database test helpers**: `Altair::Test.migrate!(App)` applies pending
  migrations through the same engine `db:migrate` drives, and
  `Altair::Test.transactional { }` wraps an example in an always-rolled-back
  transaction (nested calls join the outer transaction through savepoints).
- **`Altair::Test.boot` configure hook**: an optional `configure:` proc runs on
  the fresh application instance before the server is built, where per-spec
  settings such as `secret_key_base` belong.
- **`Connection#in_transaction?`** reports whether the calling fiber currently
  owns a transaction connection, and **`Connection#query_one?`** returns nil
  instead of raising when a query matches no rows.

### Changed

- **`examples/blog` demonstrates the Phase 7 stack end to end**: register and
  sign in (PBKDF2-hashed passwords), post creation gated behind the session,
  styles served through the fingerprinted asset pipeline, and each new post
  enqueueing a `PostPublishedJob` that `scripts/jobs.cr` drains with log
  announcements.

## [0.3.0] — 2026-08-22

### Added

- **Development console redesign**: the boot banner now shows a rich boxed
  summary (environment, address, PID, routes, middleware, Crystal version
  and startup time) and the request log is aligned for scanning (`HH:MM:SS
  METHOD   PATH                  STATUS  TIME`), with colors by method and
  status family, an optional request counter (`#0001`), slow-request
  highlighting past `config.slow_request_threshold` (default 20ms) and
  compact mode (`config.logger_compact`). Errors log a highlighted block
  with route, controller, exception, message and source location. Colors
  auto-detect `NO_COLOR`/`TERM` and `STDOUT.tty?`, or are forced via
  `config.logger_colors`.

- **Website console and testing guides**: dedicated `docs/console` and
  `docs/testing` pages, plus professional SVG icons for every guide and a
  redesigned docs layout with breadcrumbs, a sticky reading-progress bar
  and card-style `Previous`/`Next` pager (`Page X of Y`).

- **Windows installers hardened for real-world Windows**: `install.ps1`
  now forces TLS 1.2 and silences the progress bar that hung `irm`,
  `install.cmd` preserves quotes for `--dir` paths with spaces, and both
  forward `NO_COLOR`/`TERM` correctly. `windows-arm64` is now a supported
  release target.

### Fixed

- **Windows downloads no longer die mid-transfer**: `install.ps1` /
  `install.sh` ride curl's own retries (`--retry 3`, 10-minute ceiling),
  fall back to resumable BITS on Windows, and size-check every download —
  a truncated transfer is reported with the exact byte counts instead of
  surfacing later as a checksum mismatch. `altair update` gets the same
  treatment: a 120-second per-connection timeout (was 30), three attempts
  on connection-level failures and silently-truncated bodies
  (`Content-Length` verified before acceptance), while deterministic
  failures such as a missing asset still abort after one attempt.

### Changed

- **Logger configuration**: `config.logger_timestamps`,
  `config.logger_request_counter`, `config.logger_show_client_ip` and
  `config.slow_request_threshold` join `config.logger` and
  `config.logger_colors` for console tuning.

- **CLI polish from the console wave**: long request paths truncate with a
  leading ellipsis to keep columns aligned, `slow_request_threshold` now
  validates as not-negative, and spec counts are synced to 752 across
  `AGENTS.md`, `CLAUDE.md` and the website.

## [0.2.2] — 2026-08-22

### Added

- **Named scopes**: `scope :published, published: true` — or a block
  receiving the relation (`scope :recent { |query|
  query.order(:created_at).limit(10) }`) — declares a reusable,
  chainable query fragment as a class method. Two scopes compose through
  the new `Relation#merge` (where clauses AND together; a later order,
  limit or offset wins), since Crystal has no dynamic dispatch to chain
  them directly.

- **Nested includes**: `includes(posts: :comments)` applies each further
  level to the rows the previous level loaded, recursing through
  NamedTuple values to any depth (`includes(posts: {comments: :post})`).
  Every level stays one batched query — never one per record. The
  association loaders now return the rows they read and every
  `__preloader_for` signature is uniform, so dispatch goes through a
  record's metaclass.

- **`Altair::Test` helpers for application specs**: `Altair::Test.boot(App)`
  binds on an ephemeral port, waits until it accepts, yields the port and
  restores the shared application instance afterwards, with small
  `get` / `post` / `post_json` / `put` / `patch` / `delete` request
  helpers — the integration-suite boilerplate as public API.

- **`db:seed`**: `altair new` generates `db/seeds.cr`, whose
  `Altair::CLI::Project.seeds { ... }` blocks register at require time
  and run only through the new `bin/altair db:seed` — booting a server
  never plants data. Blocks re-run on every invocation; guarding with
  `unless Model.exists?` keeps repeats idempotent.

- **`Model.insert_all` bulk inserts**: inserts many rows in as few
  multi-row statements as possible. Values bind as parameters through the
  adapter's coercion layer (JSON and decimal included), timestamp columns
  auto-fill once per call like `create`, sets past a per-statement bind
  ceiling chunk inside one transaction so the call stays all-or-nothing,
  and unknown columns or primary-key keys raise before anything is
  written. Validations and callbacks are deliberately bypassed — this is
  the bulk load path.

- **Public dirty tracking**: `changed?`, `changed_attributes` and
  `attribute_changed?` report state since the last load or save;
  `restore_attributes(*names)` — or with no arguments, every changed
  attribute — reverts to that baseline. Originals snapshot wherever dirty
  state cleared before (`from_row`, successful saves), so a restored
  record stays saveable with only its surviving changes.

- **`enum_attribute` for fixed-value columns**:
  `enum_attribute :state, [:pending, :in_review]` declares a nested enum
  whose members are the only values the typed accessor accepts — anything
  else is a compile error. The column stores the member name in
  snake_case so raw rows stay readable; unknown stored values read back
  as `nil` instead of raising on legacy data; and `find_by_<col>` gains a
  member-typed overload while validations keep operating on the string.

- **CLI path-aware `altair new`**: `altair new a/b` and
  `altair new /tmp/app` now derive the application name from the
  basename and create the project at the full path; `--framework-path`
  may appear before or after the name.

- **CLI help and suggestions**: `altair help [command]` shows
  per-command help, `altair new` documents `[--framework-path DIR]`,
  and unknown commands/generators suggest up to three close matches.

### Fixed

- **Deterministic linting**: the `ameba` development dependency now pins an
  exact master commit instead of floating `branch: master`, so a fresh
  `shards install` in CI can no longer pull new rules that break the build.
  Two `Naming/BlockParameterName` findings in the showcase example were
  fixed to satisfy current master.

- **`altair g` without arguments no longer crashes**: it now prints
  the generator help instead of raising `Index out of bounds`.

- **Empty `db/schema.cr` is now typed**: rolling back to zero tables
  writes `META = {} of Symbol => Hash(Symbol, Hash(Symbol, String))`
  instead of an untyped `{}`, fixing a compile error on the next run.

- **Hyphenated application names rejected with a suggestion**:
  `my-app` now aborts with `use ... (e.g. my_app)` instead of a stack
  trace.

- **Project commands outside a project explain how to find it**:
  `server`/`routes`/`db:*` outside a project now report
  `must be run inside an Altair project` instead of `Unknown command`.

### Changed

- **CI guards the showcase**: `examples/showcase` joined the Example builds
  step, and GitHub Releases are now published with auto-generated release
  notes.

## [0.2.1] — 2026-08-07

### Added

- **Website redesign**: the docs site was redesigned to match the logo
  palette (deep navy, slate, red) with a hero, badges, a feature grid, and
  a docs layout with a sticky sidebar, active-state navigation and next/
  previous paging across the guides.

- **New docs pages**: sessions and auth (signed-cookie sessions, flash,
  CSRF protection, login helpers, JWT), configuration (`.env` and
  `config/database.yml`), security (default headers, request ids, CORS)
  and multipart uploads — each with worked code examples. The features
  page now reports 705 specs passing with Phase 6 marked complete.

- **Request id in the request log**: the `Logger` middleware appends the
  request identifier to its per-request line when the `RequestId`
  middleware assigned one, so a log entry and the echoed `X-Request-Id`
  response header correlate across distributed traces.

- **Security middleware set**: the default stack now carries three new
  layers — `Altair::Middleware::SecurityHeaders` stamps `nosniff`,
  `SAMEORIGIN` and a strict referrer policy on every response (driven by
  `config.security_headers`, only filling headers the application did not
  set itself); `Altair::Middleware::RequestId` honors an inbound
  `X-Request-Id` (or `config.request_id_header`) or generates a UUID, and
  exposes it as `request.request_id` while echoing it back on the response
  for traceable logs; `Altair::Middleware::Cors` is a pass-through until
  `config.cors.origins` names the origins an application trusts, then it
  stamps `Access-Control-Allow-*` on permitted requests and answers
  preflight `OPTIONS` directly (methods, headers, credentials, max age)
  without reaching the router.

- **Multipart form parsing**: a `multipart/form-data` request body is parsed
  into the parameter bag on first access. Scalar text fields behave like any
  other form field (`params["title"]`); file parts arrive as
  `Altair::HTTP::UploadedFile` objects carrying the client filename, content
  type and buffered bytes, read through `params.upload("avatar")` (or the
  `params.uploads` hash). Uploads are exposed as `UploadedFile#save(path)`
  and `#content`. A malformed body or missing boundary degrades gracefully.

- **`.env` + `database.yml` configuration**: the framework loads a `.env`
  file from the application root at boot (with an `.env.<environment>`
  overlaid for the active environment), so secrets and per-deploy settings
  never need to live in code. A `config/database.yml` holds per-environment
  database settings — `url`, `pool`, `initial_pool`, `max_idle_pool`,
  `checkout_timeout`, `query_timeout` — parsed by `Altair::Config::Database`
  and merged into `config` from the active environment's section. `altair new`
  ships both files (`database.yml`, `.env.example` + gitignored `.env`) and
  the generated `application.cr` no longer hardcodes a database URL:
  production configuration is a file edit, not a code change.

- **Auth helpers**: controllers get `current_user_id`, `sign_in(user_id)`,
  `sign_out`, and two ready-made `before_action` filters — `require_login`
  (redirects guests to `config.login_path`, default `/login`) and
  `authenticate!` (answers `401 Unauthorized` for JSON/API requests).
- **`Altair::Auth::JWT`**: a self-contained HS256 JSON Web Token
  implementation. `JWT.sign(claims, secret, expires_in:)` issues a token,
  `JWT.verify(token, secret)` returns the claims or `nil` for malformed,
  tampered, wrongly-signed or expired tokens — a stateless authentication
  path for API clients.

- **CSRF protection**: `protect_from_forgery` on a controller verifies that
  every state-changing request (`POST`/`PUT`/`PATCH`/`DELETE`) carries the
  session's authenticity token, either as a hidden `_csrf` form field or an
  `X-CSRF-Token` header, compared in constant time; mismatches answer `422`.
  `form_for` and `button_to` embed the field automatically on protected
  controllers, and the check plays along with the existing callback DSL —
  `skip_before_action :verify_authenticity_token` and `only:`/`except:`
  filters work unchanged.

- **Sessions**: `Altair::Session` exposes a hash-like controller session
  backed by a pluggable `Altair::Session::Store`. The default
  `SignedCookieStore` keeps the session in an HMAC-SHA256 signed cookie
  (`_altair_session`) with `HttpOnly` + `SameSite=Lax` and a `` `/` `` path,
  honoring `config.secret_key_base`, `session_cookie_name`,
  `session_expiry` and `session_cookie_secure`. Read-only requests never
  rewrite the cookie; tampered cookies fall back to an empty session.
  Controllers get `session`, `logged_in?` and `reset_session`.
- **Flash**: `Altair::Session::Flash` carries one-request messages written
  through `flash["key"] = value` and read on the next request;
  `flash.now` writes current-request-only values. Flash rides inside the
  session and is hidden from `session.to_h`.

### Fixed

- **`form_for` and `button_to` in templates with helper actions**: the
  template transpiler split `form_for(...)` args on the first `(`; a helper
  action such as `form_for(post_path(post.id), ...)` (nested parens) was
  silently truncated into a parse error, and the block form (`form_for
  ... do |f|`) called a macro `split` overload that never compiled. Both
  branches now rebuild the argument span from the split parts, so helper
  actions and block forms transpile correctly.

- **`altair update` follows redirects**: release assets are served behind an
  HTTP redirect, which `HTTP::Client` no longer follows automatically on
  modern Crystal. `Update.download` now follows a bounded redirect chain
  (up to 5 hops) and applies request timeouts, so `--check`/`--force` work
  against GitHub's asset host again. Specs cover a real 302 redirect and an
  infinite redirect loop.

## [0.2.0] — 2026-08-06

### Added

- **Route-lookup LRU cache**: `Altair::Routing::Router` now memoizes
  successful matches by `"METHOD path"`, so a repeated request path collapses
  to a hash lookup instead of re-walking the route table and re-extracting
  parameters. Sized by the new `config.router_cache_size` (default 1024; `0`
  disables it). Misses (404/405) are never cached, so an error burst cannot
  evict hot entries. Shared match params are documented read-only.
  Measured ~10x on hot paths with zero per-request routing allocations.
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

- **Record hot path builds each SQL statement once per connection**
  (`Altair::Record::Model` + `Altair::Record::Connection#sql_template`):
  `find`, `find_by_*` and `insert` cached their quoted/placeholder-laden
  statements instead of rebuilding them per call, cutting the write-path
  allocations by half (frozen-GC harness, PostgreSQL: `Item.create`
  2,033 → 964 B/op, `Item.find` 1,378 → 1,060 B/op). Same-session A/B at
  1,000 VU / 60 s: write max −27%, read p99.9 −51%; the remaining tail is
  still the per-second Boehm stop-the-world pause.
- **Benchmark measurement excludes the cold-start ramp** (`examples/benchmark_k6`):
  each write/read phase now runs a discarded k6 warm-up (ramp to 1,000 VUs +
  settle) before the measured `constant-vus` run, so the committed summaries
  describe sustained load only. Instrumentation showed the previous ~900 ms
  write max was a first-second cold-start spike (pool + prepared statements +
  GC heap storm under the ramp), not a sustained-load defect; the sustained
  tail that remains is one Boehm stop-the-world pause per second on the
  plateaued heap. Altair write max dropped 873.1 → 429.6 ms under the same
  load. Diagnosis tooling: `scripts/sample_pg.sh`, `scripts/diagnose.sh` and
  the flag-gated sampler in `app/altair/src/bench_sample.cr` (compiled only
  with `--define bench_sample`, zero effect on the normal binary).
- **Request parameters are parsed lazily**: `Altair::HTTP::Request` defers
  the query string, the JSON body and the unified `params` bag (with its
  form-param walk) to first access, memoizing each. Constructing a request
  still reads the body (the 413 size check stays at construction), so a
  request whose handler never reads parameters parses nothing. Measured on a
  bare GET: allocations 784→368 B/op, ~3.7x faster.
- **The `_method` override is honoured for `POST` submissions only**: GET and
  the other methods route directly, without touching the query string, so a
  `GET ?_method=` no longer re-routes the request as another verb. The
  override is a form (POST) behaviour, and this closes the door on
  GET-query method smuggling. Route parameters are registered through the
  request and merge into the bag when it is built.
- **Route resolution is a single scan**: `Altair::Routing::Router#resolve`
  answers both "which route matches" and "which methods are allowed" in one
  pass, so a 405 no longer triggers a second candidate walk. `#find` remains
  as a thin wrapper; `dispatch` now uses `resolve`. Candidate selection
  merged the per-group ascending index lists on the fly instead of building
  an array and sorting it, roughly halving allocations on uncached scans.
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
