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

    # The logger used by the framework for boot messages, requests and
    # errors. Applications may swap it for their own `Log` instance.
    property logger : Log = Log.for("altair")

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
    # Defaults to request logging and static-file serving from `public/`;
    # assign an empty array to disable both, or build your own stack.
    property middleware : Array(Proc(Altair::Application, Altair::Middleware)) = [
      ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::Logger.new(app) },
      ->(app : Altair::Application) : Altair::Middleware { Altair::Middleware::Static.new(app) },
    ]

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
  end
end
