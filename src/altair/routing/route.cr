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

      # The handler that answers matched requests.
      getter handler : Handler

      def initialize(@method : String, @pattern : String, @handler : Handler, @action : String? = nil, @name : String? = nil)
        @segments = Segment.parse(@pattern)
      end

      # Returns `true` when the route's segments fully match the given
      # path parts, extracting the parameter values into the returned
      # hash. Returns `nil` when the path does not match.
      def match(parts : PathParts) : Hash(String, String)?
        return nil unless parts.size == @segments.size
        params = {} of String => String
        @segments.each_with_index do |segment, index|
          case segment.kind
          when Segment::Kind::Static
            return nil unless segment.value == parts[index]
          when Segment::Kind::Param
            params[segment.value] = URI.decode(parts[index])
          end
        end
        params
      end

      # Returns `true` when the route's segments match the given path
      # parts, regardless of parameter values. Used to detect method
      # mismatches (405 responses).
      def matches_path?(parts : PathParts) : Bool
        return false unless parts.size == @segments.size
        @segments.each_with_index do |segment, index|
          case segment.kind
          when Segment::Kind::Static
            return false unless segment.value == parts[index]
          when Segment::Kind::Param
          end
        end
        true
      end
    end
  end
end
