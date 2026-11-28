# Deployment

Every generated project includes a multi-stage `Dockerfile`, `.dockerignore`
and `compose.yml`. The builder uses Crystal 1.22.3 and links statically; the
runtime image contains the compiled server, the compiled project launcher,
public assets/configuration, and the `db/migrations` files the runner needs.
The database files themselves stay outside the image (a named volume for
SQLite). The image runs as a non-root user and declares a
`HEALTHCHECK` against `/health`. `.env`, `.git`, `lib/`, `spec/`, local
databases and caches are excluded from the build context and final image.

## Build, migrate and run

```bash
docker compose build
docker compose run --rm web ./bin/altair db:migrate
docker compose up -d
curl -fsS http://localhost:3000/health
```

The application itself never runs migrations at boot. The one-off `run`
command uses the same compiled `./bin/altair` launcher as local development.
Migration files are kept in the image at `db/migrations` because the runner
matches them to the compiled migration registry; the database files live
outside that directory.

## Migrations

Migrations never run at container boot. Apply them exactly once, verify,
then roll out new images. An additive migration (nullable column, new table)
can run before the new binary; a destructive change needs a two-step deploy
because old binaries may still reference removed columns. The generated
Compose setup runs a single web container; rolling or zero-downtime deploys
need an orchestrator and a migration plan. Generated migrations are compiled
into the command binary, and their files are copied into the image, so a
schema change requires both a migration and a rebuilt image.

## Rollback

`bin/altair db:rollback` reverts one migration and regenerates
`db/schema.cr`. Treat it as a maintenance operation, not an automatic
rollback: rebuild the image so the compiled schema matches the database.

## Backups and volumes

PostgreSQL data lives in the `pg_data` volume at
`/var/lib/postgresql/data`; take `pg_dump` backups before migrations and
rehearse restores. SQLite data lives in the `sqlite_data` volume mounted at
`/app/db/data`, while migration files stay in the image at
`/app/db/migrations`; that keeps new migrations visible after an image
rebuild. WAL mode writes `db/*.db-wal` and `db/*.db-shm` beside the
database, so keep all three files in the same volume and run a single writer
container.

## Secrets

Compose defaults carry no real secrets. `SECRET_KEY_BASE` and database
credentials are required environment variables; inject them from your
secret manager. Never commit `.env` or place credentials in an image layer.

## API projects

`--api` projects build without view or asset stages and still expose
`/health` and `/metrics`.
