# CLAUDE.md — working with Altair

Altair is a batteries-included web framework for Crystal. This file is a
pointer; the authoritative, detailed guide is **`AGENTS.md`** — read it
before touching the codebase.

## The short version

- **Status:** Phases 0–6 done (Foundation, Router, Controllers, Views, ORM,
  CLI, Hardening). **Phase 7 (post-release)** is next. 752 specs passing.
- **Contract:** specs from day one, never skip a phase's exit criterion,
  never mention "Rails" in the repo, no emojis, no obvious comments.
- **Plan:** `ROADMAP.md` holds the phase table + exit criteria; detailed
  plans in `docs/architecture/`.

## Commands

```bash
crystal spec                              # full test suite
crystal tool format --check src spec examples
crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent
shards install                            # fetch dev deps (ameba)
```

Acceptance bar: formatter clean, Ameba silent, specs green, CHANGELOG
`[Unreleased]` updated for user-facing changes.

## Architectural rules

1. Compile-time safety first — route helpers are generated, type-checked
   methods; wrong dispatches fail at compile time.
2. Segment-based routing, not regex.
3. Middleware uses factories (`Proc(Application, Middleware)`); instantiating
   the base class widens the pipeline type to every subclass.
4. One `Altair::Application` subclass per project (`SpecApp` in specs).
5. Error pages are debug-mode only; production gets a plain message.
6. Escape everything rendered by default; never echo sensitive headers.

## Code layout

`src/altair.cr` requires components **in dependency order** — register new
files there or they never load. `core/ http/ routing/ controller/
middleware/ config/ session/ auth/ view/ record/ cli/ server/ support/
exceptions/ concurrency/` under `src/altair/`. `spec/` mirrors it.
`examples/hello_world/` is the runnable demo; `examples/blog` is the
persistence demo.

## Costly gotchas

- `NamedTuple#select` does not exist — use `to_a.select(...)`.
- `Exception#cause=` is not public API — chain in the constructor.
- `Log::IOBackend` needs `require "log/io_backend"`; sync specs need
  `dispatcher: Log::DispatchMode::Sync`.
- Prefer `Time.instant` over `Time.monotonic`.
- `MIME.from_extension?` takes the leading dot.
- `HEAD` matches `GET` routes; body dropped. `_method` override lets forms
  send PUT/PATCH/DELETE; error hints respect it and report `HEAD` as `GET`.
- `yield` + `ensure` widens return types to `| Nil` — use `.as(...)`.
- Never auto-format after a build; formatting is a check.
- `pkill` is unreliable here — kill dev servers by PID.
- Register new files in `src/altair.cr` in dependency order.

All the detail — phase-by-phase work, code style, testing patterns,
contributor workflow — is in `AGENTS.md` and `CONTRIBUTING.md`.
