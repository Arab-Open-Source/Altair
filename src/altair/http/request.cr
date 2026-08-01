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

      def initialize(@request : ::HTTP::Request)
        @method = @request.method.to_s
        @path = @request.uri.path
        @full_path = @request.resource
        @headers = @request.headers
        @body = @request.body.try(&.gets_to_end)
        @query_params = @request.query_params
        @params = Altair::HTTP::Params.new(@query_params, form_params)
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
