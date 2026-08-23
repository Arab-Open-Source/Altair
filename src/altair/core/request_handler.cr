# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Core::RequestHandler`, the entry point of every
# HTTP request. It wraps the raw stdlib context in the framework's request
# and response objects, runs the application's middleware stack — the
# configured pipeline, ending with the router itself — and owns the
# framework's top-level error boundary: unexpected exceptions become 500
# responses and are logged, keeping the server alive instead of crashing.
#
# Routing dispatches the matching route's handler: unknown paths become
# 404 and known paths with the wrong method become 405 with an `Allow`
# header. With debug enabled, the error responses are full pages — route
# suggestions, the route table and backtraces — rendered by
# `Altair::Core::ErrorPages`; otherwise they stay plain text. When the
# application has no routes at all, `/` still answers with the welcome page
# so a fresh project shows something useful before its first route is
# written.
class Altair::Core::RequestHandler
  include ::HTTP::Handler

  @chain : Proc(Altair::HTTP::Request, Altair::HTTP::Response, Nil)

  def initialize(@app : Altair::Application)
    @router = Altair::Routing::Router.new(
      Altair::Routing.route_set_for(@app.class).routes,
      cache_size: @app.config.router_cache_size
    )
    @chain = build_chain
    Altair::Record::NDetector.enable(Altair.env, @app.config.detect_n_plus_one?, @app.config.n_plus_one_threshold)
    Altair::Record::PermitGate.enable(admission_limit, @app.config.db_admission_timeout)
  end

  # The configured admission gate limit, clamped to the pool's maximum. A
  # gate wider than the pool caps nothing (the pool is the real limit), so
  # the documented behavior is to clamp rather than boot with a meaningless
  # bound.
  private def admission_limit : Int32
    configured = @app.config.db_max_active_queries
    pool = @app.config.db_max_pool_size
    if configured > 0 && pool > 0 && configured > pool
      @app.config.logger.info do
        "clamping db_max_active_queries=#{configured} to db_max_pool_size=#{pool}"
      end
      pool
    else
      configured
    end
  end

  def call(context : ::HTTP::Server::Context) : Nil
    Altair::Record::NDetector.begin_request
    request = nil
    response = nil
    started = Time.instant
    begin
      request = Altair::HTTP::Request.new(context.request, max_body_size: @app.config.max_body_size)
      response = Altair::HTTP::Response.new(context.response)
      @chain.call(request, response)
    rescue exception
      handle_error(context, request, exception)
    ensure
      Altair::Record::NDetector.end_request
      if @app.config.observability?
        Altair::Observability.metrics.record(context.response.status.value, Time.instant - started)
      end
    end
  end

  # Composes the configured middleware stack around the router dispatch.
  # The stack is wrapped inside out, so the first configured middleware
  # runs first, and the final link is the router itself. Factories build
  # each middleware once, when the handler is created.
  private def build_chain : Proc(Altair::HTTP::Request, Altair::HTTP::Response, Nil)
    final = ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) { dispatch(request, response) }
    @app.config.middleware.reverse.reduce(final) do |inner, factory|
      middleware = factory.call(@app)
      ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) {
        middleware.call(request, response, -> { inner.call(request, response) })
      }
    end
  end

  private def dispatch(request : Altair::HTTP::Request, response : Altair::HTTP::Response) : Nil
    if @app.config.observability? && request.path == @app.config.health_path
      response.json(%({"status":"ok"}))
    elsif @app.config.observability? && request.path == @app.config.metrics_path
      response.headers["Content-Type"] = "text/plain; version=0.0.4; charset=utf-8"
      response.print(Altair::Observability.metrics.to_prometheus)
    elsif @router.empty? && request.path == "/"
      render_welcome(response)
    else
      resolution = @router.resolve(effective_method(request), request.path)
      if match = resolution.match
        request.route_params = match.params
        request.route = match.route
        match.route.handler.call(request, response)
      elsif allowed = resolution.allowed
        raise Altair::HTTP::MethodNotAllowed.new(allowed)
      else
        raise Altair::HTTP::NotFound.new
      end
    end
  end

  private def render_welcome(response : Altair::HTTP::Response) : Nil
    response.html(welcome_page)
  end

  private def effective_method(request : Altair::HTTP::Request) : String
    return request.method unless request.method == "POST"
    case request.params["_method"]?.try(&.upcase)
    when "PUT", "PATCH", "DELETE"
      request.params["_method"].upcase
    else
      request.method
    end
  end

  private def handle_error(context : ::HTTP::Server::Context, request : Altair::HTTP::Request?, exception : Exception) : Nil
    case exception
    when Altair::HTTP::NotFound
      context.response.status = ::HTTP::Status::NOT_FOUND
      if @app.config.debug? && request
        render_debug_error(context, Altair::Core::ErrorPages.new(@router, @app).not_found(request))
      else
        context.response.print("404 Not Found")
      end
    when Altair::HTTP::PayloadTooLarge
      context.response.status = ::HTTP::Status::PAYLOAD_TOO_LARGE
      context.response.print("413 Payload Too Large")
    when Altair::HTTP::MethodNotAllowed
      context.response.status = ::HTTP::Status::METHOD_NOT_ALLOWED
      context.response.headers["Allow"] = exception.allowed.join(", ")
      if @app.config.debug? && request
        render_debug_error(context, Altair::Core::ErrorPages.new(@router, @app).method_not_allowed(request, exception.allowed))
      else
        context.response.print("405 Method Not Allowed")
      end
    when Altair::HTTP::Error
      context.response.status = exception.status
      context.response.print(exception.message || "Error")
    else
      return if handle_rescued(exception, request, context)
      log_error(request, exception)
      context.response.status = ::HTTP::Status::INTERNAL_SERVER_ERROR
      if @app.config.debug? && request
        render_debug_error(context, Altair::Core::ErrorPages.new(@router, @app).internal_server_error(request, exception))
      else
        context.response.print("500 Internal Server Error")
      end
    end
  end

  private def log_error(request : Altair::HTTP::Request?, exception : Exception) : Nil
    colors = Altair::Support::ANSI.enabled?(@app.config.logger_colors)
    @app.config.logger.error do
      String.build do |io|
        io << "\n" << Altair::Support::ANSI.colorize("─" * 50, :dim, colors) << "\n\n"
        io << Altair::Support::ANSI.colorize("500 Internal Server Error", :red, colors) << "\n\n"
        if req = request
          io << Altair::Support::ANSI.colorize("Route", :bold, colors) << "\n"
          io << "#{req.method} #{req.path}\n\n"
          if route = req.route
            if action = route.action
              io << Altair::Support::ANSI.colorize("Controller", :bold, colors) << "\n"
              io << "#{action}\n\n"
            end
          end
        end
        io << Altair::Support::ANSI.colorize("Exception", :bold, colors) << "\n"
        io << "#{exception.class}\n\n"
        if message = exception.message
          io << Altair::Support::ANSI.colorize("Message", :bold, colors) << "\n"
          io << "#{message}\n\n"
        end
        if loc = exception_location(exception)
          io << Altair::Support::ANSI.colorize("Location", :bold, colors) << "\n"
          io << "#{loc}\n\n"
        end
        io << Altair::Support::ANSI.colorize("─" * 50, :dim, colors)
      end
    end
  end

  private def exception_location(exception : Exception) : String?
    if trace = exception.backtrace?
      trace.each do |frame|
        if match = frame.match(/^(?:from )?(.+?\.cr):(\d+):\d+/)
          path = match[1]
          line = match[2]
          next if path.includes?("/lib/")
          next if path.includes?("src/crystal/")
          return "#{path}:#{line}"
        end
      end
      trace.first?
    end
  end

  # Consults the application's `rescue_from` registrations. Returns `true`
  # when a registration matched and answered the request; the response is
  # written through the registration's status or handler. Registrations
  # are checked in declaration order.
  private def handle_rescued(exception : Exception, request : Altair::HTTP::Request?, context : ::HTTP::Server::Context) : Bool
    Altair::Core::ErrorHandlers.registrations(@app.class).each do |registration|
      klass = registration.exception_class
      next unless exception.class <= klass
      if status = registration.status
        context.response.status = status
        context.response.print(exception.message || "Error")
      elsif handler = registration.handler
        handler.call(@app, exception, request, Altair::HTTP::Response.new(context.response))
      end
      return true
    end
    false
  end

  private def render_debug_error(context : ::HTTP::Server::Context, body : String) : Nil
    context.response.headers["Content-Type"] = "text/html; charset=utf-8"
    context.response.print(body)
  end

  private def welcome_page : String
    name = @app.config.name
    version = Altair::VERSION
    env = Altair.env.to_s
    root = @app.root.to_s
    <<-HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Welcome to #{name}</title>
        <style>
          body { font-family: system-ui, sans-serif; background: #f6f8fa; color: #24292f; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
          .card { background: #fff; border: 1px solid #d0d7de; border-radius: 12px; padding: 48px 56px; max-width: 520px; box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2); text-align: center; }
          h1 { margin: 0 0 8px; font-size: 28px; }
          p { color: #57606a; line-height: 1.6; }
          code { background: #eff1f3; padding: 2px 6px; border-radius: 6px; font-size: 0.9em; }
          .meta { display: flex; gap: 12px; justify-content: center; margin-top: 24px; font-size: 13px; }
          .meta span { background: #eff1f3; padding: 6px 12px; border-radius: 999px; color: #57606a; }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Welcome to #{name}</h1>
          <p>You are riding Altair — the batteries-included web framework for Crystal.</p>
          <p><code>config/application.cr</code> is where your application lives.</p>
          <div class="meta">
            <span>Altair v#{version}</span>
            <span>#{env}</span>
            <span>#{root}</span>
          </div>
        </div>
      </body>
      </html>
      HTML
  end
end
