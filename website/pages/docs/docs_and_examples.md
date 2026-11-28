# Offline docs and examples

Altair ships a curated **bundle** of documentation and starter examples with
the framework source and in every release source archive. `altair docs` and
`altair examples` read it locally — no network access and no dependence on a
published website.

## `altair docs`

List every topic, then read one:

```sh
altair docs --list
altair docs record associations    # prints just that section of the guide
altair docs deployment
```

Extra words are treated as topic or heading lookup: `record associations`
finds the Record guide and narrows it to its "associations" section. If no
curated guide is installed, short references compiled into the CLI are used
so the command still works.

Other switches:

- `--open` opens the matching published HTML guide in a browser (with a URL
  fallback when no opener is installed). Altair makes no network call itself.
- `--refresh` re-copies the installed bundle into the current project's
  `.altair/cache/` and rewrites `.altair/bundle.yml`. It must be run inside a
  generated project.

Topics installed with `--framework` include `deployment`, `observability`,
`read_replicas`, `docs_and_examples` and `troubleshooting`; run
`altair docs --list` for the authoritative set.

## `altair examples`

Listing and reading work from any directory:

```sh
altair examples                # list starter programs with titles
altair examples hello          # print one program's README
```

Copying requires a generated project:

```sh
altair examples --copy hello   # or --copy=hello, --copy=all
```

Sources land in `examples/altair/<name>/` and carry no `shard.yml` of their
own — they compile against the generated project's dependencies, for example
`crystal build examples/altair/hello/app.cr --no-codegen`.

To get the same starter set at project creation time, use:

```sh
altair new blog --with-examples
```

Only a curated set is copied; the full website, benchmark harness and entire
documentation tree are not.

## Provenance and upgrades

`.altair/bundle.yml` records the framework version and bundle revision. The
CLI warns on drift when the installed Altair version differs from that
record; after upgrading, run:

```sh
altair docs --refresh
```

Set `ALTAIR_BUNDLE_PATH` to a directory containing `docs/` and `examples/`
to point the CLI at a specific bundle, or `ALTAIR_PATH` at a framework
checkout whose `bundle/` should be used. The installer's `--framework` switch
extracts the source archive (including `bundle/`) to
`~/.altair/framework/<version>/`, which is what makes these commands work
offline on a machine without GitHub access.

## Nothing in `lib/`

`lib/` remains owned by Shards. Docs and examples are only ever written to
`.altair/cache/`, `.altair/bundle.yml` and `examples/altair/` — never into
`lib/`. Assistant-facing documentation lives in the generated `AGENTS.md`
and `.opencode/skills/altair/`.

See the [Installation guide](/docs/install.html), the [CLI reference](/docs/cli.html),
the generated project's README, or run `altair docs docs_and_examples`
offline.
