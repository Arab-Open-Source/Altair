# Altair benchmark — entry point.
#
# Serve one PostgreSQL-backed CRUD endpoint pair (write + read) on the
# framework's default stack. Compose pins the container to 2 CPUs and this
# application resizes Crystal's execution context to match (see
# application.cr).
require "altair"
require "altair/record/adapters/postgresql"
require "../db/schema"
require "./models/item"
require "./controllers/application_controller"
require "./controllers/items_controller"
require "./application"

Bench.run!
