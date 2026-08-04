# What is implemented

Altair is built in phases, each ending with something working and visible. Everything below is implemented, tested and shipped.

## Phase 0 — Foundation

The core request/response loop: `Altair::Application`, request handling, error pages and configuration.

## Phase 1 — Router

- Segment-based routing (not regex)
- `resources` blocks with `member`, `collection` and nested resources
- Constraints and implicit format suffix
- `redirect`, glob segments and singular `resource`

## Phase 2 — Controllers

A type-checked controller base with actions, parameters and rendering hooks. A wrong method on a dispatch is a compile error, not a runtime 500.

## Phase 3 — Views

- ECR templates
- Auto-escaping by default — XSS-safe out of the box
- Layouts with `yield`, partials (`render "form"`)
- Helpers: `link_to`, `content_tag`, a basic form builder

## Phase 4 — Record (ORM)

Three vertical waves:

- **Wave 1:** adapter interface + SQLite3, connection pool, migrations DSL + runner, auto-regenerated `db/schema.cr`
- **Wave 2:** CRUD + finders (`find_by_*`), validations (`valid?` + errors), timestamps and callbacks
- **Wave 3:** associations (`belongs_to`, `has_many`, `has_one`) with batched eager loading via `Relation#includes`, and `dependent:` handling

## Phase 5 — CLI + Generators

- `altair new` generates a standard project layout
- `altair g model|migration|controller|scaffold` generates ready-to-edit files
- `bin/altair` runs `server`, `routes`, `db:migrate` / `db:rollback` inside a project
- `altair install` copies a built binary onto your `PATH`, prints its SHA-256 digest, and refuses to clobber unrelated files without `--force`
- Prebuilt binaries for Linux, macOS and Windows (amd64 + arm64) published with checksums; verified one-command installers

## Testing and quality

- 481 specs passing (6 pending: the PostgreSQL contract suite, gated on `ALTAIR_TEST_PG_URL`)
- Formatter clean, linter silent on framework sources
- Smart error pages: 404 with route suggestions, 405 with `_method` explanation, detailed 500 diagnostics in debug mode only

## What is planned next

- **Phase 6 (Hardening):** sessions + flash + CSRF, `database.yml` / `.env` config, real project quality
- **Phase 7 (Post-release):** background jobs, full authentication, asset pipeline, rich query DSL, testing utilities
