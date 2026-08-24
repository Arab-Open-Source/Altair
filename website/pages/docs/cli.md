# CLI reference

The `altair` command is the framework's tool. It scaffolds projects and files, runs a generated app, and installs itself onto your `PATH`.

## Installing `altair`

### From a GitHub release (recommended for new users)

The official installer downloads the prebuilt binary for your platform, verifies its SHA-256 digest against the published `SHA256SUMS`, and installs it onto your `PATH` — no Crystal toolchain required.

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

It is fail-safe: nothing is written unless the checksum matches, an existing different binary is never overwritten without `--force` (or `-Force` on Windows), and it is idempotent over an identical install. Options: `--dir DIR` / `-Dir`, `--force` / `-Force`, `--version VER` / `-Version`.

### From a source checkout

The framework builds a standalone binary from `src/altair_cli.cr`:

```bash
shards build altair
./bin/altair install
```

`altair install` copies the running binary into a user-owned bin directory on `PATH`:

| Platform | Default target |
|----------|----------------|
| Unix (Linux, macOS) | `~/.local/bin/altair` |
| Windows | `%USERPROFILE%\.altair\bin\altair.exe` |

It prints the installed binary's SHA-256 digest so you can verify the copy matches its source. The install is deliberately cautious:

- **Idempotent** — a target that already matches the source is a no-op.
- **Refuses to clobber** — an existing, different file at the target aborts unless you pass `--force`.
- **`--dir DIR`** installs somewhere explicit instead of the default.
- **`ALTAIR_BIN`** sets the default install directory via the environment.

## Commands

| Command | Purpose |
|---------|---------|
| `altair new <name> [--framework-path DIR] [-d sqlite\|postgresql] [--api]` | Scaffold a runnable project. `<name>` may include a path (`a/b`, `/tmp/my_app`); only its basename becomes the application name. Names must be lowercase letters, digits and underscores starting with a letter — `my-app` is rejected with a suggestion `my_app`. By default it depends on the published shard; pass `--framework-path` (or set `ALTAIR_PATH`) to use a local checkout. `-d postgresql` wires the `pg` shard, postgres URLs in `config/database.yml` and the adapter require; `-d sqlite` is the default (`ALTAIR_DATABASE` env fallback). `--api` generates a JSON-only project (no views/assets) with CORS enabled. |
| `altair g scaffold <Name> [column:type ...]` | Model + migration + RESTful controller + ECR views + `resources` route + seeded `db/schema.cr`. |
| `altair g model <Name> [column:type ...]` | A model file and its table. |
| `altair g admin <Name>` | Namespaced admin controller with `require_login` + `namespace :admin` routes. |
| `altair g auth [User]` | Full registration/login stack: User model (`password_auth`, unique email), migration with the unique index, sessions + registrations controllers, login/register views, and the `/login`, `/register`, `/logout` routes. |

| `altair g migration Create<Table> [column:type ...]` | A timestamped migration. |
| `altair g controller <Name>` | A controller and its views. |
| `altair install [--dir DIR] [--force]` | Install the binary onto `PATH`. |
| `altair update [--check] [--force]` | Update the binary to the latest release. |
| `altair version` | Print `Altair <version>`. |
| `altair help` | Print usage. |

Column specs take a type after a colon and default to `string`: `title:string body:text price:float published:boolean`.

## Inside a generated project

App-context commands run against the project's application. From anywhere
inside the project directory — a subfolder included — the CLI finds the
nearest project and forwards the command to its launcher, so you never
need to type `bin/`:

| Command | Purpose |
|---------|---------|
| `altair server` | Run the app. |
| `altair routes` | Print the compiled route table. |
| `altair db:migrate` | Run pending migrations. |
| `altair db:rollback` | Undo the latest migration. |
| `altair db:create` | Create every environment database from `config/database.yml` (idempotent; PostgreSQL targets are created through the maintenance database). |
| `altair db:drop` | Drop those databases. Refuses in production without `--force`. |
| `altair db:seed` | Run the blocks registered in `db/seeds.cr`. |
| `altair assets:precompile` | Fingerprint `assets/` into `public/assets/` and write the manifest the view helpers resolve through. |
| `altair jobs:work` | Run the background-jobs worker until interrupted (graceful SIGINT/SIGTERM shutdown). |
| `altair jobs:stats` | Print background-job status counts (`pending`/`running`/`done`/`failed`). |

`db/seeds.cr` registers its blocks when the file is required and runs
them only through `db:seed` — booting a server never plants data. Blocks
re-run on every invocation, so guard with `unless Model.exists?` to stay
idempotent.

The jobs table (`altair_jobs`) creates itself lazily on first enqueue —
no migration is needed; point `jobs:work` at the same database as the
server and enqueued work drains in order with retries on failure.

`altair g scaffold ...` and the other generators write into the current
project the same way. The project launcher itself (`bin/altair`, or
`bin/altair.cr` in projects created before the executable wrapper) is
still there and accepts the same commands — both work.

When running the launcher with `crystal run` instead of the built binary, use `--` before the argument so `crystal run` does not consume it:

```bash
crystal run bin/altair.cr -- db:migrate
```

## Updating

`altair update` checks GitHub for the latest release, downloads the binary
for your platform, verifies its SHA-256 digest against the published
`SHA256SUMS`, and replaces the running executable:

```bash
altair update          # update to the latest release
altair update --check  # report whether a newer version exists, install nothing
altair update --force  # reinstall even when already up to date
```

`--check` is safe for automation — it exits `0` when the installed binary
is current and `1` when an update is available, without writing anything.

Updating the `altair` binary is separate from updating a project's copy of
the framework: inside a project, `shards update altair` pulls the latest
framework shard.
