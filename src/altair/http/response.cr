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
      # Set once `head` answers the request; every later body write is
      # ignored so a `head` followed by rendering still answers bodyless.
      @body_suppressed = false

      # True once anything was written to the response. The controller
      # dispatcher checks it to halt the chain once a callback answered.
      @written = false

      # The response status, `200 OK` by default. Reads the live status
      # from the underlying stdlib response, so it reflects every change —
      # including ones made through the stdlib object directly.
      def status : ::HTTP::Status
        @response.status
      end

      # True when the response body or a redirect has been written.
      def written? : Bool
        @written
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
        print(data)
      end

      # Sends `data` as an HTML response, setting the `Content-Type` header
      # to `text/html`.
      def html(data : String) : Nil
        @headers["Content-Type"] = "text/html; charset=utf-8"
        print(data)
      end

      # Sends `data` as a plain-text response, setting the `Content-Type`
      # header to `text/plain`.
      def text(data : String) : Nil
        @headers["Content-Type"] = "text/plain; charset=utf-8"
        print(data)
      end

      # Issues an HTTP redirect to `to`, defaulting to status 302 (Found),
      # the conventional redirect status.
      def redirect(to : String, status : ::HTTP::Status = ::HTTP::Status::FOUND) : Nil
        @written = true
        @response.redirect(to, status)
      end

      # Streams a file as the response body. The `Content-Type` is guessed
      # from the file extension and `Content-Length` is set from the file
      # size; the bytes are copied in chunks, so large files are never read
      # whole into memory. With `inline: false` the file is offered as a
      # download through the `Content-Disposition` header.
      def send_file(path : Path, *, inline : Bool = true) : Nil
        @headers["Content-Length"] = File.size(path).to_s
        @headers["Content-Type"] = MIME.from_extension?(path.extension) || "application/octet-stream"
        @headers["Content-Disposition"] = inline ? "inline" : %(attachment; filename="#{path.basename.gsub('\\', "\\\\").gsub('"', "\\\"")}")
        @written = true
        File.open(path, "rb") do |file|
          IO.copy(file, @response.output)
        end
      end

      # Opens the response for streaming. Writing to the returned `IO`
      # sends chunks as they are produced — the building block of large
      # responses and server-sent events. Close the stream when done.
      def stream : IO
        @response.output
      end

      # Answers with the given status and no body. Later body writes are
      # ignored, so a `head` followed by rendering still answers bodyless.
      def head(status : ::HTTP::Status) : Nil
        @body_suppressed = true
        @written = true
        @response.status = status
      end

      # Writes raw data to the response body.
      def print(*objects) : Nil
        unless @body_suppressed
          @written = true
          @response.print(*objects)
        end
      end
    end
  end
end
