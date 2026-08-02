# Blog — the first Altair application backed by a database.
#
# Shows the Phase 4 (record) vertical slice end to end: migrations create
# the SQLite schema, `db/schema.cr` is regenerated automatically after
# every run (with the compile-time column metadata the models read), and
# the posts controller drives full CRUD through the `Post` model —
# validations, auto-timestamps, finders and callbacks included. Every
# value travels as a bind parameter, every connection runs in WAL
# journaling mode with a 5s busy timeout, and each migration applies
# inside a transaction — a failing migration rolls back completely.
#
# ## Run it
#
# From this directory:
#
# ```
# crystal run scripts/db.cr -- migrate
# crystal run src/blog.cr
# ```
#
# then open http://localhost:4000, add a post, and restart the server —
# the post is still there, because it lives in `db/blog.db`.
#
# ```
# curl localhost:4000/
# curl -X POST localhost:4000/posts -d "title=First+post"
# curl -X POST localhost:4000/posts -d "title=Second+post"
# curl -X POST localhost:4000/posts/1 -d "_method=PUT&title=Renamed"
# curl -X POST localhost:4000/posts/2 -d "_method=DELETE"
# ```
#
# An empty title answers 422 with the validation error shown on the form.
#
# ## Migrations
#
# `scripts/db.cr` applies pending migrations in file order — each one in
# its own transaction — records the versions in the `schema_migrations`
# table, and rewrites `db/schema.cr` from the resulting state; the schema
# file and the database can never drift apart.
#
# ```
# crystal run scripts/db.cr -- migrate
# crystal run scripts/db.cr -- rollback
# ```
#
# `db/schema.cr` is generated; edit the migrations, never the schema file.
#
# ## What is here
#
# ```
# db/migrations/           timestamped migration files (the source of truth)
# db/schema.cr             generated schema + compile-time META (written by the runner)
# db/blog.db               the SQLite database (created on first run)
# src/config/application.cr  the application + routes + db_url
# src/app/models/          the Post model (table, validations, timestamps)
# src/app/controllers/     the posts controller (full CRUD)
# scripts/db.cr            the migrate/rollback runner
# ```
