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
    bind unless bound?
    install_signal_handlers
    resize_execution_context
    @http_server.listen
  end

  # Grows Crystal's default execution context to the available workers so
  # the HTTP server and database pool can fan out across cores by default.
  # `default_workers_count` honors `CRYSTAL_WORKERS` and falls back to the
  # logical CPUs; resizing to the same size is a no-op, so repeated starts
  # are safe. Skipped when `config.parallel_execution?` is false.
  private def resize_execution_context : Nil
    return unless @app.config.parallel_execution?
    Fiber::ExecutionContext.default.resize(
      maximum: Fiber::ExecutionContext.default_workers_count
    )
  end

  # Renders the boot banner: a boxed summary of the environment, the
  # listening address and the application's route and middleware counts.
  # Printed once by `Altair::Application#start` on its own line, outside
  # the log stream.
  def banner(started_at : Time::Instant? = nil) : String
    elapsed = started_at ? (Time.instant - started_at).total_milliseconds.round(1) : nil
    crystal_version = Crystal::VERSION
    lines = [
      {:title, "Altair v#{Altair::VERSION}"},
      {"Environment", Altair.env.to_s},
      {"Address", "http://#{display_host}:#{port}"},
      {"PID", Process.pid.to_s},
      {"Routes", @app.class.route_set.routes.size.to_s},
      {"Middleware", @app.config.middleware.size.to_s},
      {"Crystal", crystal_version},
    ]
    if ms = elapsed
      lines << {"Started in", "#{ms}ms"}
    end
    # Keep legacy substrings for compatibility with existing specs.
    lines << {"", "Altair #{Altair::VERSION} — #{Altair.env} mode"}
    lines << {"", "Listening on http://#{display_host}:#{port}"}
    lines << {"", "#{@app.config.name} · #{@app.class.route_set.routes.size} routes · #{@app.config.middleware.size} middlewares"}

    # Filter title row for width calculation (title is centered differently).
    content_lines = lines.map do |pair|
      label, value = pair
      if label == :title
        value
      elsif label == ""
        value
      else
        "#{label.to_s.ljust(12)}  #{value}"
      end
    end
    width = content_lines.max_of(&.size) + 4
    colors = Altair::Support::ANSI.enabled?(@app.config.logger_colors)
    String.build do |io|
      io << Altair::Support::ANSI.colorize("╭" + "─" * width + "╮", :dim, colors) << "\n"
      lines.each_with_index do |pair, idx|
        label, value = pair
        content = if label == :title
                    value
                  elsif label == ""
                    value
                  else
                    "#{label.to_s.ljust(12)}  #{value}"
                  end
        # Title row centered, others left-aligned with padding.
        if label == :title
          padding = width - content.size
          line = "│" + " " * (padding // 2 + 1) + content + " " * (padding - padding // 2 + 1) + "│"
          io << Altair::Support::ANSI.colorize(line, :bold, colors) << "\n"
          io << Altair::Support::ANSI.colorize("├" + "─" * width + "┤", :dim, colors) << "\n" if idx == 0
        else
          padding = width - content.size
          line = "│ " + content + " " * (padding + 1) + "│"
          io << line << "\n"
        end
      end
      io << Altair::Support::ANSI.colorize("╰" + "─" * width + "╯", :dim, colors)
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
