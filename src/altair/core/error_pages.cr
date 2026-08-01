# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Core::ErrorPages`, the development-mode
# renderer for the framework's error responses. When the application runs
# with debug enabled, a 404 shows the closest matching routes as "Did you
# mean?" suggestions plus the full route table, a 405 lists the methods the
# path accepts, and a 500 renders the exception with its backtrace — all in
# the same visual family as the welcome page. Outside debug mode the
# framework stays quiet: plain text responses with the standard status and
# `Allow` header, never leaking the application's routes.
require "html"

class Altair::Core::ErrorPages
  def initialize(@router : Altair::Routing::Router, @app : Altair::Application)
  end

  # The 404 page: the requested method and path, routes close enough to
  # have been what the developer meant, and the complete route table.
  def not_found(request : Altair::HTTP::Request) : String
    body = String.build do |io|
      io << "<h1>404 — Not Found</h1>\n"
      io << "<p class=\"sub\">No route matches <code>#{escape(request.method)} #{escape(request.path)}</code>.</p>\n"
      suggestions = @router.closest_to(request.path)
      unless suggestions.empty?
        io << "<h2>Did you mean?</h2>\n"
        io << "<ul class=\"suggestions\">\n"
        suggestions.each do |route|
          io << "<li><span class=\"method\">#{route.method}</span><code>#{route.pattern}</code><span class=\"action\">#{route.action || "handler block"}</span></li>\n"
        end
        io << "</ul>\n"
      end
      io << "<h2>Route table</h2>\n"
      io << route_table
    end
    page("404 — Not Found", body)
  end

  # The 405 page: the rejected method, the methods the path accepts, and a
  # hint about the `_method` override for form submissions.
  def method_not_allowed(request : Altair::HTTP::Request, allowed : Array(String)) : String
    body = String.build do |io|
      io << "<h1>405 — Method Not Allowed</h1>\n"
      io << "<p class=\"sub\"><code>#{escape(request.method)}</code> is not accepted for <code>#{escape(request.path)}</code>.</p>\n"
      io << "<h2>This path accepts</h2>\n"
      io << "<ul class=\"suggestions\">\n"
      allowed.each do |method|
        io << "<li><span class=\"method\">#{method}</span></li>\n"
      end
      io << "</ul>\n"
      io << "<p class=\"hint\">Forms can send any method with a <code>_method</code> hidden field.</p>\n"
    end
    page("405 — Method Not Allowed", body)
  end

  # The 500 page: the failing request, the exception and its backtrace.
  def internal_server_error(request : Altair::HTTP::Request, exception : Exception) : String
    body = String.build do |io|
      io << "<h1>500 — Internal Server Error</h1>\n"
      io << "<p class=\"sub\"><code>#{escape(request.method)} #{escape(request.path)}</code> raised <code>#{exception.class}</code>.</p>\n"
      unless exception.message.nil?
        io << "<pre class=\"error\">#{escape(exception.message.to_s)}</pre>\n"
      end
      io << "<h2>Backtrace</h2>\n"
      io << "<ol class=\"backtrace\">\n"
      exception.backtrace.each do |line|
        io << "<li><code>#{escape(line)}</code></li>\n"
      end
      io << "</ol>\n"
    end
    page("500 — Internal Server Error", body)
  end

  private def route_table : String
    rows = @router.routes.map do |route|
      "<tr><td>#{route.method}</td><td><code>#{route.pattern}</code></td><td>#{route.action || "handler block"}</td></tr>"
    end
    "<table><thead><tr><th>Method</th><th>Path</th><th>Action</th></tr></thead><tbody>#{rows.join}</tbody></table>\n"
  end

  private def page(title : String, body : String) : String
    name = @app.config.name
    version = Altair::VERSION
    env = Altair.env.to_s
    <<-HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{title} — #{name}</title>
        <style>
          body { font-family: system-ui, sans-serif; background: #f6f8fa; color: #24292f; margin: 0; padding: 48px 24px; }
          .page { max-width: 760px; margin: 0 auto; }
          h1 { margin: 0 0 8px; font-size: 28px; }
          .sub { color: #57606a; margin: 0 0 32px; line-height: 1.6; }
          h2 { font-size: 16px; margin: 32px 0 12px; }
          code { background: #eff1f3; padding: 2px 6px; border-radius: 6px; font-size: 0.9em; }
          ul { list-style: none; padding: 0; margin: 0; }
          li { display: flex; align-items: center; gap: 12px; padding: 10px 14px; margin-bottom: 8px; background: #fff; border: 1px solid #d0d7de; border-radius: 8px; }
          .method { font-size: 11px; font-weight: 700; letter-spacing: 0.05em; color: #57606a; background: #eff1f3; padding: 4px 8px; border-radius: 999px; }
          .action { margin-left: auto; color: #57606a; font-size: 13px; }
          table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #d0d7de; border-radius: 8px; overflow: hidden; }
          th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid #eff1f3; font-size: 14px; }
          th { background: #f6f8fa; color: #57606a; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
          tr:last-child td { border-bottom: none; }
          pre.error { background: #fff; border: 1px solid #f0b3b3; border-left: 4px solid #d1242f; padding: 12px 16px; border-radius: 8px; overflow-x: auto; }
          .backtrace li { display: block; font-size: 13px; padding: 8px 14px; }
          .backtrace code { background: none; padding: 0; }
          .hint { color: #57606a; font-size: 13px; margin-top: 24px; }
          .meta { display: flex; gap: 12px; margin-top: 32px; font-size: 13px; }
          .meta span { background: #eff1f3; padding: 6px 12px; border-radius: 999px; color: #57606a; }
        </style>
      </head>
      <body>
        <div class="page">
        #{body}
        <div class="meta">
          <span>#{name}</span>
          <span>Altair v#{version}</span>
          <span>#{env} — debug on</span>
        </div>
        </div>
      </body>
      </html>
      HTML
  end

  private def escape(text : String) : String
    HTML.escape(text)
  end
end
