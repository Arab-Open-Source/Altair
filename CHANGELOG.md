# Changelog

All notable changes to Altair will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
