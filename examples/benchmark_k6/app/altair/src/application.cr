# Altair benchmark - application wiring.
#
# The framework resizes the execution context to the available workers on
# boot (honoring CRYSTAL_WORKERS, set to 8 by the compose file), so the
# HTTP server and DB pool fan out across cores by default.
require "altair/record/adapters/postgresql"

class Bench < Altair::Application
  config.name = "Altair benchmark"
  config.port = ENV["PORT"]?.try(&.to_i?) || 4000
  config.db_url = ENV["DATABASE_URL"]? || raise(
    Altair::ConfigurationError.new("Set DATABASE_URL to a PostgreSQL URL")
  )
  # Tuned: pool sized for the sustained 2000-VU load.
  config.db_max_pool_size = ENV["BENCH_POOL"]?.try(&.to_i?) || 30
  # Tuned: seed the pool up front and keep idle connections warm.
  config.db_initial_pool_size = ENV["BENCH_INITIAL_POOL"]?.try(&.to_i?) || 10
  config.db_max_idle_pool_size = ENV["BENCH_MAX_IDLE"]?.try(&.to_i?) || 30
  # Admission control: excess fibers wait on a FIFO gate outside the pool,
  # so the tail stays bounded under 2000 concurrent requests. 0 = off.
  config.db_max_active_queries = ENV["BENCH_ACTIVE"]?.try(&.to_i?) || 0

  routes do
    get "/health", to: ItemsController.health
    post "/items", to: ItemsController.create
    get "/items/:id", to: ItemsController.show
  end
end
