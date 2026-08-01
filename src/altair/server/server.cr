# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Server`, the HTTP server wrapper. It is built on
# top of the standard library's `HTTP::Server` and manages the full server
# lifecycle: binding the configured host and port, installing graceful
# shutdown handlers for `SIGINT` and `SIGTERM`, and blocking until the server
# is closed. The server speaks only to the handler it was given —
# `Altair::Core::RequestHandler`, which runs the application's middleware
# pipeline (logging, static files) around the router.
class Altair::Server
  # The application this server serves.
  getter app : Altair::Application

  # The handler that processes every request.
  getter handler : ::HTTP::Handler

  # The underlying stdlib server.
  getter http_server : ::HTTP::Server

  def initialize(@app : Altair::Application, @handler : ::HTTP::Handler)
    @http_server = ::HTTP::Server.new([@handler])
  end

  # Binds the server to the application's configured host and port, or to
  # the given values. Returns the bound address; the actual port is
  # available through `port` afterwards.
  def bind(host : String = @app.config.host, port : Int32 = @app.config.port) : Socket::IPAddress
    @http_server.bind_tcp(host, port)
  end

  # The port the server is bound to. Available after `bind`, or once
  # `start` has bound the server.
  def port : Int32
    bound_address.port
  end

  # Binds the server (when not already bound), installs signal handlers and
  # blocks until the server is closed — the main entry point used by
  # `Altair::Application#start`.
  def start : Nil
    config = @app.config
    config.logger.info { "Altair #{Altair::VERSION} starting in #{Altair.env} mode" }
    address = bound? ? bound_address : bind
    config.logger.info { "Listening on #{address.address}:#{address.port}" }
    install_signal_handlers
    @http_server.listen
  end

  private def bound? : Bool
    !@http_server.addresses.empty?
  end

  private def bound_address : Socket::IPAddress
    @http_server.addresses.first.as(Socket::IPAddress)
  end

  private def install_signal_handlers
    Process.on_terminate { shutdown }
  end

  private def shutdown
    @http_server.close unless @http_server.closed?
  end
end
