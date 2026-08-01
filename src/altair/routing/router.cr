# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Routing::Router`, the matching engine. It
# answers two questions for every incoming request: which route matches, if
# any, and — when the path exists but the method does not — which methods
# are allowed. Matching walks the request path segment by segment against
# each route's pre-parsed segments, and the first route in definition order
# wins, exactly like conventional routing. `HEAD` requests match `GET`
# routes. For development, `closest_to` ranks registered patterns by edit
# distance so the error pages can suggest what the developer may have meant.
require "levenshtein"
require "set"

module Altair
  module Routing
    # A successful match: the matched route plus the parameter values
    # extracted from the path.
    struct Match
      # The matched route.
      getter route : Route

      # The parameter values extracted from the path.
      getter params : Hash(String, String)

      def initialize(@route : Route, @params : Hash(String, String))
      end
    end

    class Router
      def initialize(@routes : Array(Route))
      end

      # The registered routes, in definition order.
      getter routes : Array(Route)

      # Returns `true` when no routes are registered. Applications without
      # routes fall back to the welcome page.
      def empty? : Bool
        @routes.empty?
      end

      # Finds the first route matching the given method and path, returning
      # the match with its extracted parameters, or `nil` when nothing
      # matches.
      def find(method : String, path : String) : Match?
        parts = PathParts.new(path)
        @routes.each do |route|
          next unless method_matches?(route.method, method)
          if params = route.match(parts)
            return Match.new(route, params)
          end
        end
        nil
      end

      # Returns the list of methods accepted by the given path, when the
      # path matches at least one route but the requested method does not,
      # or `nil` when the path matches nothing.
      def allowed_for(path : String) : Array(String)?
        parts = PathParts.new(path)
        methods = [] of String
        @routes.each do |route|
          next unless route.matches_path?(parts)
          methods << route.method unless methods.includes?(route.method)
        end
        methods.empty? ? nil : methods
      end

      private def method_matches?(route_method : String, request_method : String) : Bool
        route_method == request_method || (route_method == "GET" && request_method == "HEAD")
      end

      # Returns up to `limit` registered routes whose patterns most closely
      # resemble the given path, ranked by similarity. Param segments count
      # as wildcards, so `/posts/5` is close to `/posts/:id`. Used by the
      # development error pages to suggest routes the developer may have
      # meant. Returns an empty array when nothing is close enough.
      def closest_to(path : String, limit : Int32 = 3) : Array(Route)
        seen = Set(String).new
        candidates = @routes.map { |route| {route, distance(route.segments, path)} }
          .select { |_, distance| distance <= 3 }
          .sort_by! { |_, distance| distance }
        candidates.map { |route, _| route }
          .select { |route| seen.add?(route.pattern) }
          .first(limit)
      end

      # The edit distance between a route's parsed segments and a request
      # path. Segments are compared one to one; param segments count as
      # wildcards. Patterns with a different number of segments are never
      # considered close, so `/posts` is not close to `/posts/:id`.
      private def distance(segments : Array(Segment), path : String) : Int32
        parts = PathParts.new(path)
        return Int32::MAX unless segments.size == parts.size
        segments.zip(parts.parts).sum do |segment, part|
          segment.param? ? 0 : Levenshtein.distance(segment.value, part)
        end
      end
    end
  end
end
