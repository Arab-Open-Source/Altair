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

> **Status:** early development (pre-alpha)

---

## Features

### Implemented

- **Application core** — a conventional application subclass with typed
  configuration, per-environment settings and a singleton application
  instance.
- **HTTP layer** — framework-owned request and response wrappers, a unified
  parameter bag (route, query and body precedence), and JSON, HTML and
  redirect helpers.
- **Routing** — a compile-time route DSL with `get`, `post`, `put`, `patch`,
  `delete`, `root`, `namespace` and `resources`; path parameters; named path
  helpers generated as real methods; and 404/405 responses served by the
  router.
- **Example application** — `examples/hello_world`, a working demo with a
  RESTful resource and verified behavior over real HTTP.

### Planned

- Controller base class with rendering and redirect helpers
- Middleware pipeline (logging, static files)
- Template rendering with layouts and partials
- Command-line generators
- Database migrations
- Authentication
- Background jobs
- Asset management
- Testing utilities

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

  routes do
    root to: "pages#index"
    get "/hello/:name", to: "pages#hello", named: :greeting
    resources :posts
  end
end
```

The `resources :posts` line alone expands to seven RESTful routes and
generates their path helpers (`posts_path`, `post_path(5)`,
`edit_post_path(5)`). Because routes are compile-time, a typo in a controller
reference fails at compile time, and the generated helpers are type-checked
like any other method.

See [examples/hello_world/README.md](examples/hello_world/README.md) for a
full walkthrough with curl and HTTP client examples.

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
