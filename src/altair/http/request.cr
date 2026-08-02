# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::Request`, the framework's request object.
# It wraps the raw `HTTP::Request` from the standard library and exposes a
# stable, framework-owned API: method, path, headers, body and an
# `Altair::HTTP::Params` bag holding query-string parameters merged with
# form-body parameters (and, once the router has matched, route
# parameters). Controllers and views in later phases will only ever see
# this wrapper, never the underlying stdlib object, which keeps the
# framework free to evolve its request model without breaking applications.
module Altair
  module HTTP
    class Request
      # The HTTP method of the request, uppercased (`"GET"`, `"POST"`, ...).
      getter method : String

      # The path component of the request URL, without the query string.
      getter path : String

      # The path component including the query string.
      getter full_path : String

      # The request headers.
      getter headers : ::HTTP::Headers

      # The request body as a `String`, or `nil` when the request has none.
      getter body : String?

      # The raw query-string parameters.
      getter query_params : URI::Params

      # The unified parameter bag: query parameters merged with form-body
      # parameters and, after routing, route parameters.
      getter params : Altair::HTTP::Params

      # The route that matched this request, assigned by the router just
      # before the route's handler runs; `nil` until then. The debug error
      # pages use it to report which route was handling a failing request.
      property route : Altair::Routing::Route?

      # True when the request was issued by htmx (the `HX-Request` header
      # is present), letting actions answer with a fragment instead of a
      # full page:
      #
      # ```
      # def index : Nil
      #   render :index, layout: !request.hx_request?
      # end
      # ```
      def hx_request? : Bool
        @headers["HX-Request"]? == "true"
      end

      def initialize(@request : ::HTTP::Request, max_body_size : Int64? = nil)
        @method = @request.method.to_s
        @path = @request.uri.path
        @full_path = @request.resource
        @headers = @request.headers
        @body = read_body(@request.body, max_body_size)
        @query_params = @request.query_params
        @params = Altair::HTTP::Params.new(@query_params, form_params)
      end

      # Reads the request body up to `limit` bytes, raising
      # `Altair::HTTP::PayloadTooLarge` when the body exceeds it. A `nil`
      # limit reads the body without any bound. The check applies to
      # chunked requests too — the body is read through a `IO::Sized`
      # wrapper, never trusting the `Content-Length` header.
      private def read_body(io : IO?, limit : Int64?) : String?
        return unless io
        return io.gets_to_end unless limit
        body = IO::Sized.new(io, limit + 1).gets_to_end
        raise Altair::HTTP::PayloadTooLarge.new if body.size > limit
        body
      end

      # Parses the body as form parameters when the request is a
      # `application/x-www-form-urlencoded` submission.
      private def form_params : URI::Params
        return URI::Params.new unless body = @body
        content_type = @headers["Content-Type"]?
        return URI::Params.new unless content_type.try(&.starts_with?("application/x-www-form-urlencoded"))
        URI::Params.parse(body)
      rescue URI::Error
        URI::Params.new
      end
    end
  end
end
