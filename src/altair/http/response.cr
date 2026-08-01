# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::Response`, the framework's response object.
# It wraps the raw `HTTP::Server::Response` and provides a concise API for
# the most common response types: JSON, HTML, redirects and arbitrary body
# writes. Controllers in later phases will only ever interact with this
# wrapper.
module Altair
  module HTTP
    class Response
      # The response status, `200 OK` by default. Reads the live status
      # from the underlying stdlib response, so it reflects every change —
      # including ones made through the stdlib object directly.
      def status : ::HTTP::Status
        @response.status
      end

      # The response headers.
      getter headers : ::HTTP::Headers

      # Sets the response status, e.g. `response.status = 404` to signal a
      # missing resource.
      def status=(status : ::HTTP::Status) : ::HTTP::Status
        @response.status = status
      end

      def initialize(@response : ::HTTP::Server::Response)
        @headers = @response.headers
      end

      # Sends `data` as a JSON response, setting the `Content-Type` header
      # to `application/json`.
      def json(data : String) : Nil
        @headers["Content-Type"] = "application/json; charset=utf-8"
        @response.print(data)
      end

      # Sends `data` as an HTML response, setting the `Content-Type` header
      # to `text/html`.
      def html(data : String) : Nil
        @headers["Content-Type"] = "text/html; charset=utf-8"
        @response.print(data)
      end

      # Sends `data` as a plain-text response, setting the `Content-Type`
      # header to `text/plain`.
      def text(data : String) : Nil
        @headers["Content-Type"] = "text/plain; charset=utf-8"
        @response.print(data)
      end

      # Issues an HTTP redirect to `to`, defaulting to status 302 (Found),
      # the conventional redirect status.
      def redirect(to : String, status : ::HTTP::Status = ::HTTP::Status::FOUND) : Nil
        @response.redirect(to, status)
      end

      # Writes raw data to the response body.
      def print(*objects) : Nil
        @response.print(*objects)
      end
    end
  end
end
