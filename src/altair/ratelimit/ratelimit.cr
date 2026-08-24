# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::RateLimit`, the sliding-window rate limiter:
# a declarative rule set on `config.rate_limit`, two interchangeable
# stores (in-process memory and Redis for multi-instance deployments),
# and the `Middleware` that enforces the rules before routing. The
# middleware is a pass-through until at least one rule is configured.
require "uri"

module Altair
  module RateLimit
    # The verdict of one counted request against one rule.
    struct Hit
      # Whether the request is within the limit.
      getter allowed : Bool

      # How much of the budget remains after this hit (floored at zero).
      getter remaining : Int32

      # Seconds until the current window closes — the natural value for a
      # `Retry-After` header on a denied request.
      getter reset_in : Float64

      def initialize(@allowed : Bool, @remaining : Int32, @reset_in : Float64)
      end
    end

    # One declared constraint: `limit` requests per `period`. When `paths`
    # is nil the rule matches every path; otherwise a path matches when it
    # equals an entry or lives underneath it (`"/login"` matches
    # `"/login"`, `"/login/x"` — never `"/logistics"`).
    class Rule
      getter limit : Int32
      getter period : Time::Span
      getter paths : Array(String)?

      def initialize(@limit : Int32, @period : Time::Span, @paths : Array(String)? = nil)
      end

      def matches?(path : String) : Bool
        entries = @paths
        return true unless entries
        entries.any? do |entry|
          prefix = entry.ends_with?("/") ? entry : entry + "/"
          path == entry || path.starts_with?(prefix)
        end
      end

      # Requests per second — the tighter of two matching rules governs.
      def tightness : Float64
        @limit / @period.total_seconds
      end
    end

    # Counts hits over sliding windows. Implementations share the math in
    # `Store.window`; only the two counters per key/window are storage.
    abstract class Store
      # Records one hit and returns the verdict.
      abstract def hit(key : String, limit : Int32, period : Time::Span, now : Float64? = nil) : Hit

      # Drops every counter.
      abstract def clear : Nil

      # Releases any resources held by the store. The memory store has
      # nothing to do; the Redis store closes its client.
      def close : Nil
      end

      # The fixed window containing `now`, plus how far into it we are as
      # a 0..1 fraction. Exposed so both stores (and their specs) compute
      # identical windows from identical clocks.
      protected def self.window(period : Time::Span, now : Float64) : {Int64, Float64}
        seconds = period.total_seconds
        position = now / seconds
        current = position.floor.to_i64
        {current, position - current}
      end

      # The weighted count across the previous and current windows — the
      # sliding-window-counter estimate: the previous window decays
      # linearly as the current one fills.
      protected def self.weighted(previous : Int32, current_count : Int32, fraction : Float64) : Float64
        previous * (1 - fraction) + current_count
      end

      private def monotonic_now : Float64
        Time.instant.elapsed.total_seconds
      end

      private def now_or(now : Float64?) : Float64
        now || monotonic_now
      end

      private def clamp_remaining(value : Float64) : Int32
        floor = value.floor.to_i
        floor > 0 ? floor : 0
      end
    end
  end
end
