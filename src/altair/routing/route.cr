# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Routing::Route`, a single registered route: the
# HTTP method, the URL pattern, the controller action it dispatches to, its
# optional name (used by named path helpers) and the handler that answers
# requests. The pattern is parsed once at registration time into segments,
# so matching a request walks pre-built segments instead of compiling
# regular expressions per request.
module Altair
  module Routing
    struct Route
      # The handler signature: every handler receives the framework's
      # request and response wrappers and returns `Nil`.
      alias Handler = Proc(Altair::HTTP::Request, Altair::HTTP::Response, Nil)

      # The HTTP method, uppercased (`"GET"`, `"POST"`, ...).
      getter method : String

      # The URL pattern as written in the DSL, e.g. `/posts/:id`.
      getter pattern : String

      # The pattern parsed into segments, built once at registration.
      getter segments : Array(Segment)

      # The controller action this route dispatches to, e.g.
      # `"posts#show"`. `nil` for block-based handlers.
      getter action : String?

      # The named-route helper name, e.g. `"post_path"`. `nil` for
      # anonymous routes.
      getter name : String?

      # Regular expressions constraining parameter values by name. A route
      # matches only when every constrained parameter satisfies its regex.
      getter constraints : Hash(String, Regex)

      # The handler that answers matched requests.
      getter handler : Handler

      def initialize(@method : String, @pattern : String, @handler : Handler, @action : String? = nil, @name : String? = nil, @constraints : Hash(String, Regex) = {} of String => Regex)
        @segments = Segment.parse(@pattern)
      end

      # Returns `true` when the route's last segment is a glob (`*path`),
      # which owns the rest of the path.
      def glob? : Bool
        @segments.last?.try(&.kind) == Segment::Kind::Glob
      end

      # Returns `true` when the route's segments fully match the given
      # path parts, extracting the parameter values into the returned
      # hash. Returns `nil` when the path does not match — either by
      # shape or by a violated parameter constraint. A glob segment
      # captures the remaining parts, decoded and joined with `/`, and
      # requires at least one.
      def match(parts : PathParts) : Hash(String, String)?
        return unless shape_ok?(parts)
        params = {} of String => String
        @segments.each_with_index do |segment, index|
          case segment.kind
          when Segment::Kind::Static
            return unless segment.value == parts[index]
          when Segment::Kind::Param
            value = URI.decode(parts[index])
            return unless constraint_ok?(segment.value, value)
            params[segment.value] = value
          when Segment::Kind::Glob
            value = parts.parts[index..].map { |part| URI.decode(part) }.join("/")
            return unless constraint_ok?(segment.value, value)
            params[segment.value] = value
          end
        end
        params
      end

      # Returns `true` when the route's segments match the given path
      # parts, regardless of parameter values. Used to detect method
      # mismatches (405 responses).
      def matches_path?(parts : PathParts) : Bool
        return false unless shape_ok?(parts)
        @segments.each_with_index do |segment, index|
          case segment.kind
          when Segment::Kind::Static
            return false unless segment.value == parts[index]
          when Segment::Kind::Param
            return false unless constraint_ok?(segment.value, URI.decode(parts[index]))
          when Segment::Kind::Glob
            return false unless constraint_ok?(segment.value, URI.decode(parts.parts[index..].join("/")))
          end
        end
        true
      end

      # Non-glob routes need exactly their own segment count; glob routes
      # need at least theirs, since a glob requires one captured segment.
      private def shape_ok?(parts : PathParts) : Bool
        glob? ? parts.size >= @segments.size : parts.size == @segments.size
      end

      # A parameter satisfies its constraint when the regex matches the
      # whole value, not just a substring — `/\d+/` accepts `"5"` but
      # rejects `"55x"`, mirroring anchored segment matching.
      private def constraint_ok?(name : String, value : String) : Bool
        if constraint = @constraints[name]?
          if match = constraint.match(value)
            return match[0] == value
          end
          return false
        end
        true
      end
    end
  end
end
