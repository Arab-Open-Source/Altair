# Blog — a working Altair application with a real database.
#
# This is the first Altair application that persists: migrations build the
# SQLite or PostgreSQL schema, `db/schema.cr` is regenerated after every run, and the
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
# Restart the server: the posts are still listed because they live in the
# configured database, not in memory.
require "altair"
require "../db/schema"
require "./app/models/comment"
require "./app/models/post"
require "./app/models/user"
require "./app/controllers/application_controller"
require "./app/controllers/comments_controller"
require "./app/controllers/posts_controller"
require "./app/controllers/sessions_controller"
require "./app/controllers/registrations_controller"
require "./app/jobs/post_published_job"
require "./config/application"

Blog.run!
