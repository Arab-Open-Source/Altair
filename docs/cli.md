# CLI reference

The `altair` command is the framework's tool. It scaffolds projects and
files, runs a generated app, and installs itself onto your `PATH`.

## Installing `altair`

### From a GitHub release (recommended for new users)

The official installer downloads the prebuilt binary for your platform,
verifies its SHA-256 digest against the published `SHA256SUMS`, and installs
it onto your `PATH` — no Crystal toolchain required.

**Linux / macOS:**

```bash
curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.sh | sh
```

**Windows (PowerShell):**

```powershell
iex (irm https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.ps1)
```

**Windows (cmd):**

```cmd
curl -fsSL https://github.com/Arab-Open-Source/Altair/releases/latest/download/install.cmd | cmd
```

It is fail-safe: nothing is written unless the checksum matches, an existing
different binary is never overwritten without `--force` (or `-Force` on
Windows), and it is idempotent over an identical install. Options:
`--dir DIR` / `-Dir`, `--force` / `-Force`, `--version VER` / `-Version`.
The installers live in `scripts/` as `install.sh` (POSIX),
`install.ps1` (PowerShell) and `install.cmd` (cmd wrapper).

### From a source checkout

The framework builds a standalone binary from `src/altair_cli.cr`:

```bash
shards build altair
./bin/altair install
```

`altair install` copies the running binary into a user-owned bin directory
on `PATH`, so the command is available directly from any shell:

| Platform | Default target |
|----------|----------------|
| Unix (Linux, macOS) | `~/.local/bin/altair` |
| Windows | `%USERPROFILE%\.altair\bin\altair.exe` |

It prints the installed binary's SHA-256 digest so you can verify the copy
matches its source. The install is deliberately cautious:

- **Idempotent** — a target that already matches the source is a no-op.
- **Refuses to clobber** — an existing, different file at the target aborts
  unless you pass `--force`.
- **`--dir DIR`** installs somewhere explicit instead of the default.
- **`ALTAIR_BIN`** sets the default install directory via the environment.

## Commands

| Command | Purpose |
|---------|---------|
| `altair new <name> [--framework-path DIR] [-d sqlite\|postgresql] [--api] [--with-examples]` | Scaffold a runnable project. By default it depends on the published shard; pass `--framework-path` (or set `ALTAIR_PATH`) to use a local checkout. `-d postgresql` wires the `pg` shard, PostgreSQL URLs and the adapter require; `--api` omits views/assets and enables CORS; `--with-examples` copies curated starters into `examples/altair/`. Every mode generates `Dockerfile`, `.dockerignore` and `compose.yml`. |
| `altair g scaffold <Name> [column:type ...]` | Model + migration + RESTful controller + ECR views + `resources` route + seeded `db/schema.cr`. |
| `altair g model <Name> [column:type ...]` | A model file and its table. |
| `altair g migration Create<Table> [column:type ...]` | A timestamped migration. |
| `altair g controller <Name>` | A controller and its views. |
| `altair docs [topic ...] [--list] [--open] [--refresh]` | List or print curated guides offline; extra words narrow to a heading; `--open` opens the published page; `--refresh` updates `.altair/cache/` and `.altair/bundle.yml` inside a project. |
| `altair examples [name ...] [--copy[=name]]` | List or read curated starter examples offline; `--copy` / `--copy=all` copies into `examples/altair/` inside a project. |
| `altair install [--dir DIR] [--force]` | Install the binary onto `PATH`. |
| `altair update [--check] [--force]` | Update to the latest release. |
| `altair version` | Print `Altair <version>`. |
| `altair help` | Print usage. |

Column specs take a type after a colon and default to `string`:
`title:string body:text price:float published:boolean`.

## Inside a generated project

App-context commands run against the project's application. From anywhere
inside the project directory you can call them directly — the CLI finds the
nearest project and forwards the command to its launcher, so you never need
to type `bin/`:

| Command | Purpose |
|---------|---------|
| `altair server` | Run the app. |
| `altair routes` | Print the compiled route table. |
| `altair db:migrate` | Run pending migrations. |
| `altair db:rollback` | Undo the latest migration. |
| `altair db:create` | Create every environment database from `config/database.yml`. |
| `altair db:drop` | Drop those databases (refuses in production without `--force`). |
| `altair db:seed` | Run the blocks registered in `db/seeds.cr`. |
| `altair assets:precompile` | Fingerprint `assets/` into `public/assets/` and write the manifest. |
| `altair jobs:work` | Run the background-jobs worker until interrupted. |
| `altair jobs:stats` | Print background-job status counts. |

`altair g scaffold ...` and the other generators write into the current
project the same way. The project launcher itself (`bin/altair`, or
`bin/altair.cr` in projects created before the executable wrapper) is
still there and accepts the same commands — both work.

When running the launcher with `crystal run` instead of the built binary,
use `--` before the argument so `crystal run` does not consume it:

```bash
crystal run bin/altair.cr -- db:migrate
```

## Generated deployment files

`altair new` writes a multi-stage `Dockerfile`, `.dockerignore` and
`compose.yml` for SQLite, PostgreSQL and `--api` projects. The image uses
Crystal 1.22.3 with a static binary, runs as non-root `app`, precompiles
assets and health-checks `/health`. Migrations are explicit:

```bash
docker compose build
docker compose run --rm web ./bin/altair db:migrate
docker compose up -d
curl -fsS http://localhost:3000/health
```

The runtime image keeps the compiled server and launcher, public assets and
configuration, and `db/migrations` (the runner matches those filenames to the
compiled registry). PostgreSQL data lives in `pg_data`; SQLite data lives in
`sqlite_data` at `/app/db/data`. Secrets such as `SECRET_KEY_BASE` and
`POSTGRES_PASSWORD` are required environment variables; inject them from your
secret manager.

## Offline docs and examples

`altair docs` and `altair examples` read the curated `bundle/` shipped with
the framework source and the release source archive. Nothing requires a
network connection:

```bash
altair docs --list
altair docs record associations
altair docs --open deployment
altair examples hello
altair examples --copy hello
```

Copied examples live in `examples/altair/` and have no `shard.yml` of their
own; they compile against the project's dependencies. Generated projects
record provenance in `.altair/bundle.yml` and cache guides/examples under
`.altair/cache/`. `altair docs --refresh` updates both after an upgrade.
Nothing is written into `lib/`, which stays managed by Shards.

## Updating

`altair update` checks GitHub for the latest release, downloads the binary
for your platform, verifies its SHA-256 digest against the published
`SHA256SUMS`, and replaces the running executable:

```bash
altair update          # update to the latest release
altair update --check  # report whether a newer version exists, install nothing
altair update --force  # reinstall even when already up to date
```

`--check` is safe for automation (a cron job, say): it exits `0` when the
installed binary is current and `1` when an update is available, without
writing anything.

You can also update manually:

- **Re-run the installer** — `curl ... install.sh | sh -s -- --force`
  (or `iex (irm ...)` on Windows) downloads the prebuilt binary again.
- **From a source checkout** — `shards build altair && ./bin/altair install --force`
  builds the current source and copies it onto your `PATH`.

Updating the `altair` binary is separate from updating a project's copy of
the framework: inside a project, `shards update altair` (then `shards
install`) pulls the latest framework shard, and a fresh `shards install`
after removing `shard.lock` and `lib/` re-resolves from scratch. After
upgrading the CLI, run `altair docs --refresh` inside a project to refresh
the offline `bundle/` cache and `.altair/bundle.yml`.