# PostgreSQL read-replica demo.
#
# `db_url` points at the primary; `db_replica_url` points at a streaming
# standby. Plain SELECTs use the replica, writes and transactions stay on
# the primary, and every response reports which pool actually served it.
require "altair"
require "altair/record/adapters/postgresql"
require "../db/schema"
require "./models/item"
require "./controllers/items_controller"

class ReadReplicaPostgres < Altair::Application
  config.name = "read_replica_postgres"
  config.port = 4000
  config.observability = true
  config.db_url = ENV["DATABASE_URL"]? || "postgres://altair:altair@127.0.0.1:55440/altair_demo"
  config.db_replica_url = ENV["REPLICA_DATABASE_URL"]? || "postgres://altair:altair@127.0.0.1:55441/altair_demo"
  config.db_initial_pool_size = 2
  config.db_max_pool_size = 10
  config.db_max_idle_pool_size = 10

  routes do
    get "/items", to: ItemsController.index
    post "/items", to: ItemsController.create
  end
end
