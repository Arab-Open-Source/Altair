# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Core::ErrorPages`, the development-mode
# renderer for the framework's error responses — the smart error pages.
# When the application runs with debug enabled, they turn every failure
# into a lesson:
#
# * a 404 suggests the routes closest to the requested path, links the
#   clickable ones and shows the exact route line to add (with a copy
#   button) to make the path work;
# * a 405 lists the methods the path accepts and shows how to send the
#   rejected method from a form via `_method`;
# * a 500 renders a full diagnostic: the request context (method, path,
#   parameters, safe headers), the route that was handling it, the
#   exception chain down to the root cause, a source preview highlighting
#   the failing line, and the complete backtrace.
#
# Every page carries an environment strip (application, version, env,
# route count, middleware count) and every echoed value is HTML-escaped;
# sensitive headers such as `Authorization` and `Cookie` are never shown.
# Outside debug mode the framework stays quiet: plain text responses with
# the standard status and `Allow` header, never leaking the application's
# routes.
require "html"

class Altair::Core::ErrorPages
  # Matches a backtrace frame such as `/path/app.cr:42:5 in 'show'`,
  # capturing the source file and line. Frames from libraries and the
  # stdlib are skipped when picking the highlighted snippet.
  BACKTRACE_FRAME = /^(?:from )?(.+?\.cr):(\d+):\d+/

  # Request headers that must never appear on a diagnostic page, even in
  # development.
  SENSITIVE_HEADERS = ["Authorization", "Cookie", "Proxy-Authorization"]

  # How many source lines to show around the failing line.
  SOURCE_PADDING = 3

  def initialize(@router : Altair::Routing::Router, @app : Altair::Application)
  end

  # The 404 page: the requested method and path, routes close enough to
  # have been what the developer meant — each with the route line that
  # would make the requested path work — and the complete route table.
  def not_found(request : Altair::HTTP::Request) : String
    suggestions = @router.closest_to(request.path)
    body = String.build do |io|
      io << "<h1>404 — Not Found</h1>\n"
      io << "<p class=\"sub\">No route matches <code>#{escape(request.method)} #{escape(request.path)}</code>.</p>\n"
      unless suggestions.empty?
        io << "<h2>Did you mean?</h2>\n"
        io << "<ul class=\"suggestions\">\n"
        suggestions.each do |route|
          io << "<li>\n"
          io << "  <span class=\"method\">#{route.method}</span>\n"
          if clickable?(route)
            io << "  <a href=\"#{escape(route.pattern)}\"><code>#{route.pattern}</code></a>\n"
          else
            io << "  <code>#{route.pattern}</code>\n"
          end
          io << "  <span class=\"action\">#{route.action || "handler block"}</span>\n"
          io << "</li>\n"
          io << fix_suggestion(route, request)
        end
        io << "</ul>\n"
      end
      io << "<h2>Route table</h2>\n"
      io << route_table
    end
    page("404 — Not Found", body)
  end

  # The 405 page: the rejected method, the methods the path accepts, and
  # the hidden field that sends the rejected method from a form.
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
      io << "<h2>How to send the right method</h2>\n"
      io << "<p class=\"hint\">Forms only know <code>GET</code> and <code>POST</code>. Add a hidden <code>_method</code> field to send any method:</p>\n"
      io << "<div class=\"fix\"><code>&lt;input type=\"hidden\" name=\"_method\" value=\"#{escape(request.method.downcase)}\"&gt;</code><button class=\"copy\" onclick=\"copyFix(this)\">Copy</button></div>\n"
    end
    page("405 — Method Not Allowed", body)
  end

  # The 500 page: the failing request, the route that was handling it,
  # the exception chain down to the root cause, a source preview with the
  # failing line highlighted, and the complete backtrace.
  def internal_server_error(request : Altair::HTTP::Request, exception : Exception) : String
    body = String.build do |io|
      io << "<h1>500 — Internal Server Error</h1>\n"
      io << "<p class=\"sub\"><code>#{escape(request.method)} #{escape(request.path)}</code> raised <code>#{exception.class}</code>.</p>\n"
      io << request_context(request)
      io << "<h2>Route</h2>\n"
      if route = request.route
        io << "<p><span class=\"method\">#{route.method}</span> <code>#{route.pattern}</code> <span class=\"action\">#{route.action || "handler block"}</span></p>\n"
      else
        io << "<p class=\"hint\">No route matched — the failure happened before routing (a middleware or the request wrapper).</p>\n"
      end
      unless exception.message.nil?
        io << "<h2>Error</h2>\n"
        io << "<pre class=\"error\">#{escape(exception.message.to_s)}</pre>\n"
      end
      chain = exception_chain(exception)
      if chain.size > 1
        io << "<h2>Exception chain</h2>\n"
        io << "<ol class=\"chain\">\n"
        chain.each do |link|
          io << "<li><span class=\"method\">#{link.class}</span><code>#{escape(link.message.to_s)}</code></li>\n"
        end
        io << "</ol>\n"
      end
      if preview = source_preview(exception)
        io << "<h2>Source</h2>\n"
        io << preview
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

  # The route line that would make the requested path work: the request's
  # method (GET for HEAD) with the closest route's action. Shown on the
  # 404 page under each suggestion, copyable with one click.
  private def fix_suggestion(route : Altair::Routing::Route, request : Altair::HTTP::Request) : String
    method = request.method == "HEAD" ? "get" : request.method.downcase
    action = route.action || "pages#index"
    String.build do |io|
      io << "<div class=\"fix\">\n"
      io << "  <code>#{method} \"#{escape(request.path)}\", to: \"#{action}\"</code>\n"
      io << "  <button class=\"copy\" onclick=\"copyFix(this)\">Copy</button>\n"
      io << "</div>\n"
    end
  end

  # Routes whose pattern contains a parameter (`/posts/:id`) cannot be
  # linked from a 404 — there is no value for the placeholder — so they
  # are shown as code instead.
  private def clickable?(route : Altair::Routing::Route) : Bool
    route.pattern.split('/').none?(&.starts_with?(':'))
  end

  # The request context shown on the 500 page: method, path, parameters
  # and the headers that carry no secrets.
  private def request_context(request : Altair::HTTP::Request) : String
    rows = [] of String
    rows << "<tr><td>Method</td><td><code>#{escape(request.method)}</code></td></tr>"
    rows << "<tr><td>Path</td><td><code>#{escape(request.path)}</code></td></tr>"
    params = request.params.to_h.to_a.sort
    if params.empty?
      rows << "<tr><td>Params</td><td>none</td></tr>"
    else
      params.each do |key, value|
        rows << "<tr><td>Params</td><td><code>#{escape(key)}</code> = <code>#{escape(value)}</code></td></tr>"
      end
    end
    request.headers.to_h.to_a.sort.each do |key, values|
      next if SENSITIVE_HEADERS.includes?(key)
      rows << "<tr><td>#{escape(key)}</td><td><code>#{escape(values.join(", "))}</code></td></tr>"
    end
    "<h2>Request</h2>\n<table>\n#{rows.join("\n")}\n</table>\n"
  end

  # The exception and every cause, outermost first.
  private def exception_chain(exception : Exception) : Array(Exception)
    chain = [exception]
    cause = exception.cause
    while cause
      chain << cause
      cause = cause.cause
    end
    chain
  end

  # The first backtrace frame pointing into the application's own source
  # (anything but `lib/` and the stdlib), or `nil` when there is none.
  private def first_project_frame(exception : Exception) : Tuple(String, Int32)?
    exception.backtrace.each do |line|
      next unless match = BACKTRACE_FRAME.match(line)
      path = match[1]
      line_number = match[2].to_i
      next if path.includes?("/lib/") || path.starts_with?("/usr/")
      return {path, line_number} if File.exists?(path)
    end
    nil
  end

  # A highlighted excerpt of the source around the failing line, or `nil`
  # when no project frame is available.
  private def source_preview(exception : Exception) : String?
    frame = first_project_frame(exception)
    return unless frame
    path, line_number = frame
    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
    first = Math.max(1, line_number - SOURCE_PADDING)
    last = Math.min(lines.size, line_number + SOURCE_PADDING)
    String.build do |io|
      io << "<pre class=\"source\">\n"
      (first..last).each do |index|
        content = lines[index - 1]
        if index == line_number
          io << "<span class=\"bad\">#{index.to_s.rjust(4)}  #{escape(content)}</span>\n"
        else
          io << "<span>#{index.to_s.rjust(4)}  #{escape(content)}</span>\n"
        end
      end
      io << "</pre>\n"
      io << "<p class=\"hint\">#{escape(path)}:#{line_number}</p>\n"
    end
  end

  private def route_table : String
    rows = @router.routes.map do |route|
      "<tr><td>#{route.method}</td><td><code>#{route.pattern}</code></td><td>#{route.action || "handler block"}</td></tr>"
    end
    "<table><thead><tr><th>Method</th><th>Path</th><th>Action</th></tr></thead><tbody>#{rows.join}</tbody></table>\n"
  end

  # The shared footer: application, framework version, environment, route
  # count and middleware count — the state of the running application at
  # a glance.
  private def env_strip : String
    String.build do |io|
      io << "<div class=\"meta\">\n"
      io << "  <span>#{escape(@app.config.name)}</span>\n"
      io << "  <span>Altair v#{Altair::VERSION}</span>\n"
      io << "  <span>#{escape(Altair.env.to_s)} — debug on</span>\n"
      io << "  <span>#{@router.routes.size} routes</span>\n"
      io << "  <span>#{@app.config.middleware.size} middleware</span>\n"
      io << "</div>\n"
    end
  end

  private def page(title : String, body : String) : String
    name = @app.config.name
    <<-HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{title} — #{name}</title>
        <style>
          body { font-family: system-ui, sans-serif; background: #f6f8fa; color: #24292f; margin: 0; padding: 48px 24px; }
          .page { max-width: 860px; margin: 0 auto; }
          h1 { margin: 0 0 8px; font-size: 28px; }
          .sub { color: #57606a; margin: 0 0 32px; line-height: 1.6; }
          h2 { font-size: 16px; margin: 32px 0 12px; }
          code { background: #eff1f3; padding: 2px 6px; border-radius: 6px; font-size: 0.9em; }
          a code { color: #0969da; }
          ul { list-style: none; padding: 0; margin: 0; }
          li { display: flex; align-items: center; gap: 12px; padding: 10px 14px; margin-bottom: 8px; background: #fff; border: 1px solid #d0d7de; border-radius: 8px; }
          .method { font-size: 11px; font-weight: 700; letter-spacing: 0.05em; color: #57606a; background: #eff1f3; padding: 4px 8px; border-radius: 999px; }
          .action { margin-left: auto; color: #57606a; font-size: 13px; }
          .fix { display: flex; align-items: center; gap: 12px; background: #fff; border: 1px dashed #d0d7de; border-radius: 8px; padding: 10px 14px; margin: -4px 0 12px 8px; }
          .fix code { background: none; }
          .copy { font-size: 12px; margin-left: auto; background: #eff1f3; border: 1px solid #d0d7de; border-radius: 6px; padding: 4px 10px; cursor: pointer; color: #24292f; }
          .copy:hover { background: #d0d7de; }
          table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #d0d7de; border-radius: 8px; overflow: hidden; }
          th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid #eff1f3; font-size: 14px; vertical-align: top; }
          th { background: #f6f8fa; color: #57606a; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
          tr:last-child td { border-bottom: none; }
          pre.error { background: #fff; border: 1px solid #f0b3b3; border-left: 4px solid #d1242f; padding: 12px 16px; border-radius: 8px; overflow-x: auto; }
          pre.source { background: #fff; border: 1px solid #d0d7de; border-radius: 8px; padding: 12px 16px; overflow-x: auto; line-height: 1.6; }
          pre.source span { display: block; color: #57606a; }
          pre.source span.bad { background: #fff1f0; color: #d1242f; font-weight: 600; margin: 0 -16px; padding: 0 16px; }
          ol.chain, ol.backtrace { list-style: none; padding: 0; margin: 0; }
          ol.chain li, ol.backtrace li { display: flex; align-items: center; gap: 12px; font-size: 13px; padding: 8px 14px; }
          ol.backtrace code { background: none; padding: 0; }
          .hint { color: #57606a; font-size: 13px; margin-top: 24px; }
          .meta { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 32px; font-size: 13px; }
          .meta span { background: #eff1f3; padding: 6px 12px; border-radius: 999px; color: #57606a; }
        </style>
      </head>
      <body>
        <div class="page">
        #{body}
        #{env_strip}
        </div>
        <script>
          function copyFix(button) {
            var code = button.parentElement.querySelector("code").textContent;
            var done = function () {
              button.textContent = "Copied";
              setTimeout(function () { button.textContent = "Copy"; }, 1500);
            };
            if (navigator.clipboard) {
              navigator.clipboard.writeText(code).then(done);
            } else {
              var area = document.createElement("textarea");
              area.value = code;
              document.body.appendChild(area);
              area.select();
              document.execCommand("copy");
              document.body.removeChild(area);
              done();
            }
          }
        </script>
      </body>
      </html>
      HTML
  end

  private def escape(text : String) : String
    HTML.escape(text)
  end
end
