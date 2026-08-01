# Changelog

All notable changes to Altair will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
