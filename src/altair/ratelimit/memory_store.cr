# Altair — the in-process rate-limit store.
#
# Two counters per key — the previous and current fixed window — guarded
# by one mutex and pruned lazily as keys are touched. Deterministic under
# an injected clock, which is how its specs verify the sliding math
# without sleeps.
require "./ratelimit"

module Altair::RateLimit
  class MemoryStore < Store
    @windows = Hash(String, Hash(Int64, Int32)).new
    @lock = Mutex.new

    def hit(key : String, limit : Int32, period : Time::Span, now : Float64? = nil) : Hit
      at = now_or(now)
      current, fraction = Store.window(period, at)
      previous = current - 1

      @lock.synchronize do
        buckets = (@windows[key] ||= Hash(Int64, Int32).new(0))
        prune(buckets, current)

        weighted = Store.weighted(buckets.fetch(previous, 0), buckets[current], fraction)
        reset_in = period.total_seconds * (1 - fraction)
        if weighted >= limit
          return Hit.new(false, 0, reset_in)
        end

        buckets[current] += 1
        Hit.new(true, clamp_remaining(limit - (weighted + 1)), reset_in)
      end
    end

    def clear : Nil
      @lock.synchronize { @windows.clear }
    end

    def close : Nil
    end

    # Distinct keys currently holding counters — a spec handle.
    def size : Int32
      @lock.synchronize { @windows.size }
    end

    # Drops window entries older than the previous one; removes keys
    # whose every bucket is gone.
    private def prune(buckets : Hash(Int64, Int32), current : Int64) : Nil
      buckets.select! { |window, _| window >= current - 1 }
      @windows.delete(current) if buckets.empty?
    end
  end
end
