# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware::Static`, the static-file server. It
# serves files from the application's `public/` directory for GET and HEAD
# requests, mapping the content type from the file extension and letting
# every other request fall through to the router:
#
# | Request | Result |
# |---|---|
# | `GET /css/app.css` (file exists) | the file, with its content type |
# | `GET /missing.css` | falls through to routing (a 404) |
# | `POST /css/app.css` | falls through to routing |
# | `GET /../config/application.cr` | rejected, falls through to routing |
#
# Paths are checked before serving: only plain relative segments are
# accepted, so a request can never escape the `public/` directory.
require "mime"

class Altair::Middleware::Static < Altair::Middleware
  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    if (request.method == "GET" || request.method == "HEAD") && (file = resolve(request.path)) && File.file?(file)
      serve(file, response)
    else
      chain.call
    end
  end

  # Maps a request path to a file inside `<app root>/public`, or returns
  # `nil` when the path cannot name a file there. Requests with parent
  # segments (`..`) or absolute paths are rejected outright.
  private def resolve(path : String) : Path?
    return unless path.starts_with?("/")
    return if path.includes?('\0')
    return if path.split('/').any? { |segment| segment == ".." }
    Path.new((@app.root / "public").to_s + path)
  end

  private def serve(file : Path, response : Altair::HTTP::Response) : Nil
    content_type = MIME.from_extension?(file.extension) || "application/octet-stream"
    response.headers["Content-Type"] = content_type
    response.status = ::HTTP::Status::OK
    response.print(File.read(file))
  end
end
