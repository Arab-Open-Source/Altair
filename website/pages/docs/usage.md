# Usage

Altair projects are generated with the `altair` CLI. Every command is type-checked and compile-time safe: a wrong argument is a compile error, not a runtime surprise.

## Create a new project

```sh
altair new blog
cd blog
shards install
```

This generates the standard layout: `src/`, `db/`, `public/`, and the `bin/altair` wrapper script.

## Run the server

```sh
bin/altair server
```

Open <http://localhost:3000> in your browser.

## Generate a scaffold

The full magic — model, migration, controller, views and a `resources` route in one command:

```sh
bin/altair g scaffold Post title:string body:text
```

Then migrate the database and start the server:

```sh
bin/altair db:migrate
bin/altair server
```

You get a working CRUD app for posts, ready to edit.

## Generate individual pieces

```sh
bin/altair g model Person name:string age:int
bin/altair g migration add-email-to-person email:string
bin/altair g controller People index show
```

## List the routes

```sh
bin/altair routes
```

## Database commands

```sh
bin/altair db:migrate    # run pending migrations
bin/altair db:rollback   # roll back the last migration
```

## Project structure

```
src/            your application code
db/             migrations and db/schema.cr
public/         static assets served as-is
bin/altair      the per-project command wrapper
```

## Try the demo

The repository ships `examples/hello_world`, the always-running demo app:

```sh
cd examples/hello_world
shards install
crystal run src/hello_world.cr
```

`examples/blog` is the persistence demo — posts and comments survive restarts.
