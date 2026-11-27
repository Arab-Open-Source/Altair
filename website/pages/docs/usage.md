# Usage

Altair projects are generated with the `altair` CLI. Every command is type-checked and compile-time safe: a wrong argument is a compile error, not a runtime surprise.

## Create a new project

```sh
altair new blog
cd blog
shards install
```

This generates the standard layout: `src/`, `db/`, `public/`, the `bin/altair` wrapper script, plus `.env` and `config/database.yml` — so a fresh project's configuration is file-driven, not code-driven. See the [Configuration guide](/docs/configuration.html).

Pass `-d postgresql` to generate a project wired to PostgreSQL (the `pg` shard, `postgres://` URLs and the adapter require). Pass `--api` for a JSON-only project with CORS enabled and no views or assets. Both modes generate the same deployment files as SQLite projects.

Add `--with-examples` to copy a curated set of runnable starter programs into `examples/altair/` alongside your app — they compile against the project's own `shard.yml` and never touch `lib/`:

```sh
altair new blog --with-examples
```

## Offline docs and examples

The CLI ships a curated documentation and examples bundle, so its help works without a network connection:

```sh
altair docs --list                # list available topics
altair docs record associations   # print just that section of the Record guide
altair docs deployment            # read the deployment guide offline
altair docs --open routing        # open the published guide in a browser

altair examples                   # list starter examples
altair examples hello             # read one example's README
altair examples --copy hello      # copy it into examples/altair/ (inside a project)
```

`altair examples --copy` requires a generated project. Provenance is recorded in `.altair/bundle.yml`; after upgrading Altair, run `altair docs --refresh` inside the project to refresh the local `.altair/cache/`. See the [Offline docs and examples guide](/docs/docs_and_examples.html).

## Run the server

```sh
altair server
```

Open <http://localhost:3000> in your browser. Inside the project the CLI
finds the project automatically — `server`, `routes` and the database
commands work from any subdirectory, so you never need to type `bin/`.
The project's own `bin/altair` launcher accepts the same commands if you
prefer it.

## Generate a scaffold

The full magic — model, migration, controller, views and a `resources` route in one command:

```sh
altair g scaffold Post title:string body:text
```

Then migrate the database and start the server:

```sh
altair db:migrate
altair server
```

You get a working CRUD app for posts, ready to edit.

## Generate individual pieces

```sh
altair g model Person name:string age:int
altair g migration add-email-to-person email:string
altair g controller People index show
```

## List the routes

```sh
altair routes
```

## Database commands

```sh
altair db:create     # create every environment database from config/database.yml
altair db:migrate    # run pending migrations
altair db:rollback   # roll back the last migration
altair db:drop       # drop databases (refuses in production without --force)
altair db:seed       # run db/seeds.cr
altair assets:precompile  # fingerprint assets/ -> public/assets/
altair jobs:work     # run background jobs
altair jobs:stats    # print job counts
```

## Project structure

```
src/            your application code
db/             migrations and db/schema.cr
public/         static assets served as-is
bin/altair      the per-project command wrapper
.env            environment settings (.env.<environment> overrides)
config/database.yml   per-environment database settings
```

## Deploy with Docker

`altair new` generates a multi-stage `Dockerfile`, a `.dockerignore` and a `compose.yml` for SQLite, PostgreSQL and `--api` projects. The image builds a static Crystal 1.22.3 binary, runs as a non-root user, precompiles assets, and checks `/health`. Migrations are never automatic:

```sh
docker compose build
docker compose run --rm web ./bin/altair db:migrate
docker compose up -d
curl -fsS http://localhost:3000/health
```

Inject secrets through the environment — the generated Compose file requires `SECRET_KEY_BASE` (and `POSTGRES_PASSWORD` for PostgreSQL) with `${VAR:?...}` and ships no real credentials. PostgreSQL data lives in the `pg_data` volume; SQLite data lives in `sqlite_data` mounted at `/app/db/data`, while `db/migrations` stays in the image. See the [Deployment guide](/docs/deployment.html) for backups, rollback and the SQLite WAL caveat.

## Try the demo

The repository ships `examples/hello_world`, the always-running demo app:

```sh
cd examples/hello_world
shards install
crystal run src/hello_world.cr
```

`examples/blog` is the persistence demo — posts and comments survive restarts.
