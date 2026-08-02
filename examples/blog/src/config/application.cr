# Blog — the application configuration.
#
# The first Altair application with a real database: `config.db_url` points
# at a SQLite file, the migration runner (`scripts/db.cr`) creates the
# schema, and the posts controller reads and writes through
# `Altair::Record.connection`. Restart the server and the posts are still
# there — the file is the storage.
class Blog < Altair::Application
  config.name = "Blog"
  config.port = 4000
  config.db_url = "sqlite3://./db/blog.db"

  routes do
    root to: PostsController.index
    post "/posts", to: PostsController.create
  end
end
