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
    address = bound? ? bound_address : bind
    install_signal_handlers
    @http_server.listen
  end

  # Renders the boot banner: a boxed summary of the environment, the
  # listening address and the application's route and middleware counts.
  # Printed once by `Altair::Application#start` on its own line, outside
  # the log stream.
  def banner : String
    lines = [
      "Altair #{Altair::VERSION} — #{Altair.env} mode",
      "Listening on http://#{display_host}:#{port}",
      "#{@app.config.name} · #{@app.class.route_set.routes.size} routes · #{@app.config.middleware.size} middlewares",
    ]
    width = lines.max_of(&.size) + 4
    String.build do |io|
      io << "╭" << "─" * width << "╮\n"
      lines.each do |line|
        padding = width - line.size
        io << "│" << " " * (padding // 2 + 1) << line << " " * (padding - padding // 2 + 1) << "│\n"
      end
      io << "╰" << "─" * width << "╯"
    end
  end

  private def bound? : Bool
    !@http_server.addresses.empty?
  end

  private def display_host : String
    @app.config.host == "0.0.0.0" ? "localhost" : @app.config.host
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
