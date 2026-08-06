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

    # The outcome of a single scan against the route table: a matched route with
    # its parameters, the allowed methods when the path matches but the method
    # does not, or neither. A resolution carries exactly one of `match` and
    # `allowed`.
    struct Resolution
      # The matched route plus params, or `nil` when the method did not match.
      getter match : Match?

      # The methods accepted at a matching path, or `nil` when the method
      # matched (or nothing matched the path).
      getter allowed : Array(String)?

      def initialize(@match : Match?, @allowed : Array(String)?)
      end

      # Whether any route matched the request method.
      def found? : Bool
        !@match.nil?
      end

      # The matched route plus params, raising when the method did not match.
      # The bang form of `match` for callers that know a route matched.
      def match! : Match
        @match.not_nil!
      end
    end

    class Router
      # Shared empty index list for first segments with no literal routes.
      # Never mutated; avoids allocating an empty array per lookup.
      EMPTY_INDICES = [] of Int32

      # Routes grouped by their first segment so matching only tests the
      # candidates that can actually win.
      @literal_index : Hash(String, Array(Int32))
      @param_routes : Array(Int32)
      @glob_routes : Array(Int32)
      @root_routes : Array(Int32)

      # Memoizes successful `find` results so a repeated request path — the
      # common case — collapses to a hash lookup instead of re-walking the
      # route table. Misses are never stored, so a 404 scan cannot evict a
      # hot entry. Sized by the application's `router_cache_size` config.
      @cache : Altair::Support::LRUCache({String, String}, Match)

      def initialize(@routes : Array(Route), cache_size : Int32 = 1024)
        @literal_index = {} of String => Array(Int32)
        @param_routes = [] of Int32
        @glob_routes = [] of Int32
        @root_routes = [] of Int32
        @cache = Altair::Support::LRUCache({String, String}, Match).new(cache_size)
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

      # Yields the route indices that could match `parts`, in definition
      # order, by merging the per-group ascending index lists — no combined
      # array and no sort per request. The groups are: routes whose first
      # segment is the request's literal first segment, every route whose
      # first segment is a parameter, and every route whose first segment is
      # a glob (the segment-less root routes when the path has none). Each
      # group is ascending because indices are assigned in definition order.
      private def each_candidate(parts : PathParts, & : Int32 ->) : Nil
        key = parts.first?
        literal = @literal_index[key]? || EMPTY_INDICES
        params = @param_routes
        globs = key ? @glob_routes : @root_routes

        merge_candidates(literal, params, globs) { |index| yield index }
      end

      # Three-way ascending merge that yields the smallest list head on each
      # step. `Int32::MAX` as the exhausted-list sentinel keeps the step a
      # plain comparison against a constant.
      private def merge_candidates(literal, params, globs, & : Int32 ->) : Nil
        i = 0
        j = 0
        k = 0
        loop do
          li = literal[i]? || Int32::MAX
          pi = params[j]? || Int32::MAX
          gi = globs[k]? || Int32::MAX
          break if li == Int32::MAX && pi == Int32::MAX && gi == Int32::MAX

          if li <= pi && li <= gi
            yield li
            i += 1
          elsif pi <= gi
            yield pi
            j += 1
          else
            yield gi
            k += 1
          end
        end
      end

      # Returns `true` when no routes are registered. Applications without
      # routes fall back to the welcome page.
      def empty? : Bool
        @routes.empty?
      end

      # Resolves a request to a `Resolution`: the matched route and params,
      # or the allowed methods when the path matches but the method does not,
      # or neither on a true miss. A path ending in a `.ext` suffix is first
      # tried with the extension stripped, exposing it as `params["format"]`
      # — so `/posts/5.json` exercises `GET /posts/:id` with `id` = `5` and
      # `format` = `json`. The exact path is tried second, so a literal
      # dotted route such as `/sitemap.xml` still matches unchanged.
      #
      # Successful matches are memoized by `{method, path}`, so repeated
      # requests to a hot path skip the scan and return the cached match —
      # including its extracted params, which callers must not mutate.
      def resolve(method : String, path : String) : Resolution
        key = {method, path}
        if cached = @cache.get(key)
          return Resolution.new(cached, nil)
        end
        resolution = resolve_uncached(method, path)
        if match = resolution.match
          @cache.put(key, match)
        end
        resolution
      end

      # The matched route or `nil`, from a single scan — the convenience form
      # of `resolve` used by callers that only care about the match.
      def find(method : String, path : String) : Match?
        resolve(method, path).match
      end

      # The uncached resolution: split, scan and extract. The format suffix
      # is written into the freshly built params hash here — before the
      # match is cached — so a cached entry never needs mutating.
      private def resolve_uncached(method : String, path : String) : Resolution
        parts = PathParts.new(path)
        if suffix = format_suffix(parts)
          resolution = scan(method, suffix[:parts], skip_glob: true)
          if match = resolution.match
            match.params["format"] = suffix[:format]
            return resolution
          end
        end
        scan(method, parts)
      end

      # One pass over the candidates: returns the first route whose path and
      # method match, or collects the methods of every route whose path
      # matches but whose method does not. `ANY` routes match every method
      # and therefore never appear in the allowed list.
      private def scan(method : String, parts : PathParts, skip_glob : Bool = false) : Resolution
        allowed = nil
        each_candidate(parts) do |index|
          route = @routes[index]
          next if skip_glob && route.glob?
          if method_matches?(route.method, method)
            if params = route.match(parts)
              return Resolution.new(Match.new(route, params), nil)
            end
          elsif route.matches_path?(parts)
            if allowed_list = allowed
              allowed_list << route.method unless allowed_list.includes?(route.method)
            else
              allowed = [route.method]
            end
          end
        end
        Resolution.new(nil, allowed)
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
        each_candidate(parts) do |index|
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
