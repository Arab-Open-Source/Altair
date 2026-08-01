# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Core::RequestHandler`, the entry point of every
# HTTP request. Requests are dispatched through the application's router:
# the matching route's handler answers, unknown paths become 404 and known
# paths with the wrong method become 405 with an `Allow` header. When the
# application has no routes at all, `/` still answers with the welcome page
# so a fresh project shows something useful before its first route is
# written. The handler also owns the framework's top-level error boundary:
# unexpected exceptions become 500 responses and are logged, keeping the
# server alive instead of crashing.
class Altair::Core::RequestHandler
  include ::HTTP::Handler

  def initialize(@app : Altair::Application)
    @router = Altair::Routing::Router.new(Altair::Routing.route_set_for(@app.class).routes)
  end

  def call(context : ::HTTP::Server::Context) : Nil
    request = Altair::HTTP::Request.new(context.request)
    response = Altair::HTTP::Response.new(context.response)
    begin
      dispatch(request, response)
    rescue exception
      handle_error(context, exception)
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

  private def handle_error(context : ::HTTP::Server::Context, exception : Exception) : Nil
    case exception
    when Altair::HTTP::NotFound
      context.response.status = ::HTTP::Status::NOT_FOUND
      context.response.print("404 Not Found")
    when Altair::HTTP::MethodNotAllowed
      context.response.status = ::HTTP::Status::METHOD_NOT_ALLOWED
      context.response.headers["Allow"] = exception.allowed.join(", ")
      context.response.print("405 Method Not Allowed")
    else
      @app.config.logger.error { "Unhandled #{exception.class}: #{exception.message}" }
      context.response.status = ::HTTP::Status::INTERNAL_SERVER_ERROR
      if @app.config.debug?
        context.response.print(exception.message.to_s)
        exception.backtrace.each do |line|
          context.response.print("\n  " + line)
        end
      else
        context.response.print("500 Internal Server Error")
      end
    end
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
