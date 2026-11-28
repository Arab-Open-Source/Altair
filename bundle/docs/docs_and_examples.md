# Offline docs and examples

`altair docs` lists the curated guides bundled with the installed framework.
`altair docs record associations` performs topic lookup across topic names
and headings; it prints the guide without network access. `--open` opens the
matching online page in a browser. `--refresh` re-copies the installed bundle
into the project's `.altair/cache/` and rewrites `.altair/bundle.yml`.

`altair examples` lists the curated starter programs. `altair examples hello`
prints one program's README, and `altair examples --copy hello` (or
`--copy all`, equivalently `--copy=hello`) copies sources into
`examples/altair/` in the current project.
`altair new --with-examples` copies the same set during project creation.

Copied examples carry no `shard.yml`: they compile against the generated
project's dependencies with, for example,
`crystal build examples/altair/hello/app.cr --no-codegen`. Nothing is written
into `lib/`; that directory stays managed by Shards. Documentation intended
for AI assistants lives in generated `AGENTS.md` and
`.opencode/skills/altair/`.

The project-local `.altair/bundle.yml` records the framework version and
bundle revision. `altair update` warns when the installed CLI version differs
from that record; run `altair docs --refresh` after upgrading.
