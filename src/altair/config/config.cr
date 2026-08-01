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

    # The logger used by the framework for boot messages, requests and
    # errors. Applications may swap it for their own `Log` instance.
    property logger : Log = Log.for("altair")

    # The htmx version served by `javascript_include_tag :htmx`. `nil`
    # falls back to the framework's pinned default.
    property htmx_version : String? = nil

    # A custom htmx source URL — a different CDN or a local file under
    # `public/`. Takes precedence over `htmx_version`.
    property htmx_src : String? = nil

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
