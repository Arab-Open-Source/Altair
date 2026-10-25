# Altair benchmark — entry point.
#
# Serve one PostgreSQL-backed CRUD endpoint pair (write + read) on the
# framework's default stack. Compose pins the container to 2 CPUs and this
# application resizes Crystal's execution context to match (see
# application.cr). The GC is Crystal's bundled Boehm, tuned for the read
# tail in gc_tuning.cr (measured basis: read-tail-investigation.md).
require "altair"
require "altair/record/adapters/postgresql"
require "../db/schema"
require "./models/item"
require "./controllers/application_controller"
require "./controllers/items_controller"
require "./gc_tuning"
require "./application"

BenchGC.setup!
Bench.run!
