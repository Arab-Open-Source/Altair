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
    @router = Altair::Routing::Router.new(Altair::Routing.route_set_for(@app.class).routes)
    @chain = build_chain
  end

  def call(context : ::HTTP::Server::Context) : Nil
    request = nil
    begin
      request = Altair::HTTP::Request.new(context.request, max_body_size: @app.config.max_body_size)
      response = Altair::HTTP::Response.new(context.response)
      @chain.call(request, response)
    rescue exception
      handle_error(context, request, exception)
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
    if @router.empty? && request.path == "/"
      render_welcome(response)
    else
      match = @router.find(effective_method(request), request.path)
      if match.nil?
        if allowed = @router.allowed_for(request.path)
          raise Altair::HTTP::MethodNotAllowed.new(allowed)
        end
        raise Altair::HTTP::NotFound.new
      end
      request.params.merge_route(match.params)
      request.route = match.route
      match.route.handler.call(request, response)
    end
  end

  private def render_welcome(response : Altair::HTTP::Response) : Nil
    response.html(welcome_page)
  end

  private def effective_method(request : Altair::HTTP::Request) : String
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
    else
      @app.config.logger.error { "Unhandled #{exception.class}: #{exception.message}" }
      context.response.status = ::HTTP::Status::INTERNAL_SERVER_ERROR
      if @app.config.debug? && request
        render_debug_error(context, Altair::Core::ErrorPages.new(@router, @app).internal_server_error(request, exception))
      else
        context.response.print("500 Internal Server Error")
      end
    end
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
