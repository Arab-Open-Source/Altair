---
name: altair
description: Altair codebase guide. Use whenever working in the Altair repository — implementing a phase, fixing a bug, writing specs, or answering questions about the project's plan, phases, architecture, coding conventions, or testing workflow. Loads the project's context (roadmap phases, exit criteria, code layout, non-negotiables, testing commands) so changes fit the framework instead of fighting it.
---

# Altair — batteries-included web framework for Crystal

Context loaded from `AGENTS.md` (the authoritative, detailed source). This
summary is the quick orientation; read `AGENTS.md` before deep work.

## Non-negotiables

- Never mention "Rails" in code, comments, docs, or commits.
- Specs from day one; every phase ends with its specs passing.
- Never skip a phase's exit criterion — vertical slices, not scaffolding.
- No emojis. No obvious comments; short doc comments on public APIs only.
- Formatter clean, Ameba silent, `crystal spec` green on every change.

## Where the project stands

Phases 0–2 done (Foundation, Router, Controllers). **Phase 3 (Views) is
next.** Smart error pages (404 route suggestions, 405 `_method` hints,
500 diagnostics) already shipped. 155 specs passing.

| Phase | Focus | Status |
|---|---|---|
| 0–2 | Foundation / Router / Controllers | Completed |
| 3 | Views (escaping, layouts, partials, helpers) | **Next** |
| 4 | CLI (`new` / `server` / `routes`) | Planned |
| 5 | ORM `Altair::Record` (migrations, CRUD, validations, associations) | Planned |
| 6 | Generators (`g scaffold Post ...`) | Planned |
| 7 | Hardening (sessions, CSRF, env config) | Planned |
| 8 | Post-release (jobs, auth, assets, rich queries) | Planned |

Exit criteria per phase and golden rules are in `ROADMAP.md`.

## Code layout

`src/altair.cr` requires every component **in dependency order** — new
files must be registered there or they silently never load.

```
core/        Application, request handling, error pages
http/        Request, Response, Params
routing/     Router, DSL, Route, RouteSet, Segment (segment-based, no regex)
controller/  Controller base
middleware/  Base, Logger, Static (factory procs, not class instantiation)
config/      Config, Env, environments/
support/     Inflector, utilities
exceptions/  Exception hierarchy
server/      HTTP server wiring
```

`spec/` mirrors `src/altair/`; `examples/hello_world/` is the runnable demo.

## Architecture principles

1. Compile-time safety first — route helpers like `post_path(5)` are
   generated, type-checked methods; a wrong dispatch is a compile error.
2. Segment-based routing, not regex.
3. Middleware uses factories (`Proc(Application, Middleware)`) — calling
   `.new` on the base class widens the pipeline type to every subclass.
4. One `Altair::Application` subclass per project (`SpecApp` in specs).
5. Error pages are debug-mode only; production gets a plain message.
6. Escape everything rendered by default; never echo sensitive headers.

## Testing

```bash
crystal spec                              # full suite (currently 155)
crystal tool format --check src spec examples
crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent
```

- `spec/spec_helper.cr` pins `Altair.env = Altair::Env::Test`, defines
  `SpecApp` and the compile-time `StubController` hierarchy (DSL specs only
  register routes; controller specs exercise real dispatch).
- Integration specs bind an ephemeral port and wait until ready; reset the
  shared app instance in an `ensure` block.
- Bug fixes: write the reproducing spec first, watch it fail, then fix.

## Gotchas that cost real time

- `NamedTuple#select` does not exist — go through `to_a.select(...)`.
- `Exception#cause=` is not public API — chain in the constructor.
- `Log::IOBackend` needs `require "log/io_backend"`; sync specs need
  `dispatcher: Log::DispatchMode::Sync` (async races assertions).
- Prefer `Time.instant` over `Time.monotonic`.
- `MIME.from_extension?` takes the leading dot (`.css`).
- `HEAD` matches `GET` routes; the body is dropped automatically.
- `_method` override lets HTML forms send PUT/PATCH/DELETE; error hints
  must respect it and report `HEAD` as `GET`.
- `yield` + `ensure` widens return types to `| Nil` — use `.as(...)`.
- Welcome page renders when there are no routes and the path is `/`.
- Never auto-format after a build; the workflow treats formatting as a check.
- `pkill` is unreliable here — kill dev servers by PID.
- Register new files in `src/altair.cr` in dependency order.

## Delivering changes

Branches: `feat-<slug>`, `issue-<n>-<slug>`, `fix-<slug>`. Conventional
Commits (`feat:`/`fix:`/`refactor:`/`docs:`/`test:`/`chore:`), imperative,
under 72 chars. Update `CHANGELOG.md` `[Unreleased]` for user-facing work.
Full guidance in `CONTRIBUTING.md`.
