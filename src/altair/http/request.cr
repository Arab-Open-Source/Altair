# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::Request`, the framework's request object.
# It wraps the raw `HTTP::Request` from the standard library and exposes a
# stable, framework-owned API: method, path, headers, body and an
# `Altair::HTTP::Params` bag. Controllers and views in later phases will only
# ever see this wrapper, never the underlying stdlib object, which keeps the
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
      # parameters (and, later, route parameters).
      getter params : Altair::HTTP::Params

      def initialize(@request : ::HTTP::Request)
        @method = @request.method.to_s
        @path = @request.uri.path
        @full_path = @request.resource
        @headers = @request.headers
        @body = @request.body.try(&.gets_to_end)
        @query_params = @request.query_params
        @params = Altair::HTTP::Params.new(@query_params)
      end
    end
  end
end
