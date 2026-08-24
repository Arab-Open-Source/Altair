# Usage

Altair projects are generated with the `altair` CLI. Every command is type-checked and compile-time safe: a wrong argument is a compile error, not a runtime surprise.

## Create a new project

```sh
altair new blog
cd blog
shards install
```

This generates the standard layout: `src/`, `db/`, `public/`, the `bin/altair` wrapper script, plus `.env` and `config/database.yml` — so a fresh project's configuration is file-driven, not code-driven. See the [Configuration guide](/docs/configuration.html).

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

## Try the demo

The repository ships `examples/hello_world`, the always-running demo app:

```sh
cd examples/hello_world
shards install
crystal run src/hello_world.cr
```

`examples/blog` is the persistence demo — posts and comments survive restarts.
