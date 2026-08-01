# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Routing::Router`, the matching engine. It
# answers two questions for every incoming request: which route matches, if
# any, and — when the path exists but the method does not — which methods
# are allowed. Matching walks the request path segment by segment against
# each route's pre-parsed segments, and the first route in definition order
# wins, exactly like conventional routing. `HEAD` requests match `GET`
# routes.
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
    end
  end
end
