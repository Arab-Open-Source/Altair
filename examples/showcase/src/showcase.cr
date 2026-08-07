# Showcase — a full-stack Altair application.
#
# Every phase in one running thing: Record models + migrations, sessions /
# auth / CSRF, multipart uploads, `.env` + `config/database.yml`
# configuration, security middleware, JSON responses + JWT, the streaming
# and respond_to APIs, and the routing DSL (root, glob, redirect,
# resources with member/collection/nested, singular resource and
# constraints). Run from this directory:
#
# ```
# shards install
# bin/altair db: migrate # or: crystal run scripts/db.cr migrate
# bin/altair server      # or: crystal run src/showcase.cr
# ```
require "altair"
require "../db/schema"
require "../db/migrations/**"
require "./app/models/user"
require "./app/models/post"
require "./app/models/comment"
require "./app/controllers/application_controller"
require "./app/controllers/pages_controller"
require "./app/controllers/users_controller"
require "./app/controllers/sessions_controller"
require "./app/controllers/posts_controller"
require "./app/controllers/comments_controller"
require "./app/controllers/api_controller"
require "./config/application"
require "./config/routes"

Showcase.run!
