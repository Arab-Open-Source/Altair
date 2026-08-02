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

      # Fetches the parameter for the given key as a `String`, raising
      # `Altair::HTTP::ParamsError` when the parameter is missing:
      #
      # ```
      # params.fetch("title", String)
      # ```
      def fetch(key : String, type : String.class) : String
        self[key]? || raise ParamsError.new("Missing parameter: #{key}")
      end

      # Fetches the parameter for the given key as an `Int32`, raising
      # `Altair::HTTP::ParamsError` when the parameter is missing or not a
      # whole number. Values are parsed with `to_i?`, so `" 42"` and `"42"` —
      # but not `"4.2"` — are accepted.
      def fetch(key : String, type : Int32.class) : Int32
        value = self[key]?
        raise ParamsError.new("Missing parameter: #{key}") unless value
        value.to_i? || raise ParamsError.new("Expected Int32 for parameter '#{key}', got '#{value}'")
      end

      # Fetches the parameter for the given key as an `Int64`.
      def fetch(key : String, type : Int64.class) : Int64
        value = self[key]?
        raise ParamsError.new("Missing parameter: #{key}") unless value
        value.to_i64? || raise ParamsError.new("Expected Int64 for parameter '#{key}', got '#{value}'")
      end

      # Fetches the parameter for the given key as a `Float64`, raising
      # `Altair::HTTP::ParamsError` when the parameter is missing or not
      # numeric.
      def fetch(key : String, type : Float64.class) : Float64
        value = self[key]?
        raise ParamsError.new("Missing parameter: #{key}") unless value
        value.to_f64? || raise ParamsError.new("Expected Float64 for parameter '#{key}', got '#{value}'")
      end

      # Fetches the parameter for the given key as a `Bool`. The strings
      # `"true"`, `"1"`, `"yes"` and `"on"` (case-insensitive) are `true`; the
      # strings `"false"`, `"0"`, `"no"` and `"off"` are `false`; anything
      # else raises `Altair::HTTP::ParamsError`.
      def fetch(key : String, type : Bool.class) : Bool
        value = self[key]?
        raise ParamsError.new("Missing parameter: #{key}") unless value
        case value.downcase
        when "true", "1", "yes", "on"
          true
        when "false", "0", "no", "off"
          false
        else
          raise ParamsError.new("Expected Bool for parameter '#{key}', got '#{value}'")
        end
      end

      # Fetches the parameter for the given key as a `String`, or returns
      # `nil` when the parameter is missing.
      def fetch?(key : String, type : String.class) : String?
        self[key]?
      end

      # Fetches the parameter for the given key as an `Int32`, or returns
      # `nil` when the parameter is missing or not a whole number.
      def fetch?(key : String, type : Int32.class) : Int32?
        self[key]?.try(&.to_i?)
      end

      # Fetches the parameter for the given key as an `Int64`, or returns
      # `nil` when the parameter is missing or not a whole number.
      def fetch?(key : String, type : Int64.class) : Int64?
        self[key]?.try(&.to_i64?)
      end

      # Fetches the parameter for the given key as a `Float64`, or returns
      # `nil` when the parameter is missing or not numeric.
      def fetch?(key : String, type : Float64.class) : Float64?
        self[key]?.try(&.to_f64?)
      end

      # Fetches the parameter for the given key as a `Bool`, or returns
      # `nil` when the parameter is missing or not a boolean value.
      def fetch?(key : String, type : Bool.class) : Bool?
        return unless value = self[key]?
        case value.downcase
        when "true", "1", "yes", "on"  then true
        when "false", "0", "no", "off" then false
        end
      end

      # Returns every value of a repeated parameter, in order. Useful for
      # multi-select fields: `?tags=a&tags=b` yields `["a", "b"]`.
      def fetch_all(key : String) : Array(String)
        @query.fetch_all(key) + @body.fetch_all(key)
      end

      # Returns `self` when a parameter with the given key exists, raising
      # `KeyError` otherwise. Chains with `permit` to implement the strong
      # params pattern:
      #
      # ```
      # params.require("title")
      # params.require("post").permit("title", "body")
      # ```
      def require(key : String) : self
        raise KeyError.new("Missing parameter: #{key}") unless self[key]?
        self
      end

      # Returns a hash of only the given keys, raising `KeyError` when any
      # of them is missing. Route and query values take precedence over
      # body values, like `to_h`.
      def permit(*keys : String) : Hash(String, String)
        keys.each { |key| self[key] }
        to_h.select { |key, _| keys.includes?(key) }
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
