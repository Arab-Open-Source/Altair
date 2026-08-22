# Blog — the application configuration.
#
# The first Altair application with a real database: `config.db_url` points
# at a SQLite file, the migration runner (`scripts/db.cr`) creates the
# schema, and the posts controller reads and writes through
# `Altair::Record.connection`. Restart the server and the posts are still
# there — the file is the storage.
#
# The URL can be overridden with `ALTAIR_DB_URL` — point it at PostgreSQL
# (and require the PostgreSQL adapter + `crystal-pg`) and the same
# application runs on another database:
#
# ```
# ALTAIR_DB_URL="postgres://postgres:secret@localhost:5433/blog" crystal run src/blog.cr
# ```
#
# The adapter files are required here so both backends are available to
# the example.
require "altair/record/adapters/postgresql"

class Blog < Altair::Application
  config.name = "Blog"
  config.port = 4000
  config.db_url = ENV["ALTAIR_DB_URL"]? || "sqlite3://./db/blog.db"
  # Demo-only signing secret for sessions — set SECRET_KEY_BASE outside dev.
  config.secret_key_base = ENV["SECRET_KEY_BASE"]? || "blog-demo-secret"

  routes do
    root to: PostsController.index
    resources :posts do
      resources :comments, only: :create
    end

    get "/register", to: RegistrationsController.register_page
    post "/register", to: RegistrationsController.register
    get "/login", to: SessionsController.login_page
    post "/login", to: SessionsController.login
    delete "/logout", to: SessionsController.logout
  end
end

abstract class ApplicationController
  include Blog::RouteHelpers
end
