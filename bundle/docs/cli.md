# CLI reference

## Creating and scaffolding

```bash
altair new <name> [-d sqlite|postgresql] [--api] [--with-examples] [--framework-path DIR]
altair g model|migration|controller|scaffold|auth|admin <args>
altair install [--dir DIR] [--force]
altair update [--check] [--force]
```

`--api` omits views and assets; `--with-examples` copies curated programs
into `examples/altair/`. `ALTAIR_PATH` and `ALTAIR_DATABASE` supply the same
defaults as the flags.

## Project commands

From inside a generated project, or through the standalone binary (which
forwards to the nearest project):

```bash
bin/altair server | routes
bin/altair db:create | db:migrate | db:rollback | db:seed | db:drop
bin/altair assets:precompile
bin/altair jobs:work | jobs:stats
```

`db:migrate` is never automatic.

## Offline guides and examples

```bash
altair docs [<topic> ...] [--list] [--open] [--refresh]
altair examples [<name>] [--copy [name|all]]
```

`altair docs` and `altair examples` work offline. They read the curated
bundle shipped with the release or the framework source, falling back to
references embedded in the CLI when no bundle is installed. `--refresh`
updates the project-local `.altair/cache` and `.altair/bundle.yml` from the
installed bundle. `--open` opens a matching online page in a browser and
needs network access; printing topics never does.

## Troubleshooting

If a topic cannot be found, run `altair docs --list` for exact names. If a
bundle cannot be found, install the framework source with the installer's
`--framework` flag or set `ALTAIR_BUNDLE_PATH` to a directory containing
`docs/` and `examples/`.
