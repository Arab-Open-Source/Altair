# Altair benchmark - application wiring.
require "altair/record/adapters/postgresql"

# Tune multi-threading: Crystal 1.21 runs fibers on a parallel execution
# context that defaults to a single OS thread. Respecting CRYSTAL_WORKERS
# (set to the app's 2 CPUs by the compose file) lets the HTTP server and DB
# pool actually fan out across cores instead of staying single-threaded.
Fiber::ExecutionContext.default.resize(
  maximum: Fiber::ExecutionContext.default_workers_count
)

class Bench < Altair::Application
  config.name = "Altair benchmark"
  config.port = ENV["PORT"]?.try(&.to_i?) || 4000
  config.db_url = ENV["DATABASE_URL"]? || raise(
    Altair::ConfigurationError.new("Set DATABASE_URL to a PostgreSQL URL")
  )
  # Tuned: pool sized for sustained load instead of the conservative 5.
  config.db_max_pool_size = ENV["BENCH_POOL"]?.try(&.to_i?) || 30
  # Tuned: seed the pool up front and keep idle connections warm. The
  # defaults (initial 1, max idle 1) cause reconnect churn under the bursty
  # ramp in the k6 write phase.
  config.db_initial_pool_size = ENV["BENCH_INITIAL_POOL"]?.try(&.to_i?) || 10
  config.db_max_idle_pool_size = ENV["BENCH_MAX_IDLE"]?.try(&.to_i?) || 30

  routes do
    get "/health", to: ItemsController.health
    post "/items", to: ItemsController.create
    get "/items/:id", to: ItemsController.show
  end
end
