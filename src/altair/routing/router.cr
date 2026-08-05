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
      # Routes grouped by their first segment so matching only tests the
      # candidates that can actually win.
      @literal_index : Hash(String, Array(Int32))
      @param_routes : Array(Int32)
      @glob_routes : Array(Int32)
      @root_routes : Array(Int32)

      def initialize(@routes : Array(Route))
        @literal_index = {} of String => Array(Int32)
        @param_routes = [] of Int32
        @glob_routes = [] of Int32
        @root_routes = [] of Int32
        index_routes
      end

      # The registered routes, in definition order.
      getter routes : Array(Route)

      # Retrieves the routes worth testing against a request by looking up
      # its first segment: routes whose first segment is that literal, plus
      # every route whose first segment is a parameter or a glob (both
      # accept any single leading segment), plus the segment-less root
      # routes. All groups are ascending index lists, so the merged result
      # preserves definition order.
      private def index_routes : Nil
        @routes.each_with_index do |route, index|
          case route.segments.first?.try(&.kind)
          when Segment::Kind::Static
            (@literal_index[route.segments.first.not_nil!.value] ||= [] of Int32) << index
          when Segment::Kind::Param
            @param_routes << index
          when Segment::Kind::Glob
            @glob_routes << index
          else
            @root_routes << index
          end
        end
      end

      # The route indices that could match `parts`, in definition order.
      private def candidates(parts : PathParts) : Array(Int32)
        key = parts.first?
        literal = @literal_index[key]? || [] of Int32
        (literal + @param_routes + (key ? @glob_routes : @root_routes)).sort!
      end

      # Returns `true` when no routes are registered. Applications without
      # routes fall back to the welcome page.
      def empty? : Bool
        @routes.empty?
      end

      # Finds the first route matching the given method and path, returning
      # the match with its extracted parameters, or `nil` when nothing
      # matches. A path ending in a `.ext` suffix is first tried with the
      # extension stripped, exposing it as `params["format"]` — so
      # `/posts/5.json` exercises `GET /posts/:id` with `id` = `5` and
      # `format` = `json`. The exact path is tried second, so a literal
      # dotted route such as `/sitemap.xml` still matches unchanged.
      def find(method : String, path : String) : Match?
        parts = PathParts.new(path)
        if suffix = format_suffix(parts)
          if match = scan(method, suffix[:parts], skip_glob: true)
            match.params["format"] = suffix[:format]
            return match
          end
        end
        scan(method, parts)
      end

      private def scan(method : String, parts : PathParts, skip_glob : Bool = false) : Match?
        candidates(parts).each do |index|
          route = @routes[index]
          next if skip_glob && route.glob?
          next unless method_matches?(route.method, method)
          if params = route.match(parts)
            return Match.new(route, params)
          end
        end
        nil
      end

      # Splits a trailing `.{ext}` off the last path part, returning the
      # shortened parts and the extension value. Returns `nil` when the
      # last part contains no dot or the extension is empty.
      private def format_suffix(parts : PathParts) : NamedTuple(parts: PathParts, format: String)?
        last = parts.parts.last?
        return unless last
        dot = last.rindex('.')
        return unless dot
        return if dot == last.size - 1
        shortened = parts.parts.dup
        shortened[-1] = last[0...dot]
        {parts: PathParts.new(shortened.join('/')), format: last[dot + 1..]}
      end

      # Returns the list of methods accepted by the given path, when the
      # path matches at least one route but the requested method does not,
      # or `nil` when the path matches nothing. Routes registered under
      # `ANY` (redirects) match every method and are never listed.
      def allowed_for(path : String) : Array(String)?
        parts = PathParts.new(path)
        methods = [] of String
        candidates(parts).each do |index|
          route = @routes[index]
          next if route.method == "ANY"
          next unless route.matches_path?(parts)
          methods << route.method unless methods.includes?(route.method)
        end
        methods.empty? ? nil : methods
      end

      private def method_matches?(route_method : String, request_method : String) : Bool
        route_method == "ANY" ||
          route_method == request_method ||
          (route_method == "GET" && request_method == "HEAD")
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
