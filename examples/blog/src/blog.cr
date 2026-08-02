# Blog — a working Altair application with a real database.
#
# This is the first Altair application that persists: migrations build the
# SQLite schema, `db/schema.cr` is regenerated after every run, and the
# posts controller reads and writes through `Altair::Record.connection`.
# Run it from this directory:
#
# ```
# crystal run scripts/db.cr -- migrate # create the schema
# crystal run src/blog.cr             # serve on http://localhost:4000
# ```
#
# then:
#
# ```
# curl localhost:4000/
# curl -X POST localhost:4000/posts -d "title=First+post"
# ```
#
# Restart the server: the posts are still listed, because they live in
# `db/blog.db`, not in memory.
require "altair"
require "../db/schema"
require "./config/application"
require "./app/controllers/application_controller"
require "./app/models/post"
require "./app/controllers/posts_controller"

Blog.run!
