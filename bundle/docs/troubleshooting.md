# Troubleshooting

## Offline bundle missing

`altair docs` prints embedded references when no curated bundle is found.
Install the framework source with the installer's `--framework` flag (or
`-Framework` on Windows) and it will place `bundle/` under
`~/.altair/framework/<version>/`. You can also set `ALTAIR_BUNDLE_PATH` to
any directory containing `docs/` and `examples/`. Run
`altair docs --list` to confirm topics are available.

## Version drift

A generated project records its bundle provenance in `.altair/bundle.yml`.
If `altair update` reports drift, run `altair docs --refresh` inside the
project to re-copy the installed guides and examples.

## Examples will not compile

Copied examples have no `shard.yml` on purpose: they use the generated
project's dependencies. Run them from the project root after
`shards install`, for example
`crystal build examples/altair/hello/app.cr --no-codegen`. Do not add a
second Altair dependency to the example directory.

## Container health check fails

Confirm `config.observability = true` in `src/config/application.cr` and
that the container is listening on `PORT` (default 3000). Inspect with
`docker compose logs web`. The generated image checks
`http://127.0.0.1:3000/health`.

## Migrations and restarts

Migrations are explicit. After changing migrations, rebuild the image and
run `docker compose run --rm web ./bin/altair db:migrate` once. Keep SQLite
WAL sidecars in the same volume as the database; keep PostgreSQL data in
`pg_data`.
