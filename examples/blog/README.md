# Blog — the first Altair application backed by a database.
#
# Shows the Phase 4 (record) vertical slice end to end: migrations create
# a SQLite or PostgreSQL schema, `db/schema.cr` is regenerated automatically after
# every run (with the compile-time column metadata the models read), and
# the posts controller drives full CRUD through the `Post` model —
# validations, auto-timestamps, finders and callbacks included. Every
# value travels as a bind parameter, every connection runs in WAL
# journaling mode with a 5s busy timeout, and each migration applies
# inside a transaction — a failing migration rolls back completely.
#
# Wave 3 adds the associations: `Post has_many :comments, dependent:
# :destroy` and `Comment belongs_to :post`. The post page lists its
# comments with a form to add new ones (an empty body answers 422 with
# the error on the form), the index shows each post's comment count,
# and `Post.all.includes(:comments)` on the index preloads every post's
# comments in a single query instead of one per post. Deleting a post
# destroys its comments.
#
# Phase 7 adds authentication, the asset pipeline and background jobs:
#
# - **Authentication** — register at `/register`, sign in at `/login`,
#   sign out from any page. Passwords hash through PBKDF2-SHA256 via the
#   model's `password_auth` declaration, emails are unique, and creating,
#   editing or deleting a post requires a signed-in session (`require_login`
#   answers guests with a redirect to `/login`).
# - **Asset pipeline** — `assets/css/app.css` compiles into a fingerprinted
#   file under `public/assets/` plus a manifest; the layout links it through
#   `asset_url`, so browsers cache it forever and a content change rotates
#   the URL.
# - **Background jobs** — every new post enqueues a `PostPublishedJob`. Run
#   the worker in another terminal and watch it announce each post:
#
#   ```
#   crystal run scripts/jobs.cr
#   ```
#
# ## Run it
#
# From this directory:
#
# ```
# crystal run scripts/assets.cr           # compile assets/ -> public/assets/
# crystal run scripts/db.cr -- migrate    # create/update the schema
# crystal run src/blog.cr                 # serve on http://localhost:4000
# ```
#
# then open http://localhost:4000, register an account, add a post, and restart the server —
# the post is still there, because it lives in `db/blog.db`.
#
# PostgreSQL uses the same application, models, controllers and migrations.
# Set `ALTAIR_DB_URL` for both the migration runner and server:
#
# ```
# export ALTAIR_DB_URL="postgres://postgres:secret@localhost:5432/blog"
# crystal run scripts/db.cr -- migrate
# crystal run src/blog.cr
# ```
#
# PostgreSQL support comes from the example's `pg` dependency. SQLite remains
# the default when `ALTAIR_DB_URL` is absent.
#
# ```
# curl localhost:4000/
# curl -X POST localhost:4000/posts -d "title=First+post"
# curl -X POST localhost:4000/posts -d "title=Second+post"
# curl -X POST localhost:4000/posts/1 -d "_method=PUT&title=Renamed"
# curl -X POST localhost:4000/posts/2 -d "_method=DELETE"
# curl -X POST localhost:4000/posts/1/comments -d "body=A+comment"
# curl localhost:4000/posts/1        # the comment appears on the post page
# curl localhost:4000/               # the index shows comment counts
# ```
#
# An empty title answers 422 with the validation error shown on the form,
# and so does an empty comment body.
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
# assets/css/app.css        asset-pipeline source styles
# public/assets/            compiled fingerprints + manifest.json (generated)
# src/app/models/           Post, Comment and User models (associations, validations, password_auth)
# src/app/controllers/      posts, comments, sessions and registrations controllers
# src/app/jobs/             PostPublishedJob — enqueued when a post is created
# scripts/db.cr             the migrate/rollback runner
# scripts/assets.cr         the asset precompiler
# scripts/jobs.cr           the background-jobs worker
# ```
