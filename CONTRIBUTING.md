# Contributing to Altair

First of all: thank you for considering a contribution. Altair is built by
people who care about the details, and every issue, pull request and review
moves the framework forward.

This guide explains how to contribute: reporting bugs, requesting features,
writing code and opening pull requests. Please read it before opening an
issue or a pull request.

---

## Table of contents

- [Getting started](#getting-started)
- [Finding your way around](#finding-your-way-around)
- [Reporting bugs](#reporting-bugs)
- [Requesting features](#requesting-features)
- [Working on an issue](#working-on-an-issue)
- [Branch naming](#branch-naming)
- [Commit messages](#commit-messages)
- [Code style](#code-style)
- [Testing](#testing)
- [Opening a pull request](#opening-a-pull-request)
- [Code of conduct](#code-of-conduct)

---

## Getting started

Requirements:

- [Crystal](https://crystal-lang.org) `>= 1.21.0`
- [Git](https://git-scm.com)

Clone the repository and install the development dependencies (Ameba, the
linter used by the CI pipeline):

```bash
git clone https://github.com/Arab-Open-Source/Altair.git
cd Altair
shards install
```

Run the full test suite to make sure your environment is healthy:

```bash
crystal spec
```

You should see every example passing.

## Finding your way around

The architecture is described in [ARCHITECTURE.md](ARCHITECTURE.md), and the
project status and upcoming work live in [ROADMAP.md](ROADMAP.md). Phase-by-phase
implementation plans are kept in [docs/architecture](docs/architecture).

The source lives under `src/altair/`:

| Directory | Contains |
|---|---|
| `src/altair/core/` | Application core and request handling |
| `src/altair/http/` | Request, response and params wrappers |
| `src/altair/routing/` | Routing engine and the route DSL |
| `src/altair/config/` | Configuration system and environments |
| `src/altair/support/` | Utility helpers such as the inflector |
| `src/altair/exceptions/` | The exception hierarchy |

Specs live in `spec/`, mirroring the same structure. The example application
in `examples/hello_world/` is the always-running demo.

## Reporting bugs

Open a bug report with the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md).
A good report includes:

1. A short, descriptive title.
2. Steps to reproduce — code, command, and the exact request if it is an
   HTTP behavior.
3. The expected behavior and the actual behavior.
4. The Crystal version (`crystal --version`) and the platform you are on.

If you already know the cause, do not open an issue — open a pull request
with the fix and describe the problem in its description.

## Requesting features

Open a feature request with the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md).
Describe the problem you are trying to solve, not just the solution you have
in mind. A well-scoped proposal with a motivating example gets the
conversation going much faster.

Check the [roadmap](ROADMAP.md) first: large planned work already has a
phase. Aligning a request with an existing phase increases the chance it
gets picked up.

## Working on an issue

1. Find an issue you would like to work on, or open one describing the
   change you plan to make. Bigger changes almost always deserve a short
   issue first, so the maintainers can give early feedback.
2. Create a branch off `main` (see [Branch naming](#branch-naming)).
3. Make your changes, following the [code style](#code-style) and keeping
   the [tests](#testing) green.
4. Open a pull request and fill in the
   [pull request template](.github/PULL_REQUEST_TEMPLATE.md).

## Branch naming

Every pull request is made from a dedicated branch, never directly from
`main`. **Name the branch after the update it delivers or the issue it
resolves**, so the intent is readable at a glance:

- **Fixes an issue** — reference the issue number and a short slug:

  ```
  issue-42-fix-405-header
  issue-17-add-sessions
  ```

- **No issue (small or self-contained change)** — use a type prefix and a
  short slug:

  ```
  feat-named-routes
  fix-route-param-decoding
  refactor-segment-parsing
  docs-contributing-guide
  chore-update-dependencies
  ```

Types follow the [Conventional Commits](https://www.conventionalcommits.org)
vocabulary: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.

Short slugs are lowercase with hyphens. When an issue exists, prefer the
`issue-<number>-<slug>` form so the pull request links back to the issue
automatically when you mention it.

## Commit messages

Altair follows [Conventional Commits](https://www.conventionalcommits.org):

```
<type>: <short summary>
```

- `feat:` a new feature or behavior
- `fix:` a bug fix
- `refactor:` internal change with no behavior change
- `docs:` documentation only
- `test:` adding or updating tests
- `chore:` maintenance, dependencies, tooling

Write the summary in the imperative mood, lowercase, under 72 characters.
Use the body for the "why" — context, trade-offs and consequences — and list
the affected areas. A good example:

```
feat: add path helpers for named routes

Generate compile-time helpers like post_path(5) on the application
subclass, type-checked like any other method. Helpers interpolate
static segments and parameters in declaration order.
```

If the commit resolves an issue, reference it in the body with
`Fixes #42`.

## Code style

- Match the surrounding style of the file you are editing.
- Follow Crystal's official style; the authoritative check is the formatter:

  ```bash
  crystal tool format --check src spec examples
  ```

- Keep public API documented with a short comment above each public method
  and class, as the existing code does.
- Run Ameba (the linter used in CI) and keep it silent:

  ```bash
  crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent
  ```

## Testing

Altair ships with a healthy spec suite and CI runs it on every pull
request. Every change should keep the suite green:

```bash
crystal spec
```

When you add behavior, add specs for it. When you fix a bug, add a spec
that reproduces it before fixing, then watch it pass. Look at the existing
specs in `spec/` — especially `spec/routing/` for the routing layer — for
the established patterns.

## Opening a pull request

1. Make sure your branch is up to date with `main`.
2. Push your branch and open a pull request against `main`.
3. Fill in the [pull request template](.github/PULL_REQUEST_TEMPLATE.md).
4. A maintainer will review; expect questions and feedback. This is normal
   and welcome — pull requests are a conversation.
5. Update the branch with `main` as needed, and address review comments in
   follow-up commits.

Before opening the pull request, double-check that:

- The branch is named after the change or its issue (see
  [Branch naming](#branch-naming)).
- `crystal tool format --check src spec examples` passes.
- Ameba is silent.
- `crystal spec` passes, including any new specs.
- The [CHANGELOG.md](CHANGELOG.md) `[Unreleased]` section documents
  user-facing changes.

## Code of conduct

Be respectful, constructive and inclusive. Harassment and offensive behavior
of any kind are not tolerated. We are all here to build something good
together.
