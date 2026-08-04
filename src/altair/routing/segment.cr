# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Routing::Segment`, one piece of a parsed route
# pattern, and `Altair::Routing::PathParts`, the matching shape of an
# incoming request path. A pattern such as `/posts/:id` is split at
# registration time into a static segment (`posts`) and a parameter segment
# (`id`). At request time the router walks the request path segment by
# segment against the route's pre-parsed segments — no regular expressions
# are involved, which keeps matching simple and fast.
module Altair
  module Routing
    struct Segment
      enum Kind
        # A literal path component, e.g. `"posts"` in `/posts/:id`.
        Static
        # A named placeholder, e.g. `:id` in `/posts/:id`.
        Param
        # A catch-all placeholder that captures the rest of the path, e.g.
        # `path` in `/files/*path`.
        Glob
      end

      # The segment kind.
      getter kind : Kind

      # For static segments the literal value; for parameter segments the
      # parameter name.
      getter value : String

      def initialize(@kind : Kind, @value : String)
      end

      # Returns `true` for parameter segments (`:id`).
      def param? : Bool
        @kind.param?
      end

      # Returns `true` for static segments (`posts`).
      def static? : Bool
        @kind.static?
      end

      # Returns `true` for glob segments (`*path`).
      def glob? : Bool
        @kind.glob?
      end

      # Parses a route pattern into segments. `/posts/:id` becomes the
      # static segment `posts` and the parameter segment `id`; `/files/*path`
      # yields the same static segment plus a glob segment that owns the rest
      # of the path. A glob must be the last segment and needs a name.
      def self.parse(pattern : String) : Array(Segment)
        parts = pattern.split('/').reject(&.empty?)
        glob_index = parts.index(&.starts_with?('*'))
        if glob_index && glob_index != parts.size - 1
          raise ArgumentError.new("glob segments must be the last segment of a route: #{pattern}")
        end
        if glob_index && parts[glob_index].size == 1
          raise ArgumentError.new("glob segments need a name: #{pattern}")
        end
        parts.map do |part|
          if part.starts_with?(':')
            new(Kind::Param, part[1..])
          elsif part.starts_with?('*')
            new(Kind::Glob, part[1..])
          else
            new(Kind::Static, part)
          end
        end
      end
    end

    # An incoming request path split into its non-empty parts, the shape
    # routes are matched against. `/posts/5` yields `["posts", "5"]`.
    struct PathParts
      getter parts : Array(String)

      def initialize(path : String)
        @parts = path.split('/').reject(&.empty?)
      end

      # The number of path parts.
      def size : Int32
        @parts.size
      end

      # The part at the given index.
      def [](index : Int32) : String
        @parts[index]
      end
    end
  end
end
