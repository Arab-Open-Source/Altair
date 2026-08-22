# What is implemented

Altair is built in phases, each ending with something working and visible. Everything below is implemented, tested and shipped. Each area has a guide: [Routing](/docs/routing.html), [Controllers](/docs/controllers.html), [Views](/docs/views.html), [Record](/docs/record.html), [Sessions and auth](/docs/sessions.html), [Configuration](/docs/configuration.html), [Security](/docs/security.html) and [Uploads](/docs/uploads.html).

## Phase 0 — Foundation

The core request/response loop: `Altair::Application`, request handling, error pages and configuration.

## Phase 1 — Router

- Segment-based routing (not regex)
- `resources` blocks with `member`, `collection` and nested resources
- Constraints and implicit format suffix
- `redirect`, glob segments and singular `resource`

## Phase 2 — Controllers

A type-checked controller base with actions, parameters and rendering hooks. A wrong method on a dispatch is a compile error, not a runtime 500. The controller layer gained a hardening wave:

- `render json:` serializes any JSON-able object, `redirect_back` with open-redirect protection
- `request.format` (path suffix, then `Accept`, then `:html`) and JSON request bodies merged into `params`
- `head` answers bodyless; `no_content` for a bare 204
- `respond_to` — one action, several format handlers, undeclared formats answer 406
- `before_action` / `after_action` with `only:` / `except:`, `skip_before_action` / `skip_after_action`, inheritance across the hierarchy
- `rescue_from` maps exceptions to handler responses (inherited, `only:`-filtered, subclass-aware)
- `stream` opens chunked bodies for large responses and server-sent events
- A segment-based route index buckets routes by their first segment so matching only tests viable candidates

## Phase 3 — Views

- ECR templates
- Auto-escaping by default — XSS-safe out of the box
- Layouts with `yield`, partials (`render "form"`)
- Helpers: `link_to`, `content_tag`, a basic form builder, and an htmx layer

## Phase 4 — Record (ORM)

Three vertical waves:

- **Wave 1:** adapter interface + SQLite3, connection pool, migrations DSL + runner, auto-regenerated `db/schema.cr`
- **Wave 2:** CRUD + finders (`find_by_*`), validations (`valid?` + errors), timestamps and callbacks
- **Wave 3:** associations (`belongs_to`, `has_many`, `has_one`) with batched eager loading via `Relation#includes`, and `dependent:` handling

## Phase 5 — CLI + Generators

- `altair new` generates a standard project layout
- `altair g model|migration|controller|scaffold` generates ready-to-edit files
- App commands (`server`, `routes`, `db:migrate` / `db:rollback`) run from anywhere inside a project — no `bin/` prefix needed
- `altair install` copies a built binary onto your `PATH`, prints its SHA-256 digest, and refuses to clobber unrelated files without `--force`
- `altair update` checks GitHub for a newer release, verifies the checksum and swaps the binary atomically
- Prebuilt binaries for Linux, macOS and Windows (amd64 + arm64) published with checksums; verified one-command installers

## Phase 6 — Hardening

Sessions, authentication, file-driven configuration, multipart uploads and a
security middleware set, shipped in waves:

- **Sessions + flash + CSRF** — signed-cookie sessions with a `session`
  hash view, one-request `flash` messages, `protect_from_forgery` with
  constant-time token verification, and login helpers (`sign_in`,
  `sign_out`, `require_login`, `authenticate!`, `current_user_id`)
- **JWT auth** — `Altair::Auth::JWT`, a minimal HS256 implementation for
  stateless API auth
- **Configuration** — `.env` (real env vars win; `.env.<environment>`
  overrides `.env`) and `config/database.yml` per-environment settings,
  merged into `config` at boot by `Altair::Config::DotEnv` /
  `Altair::Config::Database`; `altair new` generates both files
- **Multipart uploads** — `multipart/form-data` bodies parse into the
  parameter bag (scalar fields as params, files as
  `Altair::HTTP::UploadedFile` via `params.upload("avatar")`, with
  `UploadedFile#save` + `#content`)
- **Security middleware set** — `SecurityHeaders` (default `nosniff` /
  `SAMEORIGIN` / referrer policy, driven by `config.security_headers`),
  `RequestId` (`request.request_id`, echo-back through
  `config.request_id_header`, appended to the request log line), and
  opt-in `Cors` (`config.cors.origins` enables it; preflight answered
  directly)

## Performance hardening

- `find_each` streams bounded batches that keep the scoped `where` filters and `includes` preloaders
- `Relation#count` / `size` run `COUNT(*)` without materializing rows
- The server resizes the execution context to the available workers on boot (honors `CRYSTAL_WORKERS`; `config.parallel_execution` opt-out)
- Warm connection-pool defaults: `initial 2 / idle 2 / max 10`
- A development-mode N+1 detector warns on identical SQL fired more than `config.n_plus_one_threshold` times in one request
- A database admission-control gate (`config.db_max_active_queries`, off by default) parks excess request fibers on a FIFO semaphore outside the pool, bounding tail latency under saturation
- The record hot path builds each SQL statement once per connection
  (`Connection#sql_template`): `find`, `find_by_*` and `insert` cache their
  quoted statements, halving the write-path allocations (PostgreSQL:
  `Item.create` 2,033 → 964 B/op on the frozen-GC harness) — see
  [Benchmarks](/docs/benchmarks.html) for the end-to-end effect

## Testing and quality

- 746 specs passing (6 pending: the PostgreSQL concurrency contract tests; the full PostgreSQL contract suite runs when `ALTAIR_TEST_PG_URL` is set)
- Formatter clean, linter silent on framework sources
- Smart error pages: 404 with route suggestions, 405 with `_method` explanation, detailed 500 diagnostics in debug mode only

## What is planned next

- **Phase 7 (Post-release):** background jobs, full authentication, asset pipeline, rich query DSL, testing utilities
