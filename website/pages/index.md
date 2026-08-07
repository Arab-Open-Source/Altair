<div class="hero">
  <img class="logo" src="{{root}}assets/img/logo.png" alt="Altair logo">
  <h1>Altair</h1>
  <p class="tagline">Batteries-included web framework for Crystal. The full
  stack — routing, controllers, views, an ORM, generators and a CLI — with
  sane defaults.</p>
  <div class="badges">
    <span class="badge">Crystal</span>
    <span class="badge"><b>705</b> specs passing</span>
    <span class="badge">SQLite + PostgreSQL</span>
    <span class="badge">Linux &middot; macOS &middot; Windows</span>
  </div>
  <div class="button-row">
    <a class="btn btn-primary" href="/docs/install.html">Get started</a>
    <a class="btn btn-secondary" href="/docs/routing.html">Read the guides</a>
    <a class="btn btn-secondary" href="https://github.com/Arab-Open-Source/Altair" rel="noopener">GitHub</a>
  </div>
  <div class="copy-box">
    <code>curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.sh | sh</code>
  </div>
</div>

<div class="content-narrow">

## What Altair is

Altair is a batteries-included web framework for Crystal. It ships the full stack — routing, controllers, views, an ORM, generators and a CLI — with sane defaults, so building a web app feels like the framework is working *for* you.

```sh
altair new blog
cd blog
shards install
altair server
```

Open <http://localhost:3000>. Inside a generated project the CLI finds the
project automatically — `altair server`, `altair routes` and
`altair db:migrate` work from any subdirectory, no `bin/` prefix needed.

## What ships today

<div class="feature-grid">
  <div class="feature">
    <h3>Routing</h3>
    <p>Segment-based router with resources, nested routes, constraints and glob segments.</p>
  </div>
  <div class="feature">
    <h3>Controllers</h3>
    <p>Actions, typed parameters, filters, callbacks and rendering hooks on a type-checked base class.</p>
  </div>
  <div class="feature">
    <h3>Views</h3>
    <p>ECR templates with auto-escaping, layouts, partials, helpers and a form builder.</p>
  </div>
  <div class="feature">
    <h3>Record (ORM)</h3>
    <p>SQLite3 and PostgreSQL adapters, migrations, validations, callbacks and associations.</p>
  </div>
  <div class="feature">
    <h3>Sessions and auth</h3>
    <p>Signed-cookie sessions, flash messages, CSRF protection and login helpers.</p>
  </div>
  <div class="feature">
    <h3>Security</h3>
    <p>Safe-by-default headers, request ids and opt-in CORS in the middleware stack.</p>
  </div>
  <div class="feature">
    <h3>Configuration</h3>
    <p><code>.env</code> and <code>config/database.yml</code> merged into typed per-environment config at boot.</p>
  </div>
  <div class="feature">
    <h3>CLI + Generators</h3>
    <p><code>altair new</code>, <code>altair g scaffold</code>, <code>server</code>, <code>routes</code> and database commands.</p>
  </div>
  <div class="feature">
    <h3>Install</h3>
    <p>One-command installers for Linux, macOS and Windows with checksum verification.</p>
  </div>
</div>

## Installation

Install the prebuilt binary on Linux, macOS or Windows:

```sh
curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.sh | sh
```

Windows PowerShell:

```powershell
iex (irm https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.ps1)
```

Windows command prompt:

```cmd
curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.cmd | cmd
```

## Documentation

- [Install](/docs/install.html) — download and set up Altair on your platform.
- [Usage](/docs/usage.html) — create a project, generate a scaffold and run the server.
- [Guides](/docs/routing.html) — routing, controllers, views, the Record ORM, sessions, configuration, security and uploads.
- [What is implemented](/docs/features.html) — the current state of the framework, phase by phase.
- [CLI reference](/docs/cli.html) — every command and generator.
- [Benchmarks](/docs/benchmarks.html) — Altair vs Express and Fiber under real HTTP load.

</div>
