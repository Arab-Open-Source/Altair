# Changelog

All notable changes to Altair will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Phase 1 — Router**: a Rails-style routing layer built with compile-time
  macros.
  - `routes do ... end` DSL with `get` / `post` / `put` / `patch` / `delete`,
    `root`, `namespace` and `resources`, plus `to:` actions, inline handler
    blocks and `named:` routes.
  - `resources :posts` expands to the seven RESTful routes (Rails order)
    with `only:` / `except:` filters and generated helpers
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
