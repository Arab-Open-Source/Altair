# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Config`, the application configuration object.
# Every `Altair::Application` owns one, and it is exposed through the
# `config` accessor. Framework settings are typed properties with sensible
# defaults, and each environment carries its own settings bag
# (`development`, `production`, `test`) that the application reads at boot
# time.
module Altair
  class Config
    # The application display name, shown on the welcome page and in logs.
    property name : String = "Altair Application"

    # The host the HTTP server binds to. Defaults to `0.0.0.0` so the
    # application is reachable from outside the machine.
    property host : String = "0.0.0.0"

    # The port the HTTP server listens on. Defaults to 3000, the
    # conventional web development port.
    property port : Int32 = 3000

    # Whether the server resizes Crystal's execution context to the
    # available workers on boot, so requests fan out across cores instead
    # of running on the single OS thread the runtime starts with. Honors
    # the `CRYSTAL_WORKERS` environment variable; set it to your CPU limit
    # when running inside a container. Disable to keep the runtime's
    # default parallelism.
    property? parallel_execution : Bool = true

    # How many successful route lookups the router memoizes per `"METHOD
    # path"`. A hot path is matched once and then answered from the cache —
    # no segment walk, no parameter re-extraction — until evicted by
    # least-recently-used pressure. `0` disables the cache.
    property router_cache_size : Int32 = 1024

    # The logger used by the framework for boot messages, requests and
    # errors. Applications may swap it for their own `Log` instance.
    property logger : Log = Log.for("altair")

    # The application cache. It stays local by default; assign another
    # `Altair::Cache::Store` when values must be shared across processes.
    property cache : Altair::Cache::Store = Altair::Cache::MemoryStore.new

    # The backend that persists uploaded application files.
    property storage : Altair::Storage::Store = Altair::Storage::DiskStore.new(Path.new(Dir.current).join("public/uploads"))

    # Enables built-in liveness and Prometheus-compatible metrics endpoints.
    property? observability : Bool = false

    # When enabled, the request logger emits one JSON object per request
    # (method, path, status, duration, request_id) instead of aligned text.
    # Cookies, Authorization and request bodies are never included.
    property? structured_logs : Bool = false

    # The liveness endpoint served before route dispatch when observability
    # is enabled.
    property health_path : String = "/health"

    # The metrics endpoint served before route dispatch when observability
    # is enabled.
    property metrics_path : String = "/metrics"

    # The WebSocket endpoint used by `Altair::Cable`.
    property cable_path : String = "/cable"

    # Whether the Cable WebSocket handler is installed. Set to false to
    # skip the handler entirely (e.g. for API-only projects).
    property? cable_enabled : Bool = true

    # Called during the Cable handshake with a ConnectionContext. Return
    # false to reject the connection with 401. When nil, no auth check runs.
    property cable_auth : Proc(Altair::HTTP::Request, Altair::Cable::ConnectionContext, Bool)? = nil

    # When set, only requests whose Origin header matches one of these
    # values are allowed through; others receive 403.
    property cable_allowed_origins : Array(String)? = nil

    # How often the Cable heartbeat sends ping frames.
    property cable_heartbeat_interval : Time::Span = 30.seconds

    # How long to wait for a pong before closing a stale connection.
    property cable_pong_budget : Time::Span = 10.seconds

    # Whether console colors are enabled. `nil` (the default) auto-detects
    # from `STDOUT.tty?` and `NO_COLOR`/`TERM`; `true`/`false` forces it.
    property logger_colors : Bool? = nil

    # Compact request logging without timestamps or alignment.
    property? logger_compact : Bool = false

    # Whether request lines include a `HH:MM:SS` timestamp.
    property? logger_timestamps : Bool = true

    # Whether request lines include a sequential counter (`#0001`).
    property? logger_request_counter : Bool = false

    # Whether request lines include the client IP address.
    property? logger_show_client_ip : Bool = false

    # Requests slower than this are highlighted in the log.
    property slow_request_threshold : Time::Span = 20.milliseconds

    # Validates the slow-request threshold is not negative.
    def slow_request_threshold=(value : Time::Span) : Nil
      raise ArgumentError.new("slow_request_threshold must not be negative") if value < Time::Span.zero
      @slow_request_threshold = value
    end

    # The secret used to sign session cookies (and later CSRF tokens and
    # JWT signatures). Reads `SECRET_KEY_BASE` from the environment when
    # not set explicitly. Must be set in production — signing without a
    # real secret lets an attacker forge session cookies.
    property secret_key_base : String? = ENV["SECRET_KEY_BASE"]?

    # The name of the session cookie used by the default `SignedCookieStore`.
    # Applications with several Altair apps behind one host should give each
    # its own name.
    property session_cookie_name : String = "_altair_session"

    # The lifetime of the session cookie. `nil` (the default) makes it a
    # browser-session cookie that expires when the client closes; set a
    # `Time::Span` such as `30.days` to keep users logged in across restarts.
    property session_expiry : Time::Span? = nil

    # Whether the session cookie carries the `Secure` attribute. `nil`
    # (the default) turns it on only in production; force on/off with `true`
    # or `false`.
    property session_cookie_secure : Bool? = nil

    # The session store the controllers use, built lazily from the
    # `session_*` settings. Applications that need a custom backend (e.g.
    # server-side storage) assign their own `Altair::Session::Store` here.
    property session_store : Altair::Session::Store? = nil

    # The path the `require_login` filter redirects unauthenticated
    # requests to.
    property login_path : String = "/login"

    # The maximum request body size in bytes, applied while reading the
    # body before any parsing — a request that exceeds it answers 413
    # Payload Too Large. Raise it (or set it to `nil` to disable the
    # limit) when the application accepts large uploads:
    #
    # ```
    # config.max_body_size = 100.megabytes
    # config.environments.production.max_body_size = 100.megabytes
    # ```
    property max_body_size : Int64? = 2_000_000

    # The htmx version served by `javascript_include_tag :htmx`. `nil`
    # falls back to the framework's pinned default.
    property htmx_version : String? = nil

    # A custom htmx source URL — a different CDN or a local file under
    # `public/`. Takes precedence over `htmx_version`.
    property htmx_src : String? = nil

    # The database connection URL, e.g. `sqlite3://./db/app.db`. The
    # `Altair::Record` layer opens one connection pool from it on first
    # use; set it per environment for isolated test databases.
    property db_url : String? = nil

    # The maximum number of pooled database connections. Each request may
    # check one out at a time; extra checks wait for a free connection.
    property db_max_pool_size : Int32 = 10

    # How many fibers may hold a pooled connection at once. Requests past
    # the limit wait on a FIFO permit gate before entering the pool, which
    # keeps tail latency bounded under overload. `0` disables the gate.
    property db_max_active_queries : Int32 = 0

    # How long a request waits on the admission gate for a database permit
    # before raising `Altair::Concurrency::Timeout` (a 503 by default). A
    # deadline keeps saturated requests from parking in the FIFO queue
    # forever; `db_checkout_timeout` bounds the pool wait separately.
    property db_admission_timeout : Time::Span = 5.seconds

    # The initial number of connections opened when the pool is created.
    # Starting warm avoids connection-creation bursts under the first wave
    # of concurrent requests.
    property db_initial_pool_size : Int32 = 2

    # The maximum number of idle connections the pool keeps open. Idle
    # connections beyond this are closed when released, so a small value
    # causes frequent reconnect churn under sustained load. Kept close to
    # `db_max_pool_size` so the pool stays warm.
    property db_max_idle_pool_size : Int32 = 2

    # How long a connection checkout waits when the pool is exhausted
    # before raising, in seconds.
    property db_checkout_timeout : Float64 = 5.0

    # The per-query timeout applied to statements. PostgreSQL receives this as
    # a server-side `statement_timeout` during connection startup; adapters
    # that do not support cancellation may only use it for checkout policy.
    property db_query_timeout : Time::Span = 5.seconds

    # How long the background-jobs worker sleeps after an empty poll of the
    # `altair_jobs` table. Lower values pick up new work sooner at the cost
    # of more polling queries.
    property jobs_poll_interval : Time::Span = 1.second

    # The attempt budget per background job before it is parked as failed.
    # Individual jobs may override through their own `max_attempts`.
    property jobs_max_attempts : Int32 = 5

    # The queues a background worker drains, in priority order.
    property jobs_queues : Array(String) = ["default"]

    # Whether the development-mode N+1 detector is active. It counts
    # identical queries within a request and logs a warning above
    # `n_plus_one_threshold`; only armed in the Development environment,
    # so production never pays its per-statement timing.
    property? detect_n_plus_one : Bool = true

    # How many times the same SQL may fire within one request before the
    # detector warns. `0` disables the detector regardless of the flag.
    property n_plus_one_threshold : Int32 = 3

    # The middleware stack, run in order on every request before routing.
    # Each entry is a factory proc that builds one middleware for the
    # application, e.g. `->(app : Altair::Application) { MyMiddleware.new(app) }`.
    # Defaults to request logging, request-id assignment, the default
    # security headers and static-file serving from `public/`; CORS is
    # present but a pass-through until `config.cors.origins` is filled.
    # Assign an empty array to disable all of them, or build your own stack.
    property middleware : Array(Proc(Altair::Application, Altair::Middleware)) = [
      ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::Logger.new(app) },
      ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::RequestId.new(app) },
      ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::SecurityHeaders.new(app) },
      ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::Cors.new(app) },
      ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::Static.new(app) },
    ]

    # The header carrying the request identifier assigned by the
    # `RequestId` middleware. A client-supplied value for this header is
    # honored; otherwise a fresh UUID is generated and echoed back.
    property request_id_header : String = "X-Request-Id"

    # The security headers stamped on every response by the
    # `SecurityHeaders` middleware. Entries are only written when the
    # response does not already carry the header. Set to `{} of
    # String => String` to disable the layer.
    property security_headers : Hash(String, String) = {
      "X-Content-Type-Options" => "nosniff",
      "X-Frame-Options"        => "SAMEORIGIN",
      "Referrer-Policy"        => "strict-origin-when-cross-origin",
    }

    # Cross-origin resource sharing settings driving the `Cors` middleware.
    getter cors : Cors = Cors.new

    # Global debug flag, inherited from the active environment's settings.
    property? debug : Bool = false

    # Per-environment settings bags, addressed like
    # `config.environments.development.debug = true`.
    getter environments : Environments = Environments.new

    # Returns the settings bag for the given environment:
    #
    # ```
    # config.environment(Altair::Env::Development).debug # => true
    # ```
    def environment(name : Env) : Environment
      case name
      when Env::Development
        @environments.development
      when Env::Production
        @environments.production
      else
        @environments.test
      end
    end

    # Holds the three per-environment settings bags. Exposed through
    # `Config#environments` so settings read like
    # `config.environments.production.eager_load = true`, the familiar shape
    # of per-environment configuration.
    class Environments
      # Development settings bag. Debug is on by default.
      getter development : Environment

      # Production settings bag. Eager loading is on by default.
      getter production : Environment

      # Test settings bag. Debug is on by default.
      getter test : Environment

      def initialize
        @development = Environment.new(debug: true)
        @production = Environment.new(eager_load: true)
        @test = Environment.new(debug: true)
      end
    end

    # Cross-origin resource sharing settings. `origins` is the only knob
    # that matters for enabling CORS: an empty list (the default) leaves the
    # `Cors` middleware a pass-through. Everything else is optional tailoring.
    #
    # ```
    # config.cors.origins = ["https://app.example.com"]
    # config.cors.credentials = true
    # ```
    class Cors
      # The allowed origins, exact-match against the `Origin` header. A
      # `"*"` entry grants any origin. Empty (the default) disables CORS.
      property origins : Array(String) = [] of String

      # The methods allowed in preflight responses, e.g.
      # `"GET, POST, PATCH, PUT, DELETE, OPTIONS"`.
      property methods : String = "GET, HEAD, POST, PATCH, PUT, DELETE, OPTIONS"

      # The request headers echoed back in preflight responses. When the
      # client's `Access-Control-Request-Headers` names extra headers, that
      # list is honored instead.
      property headers : String = "Content-Type, Authorization, X-CSRF-Token"

      # Whether the `Access-Control-Allow-Credentials` header is included,
      # admitting cookies on cross-origin requests. Methods that rely on
      # `Origin`-scoped credentials should combine this with the framework's
      # signed session cookie, which carries `SameSite=Lax` by default.
      property? credentials : Bool = false

      # The `Access-Control-Max-Age` value in seconds for preflight
      # caching, or `nil` to omit the header.
      property max_age : Int64? = nil

      # Whether `origin` is on the allowed list (or the list carries `"*"`).
      def origin_allowed?(origin : String) : String?
        return "*" if origins.includes?("*")
        origins.includes?(origin) ? origin : nil
      end

      # The value written to `Access-Control-Allow-Origin`: the literal
      # opening the wildcard unless credentials are requested, in which case
      # the exact origin is echoed so the browser keeps credentials.
      def allow_origin_header(origin : String) : String
        if origins.includes?("*") && !credentials?
          "*"
        else
          origin
        end
      end

      # The `Access-Control-Allow-Headers` value: the configured list, or
      # the client-requested headers when the echo-back is needed.
      def allow_headers(requested : String?) : String
        requested && !requested.empty? ? requested : headers
      end
    end
  end
end
