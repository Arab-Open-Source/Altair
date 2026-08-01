# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::Params`, the unified request-parameter
# bag. In Phase 0 it merges query-string and form-body parameters; route
# parameters are merged in from the router in a later phase. Lookups follow
# the conventional precedence: route params first, then the query string,
# then the body.
module Altair
  module HTTP
    class Params
      @route = Hash(String, String).new
      @query : URI::Params
      @body : URI::Params

      def initialize(@query : URI::Params, @body : URI::Params = URI::Params.new)
      end

      # Returns the parameter value for the given key, or raises `KeyError`
      # when no parameter with that key exists.
      def [](key : String) : String
        self[key]? || raise KeyError.new("Missing parameter: #{key}")
      end

      # Returns the parameter value for the given key, or `nil` when no
      # parameter with that key exists.
      def []?(key : String) : String?
        @route[key]? || @query[key]? || @body[key]?
      end

      # Returns `true` when a parameter with the given key exists.
      def has_key?(key : String) : Bool
        !self[key]?.nil?
      end

      # Returns all parameters as a plain `Hash`, body values taking
      # precedence over query values and route values over both.
      def to_h : Hash(String, String)
        merged = @query.to_h
        @body.to_h.each { |key, value| merged[key] = value }
        @route.each { |key, value| merged[key] = value }
        merged
      end

      # Merges route parameters (extracted by the router from the URL path)
      # into this bag. Used by the router in a later phase.
      def merge_route(route_params : Hash(String, String)) : self
        @route.merge!(route_params)
        self
      end
    end
  end
end
