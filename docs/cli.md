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
| `altair new <name> [--framework-path DIR]` | Scaffold a runnable project. By default it depends on the published shard; pass `--framework-path` (or set `ALTAIR_PATH`) to use a local checkout. |
| `altair g scaffold <Name> [column:type ...]` | Model + migration + RESTful controller + ECR views + `resources` route + seeded `db/schema.cr`. |
| `altair g model <Name> [column:type ...]` | A model file and its table. |
| `altair g migration Create<Table> [column:type ...]` | A timestamped migration. |
| `altair g controller <Name>` | A controller and its views. |
| `altair install [--dir DIR] [--force]` | Install the binary onto `PATH`. |
| `altair version` | Print `Altair <version>`. |
| `altair help` | Print usage. |

Column specs take a type after a colon and default to `string`:
`title:string body:text price:float published:boolean`.

## Inside a generated project

`bin/altair` (the project's launcher) accepts the app-context commands in
addition to the generators above:

| Command | Purpose |
|---------|---------|
| `altair server` | Run the app. |
| `altair routes` | Print the compiled route table. |
| `altair db:migrate` | Run pending migrations. |
| `altair db:rollback` | Undo the latest migration. |

When running the launcher with `crystal run` instead of the built binary,
use `--` before the argument so `crystal run` does not consume it:

```bash
crystal run bin/altair.cr -- db:migrate
```