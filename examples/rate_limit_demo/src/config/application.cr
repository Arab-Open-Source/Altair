# Rate Limit Demo — the application configuration.
#
# Demonstrates declarative rate limiting with per-path rules and pluggable
# stores. The middleware is a pass-through until rules are declared.
class RateLimitDemo < Altair::Application
  config.name = "Rate Limit Demo"
  config.port = 3000

  # Sliding-window rate limiting. The most restrictive matching rule governs
  # each request; unmatched paths are free. Every value travels as a bind
  # parameter internally, and the middleware is a pass-through until configured.
  #
  # Stores:
  #   :memory — per-process, Mutex-guarded, evicts dead keys lazily
  #   :redis  — shared across processes via Altair::Redis (set redis_url or ALTAIR_REDIS_URL)
  config.rate_limit.configure do |rl|
    # Choose the backend. The default is :memory; switch to :redis for
    # multi-instance deployments. When :redis is selected without an
    # explicit URL, the middleware falls back to ENV["ALTAIR_REDIS_URL"].
    rl.store :memory
    # rl.store :redis
    # rl.redis_url = "redis://localhost:6379"

    # Global default: 100 requests per minute for every path.
    rl.limit 100, per: 1.minute

    # Stricter limits for sensitive endpoints.
    rl.limit 5, per: 1.minute, only: ["/login"]
    rl.limit 30, per: 1.minute, only: ["/api/data"]

    # Trust X-Forwarded-For when behind a proxy you control (clients can
    # spoof this header to mint fresh buckets, so leave it off otherwise).
    # rl.trusted_headers = true
  end

  routes do
    root to: PagesController.index
    get "/login", to: PagesController.login
    get "/api/data", to: PagesController.api_data
    get "/free", to: PagesController.free
  end
end
