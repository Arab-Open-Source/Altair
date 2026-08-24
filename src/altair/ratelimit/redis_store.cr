# Altair — the Redis-backed rate-limit store.
#
# The same two-counters-per-key sliding window as `MemoryStore`, but the
# counters live in Redis under a configurable prefix, so every process
# fronting one Redis shares one budget. Window ids are derived from the
# same injected clock as the memory store, keeping both stores' math
# identical.
require "./ratelimit"

module Altair
  module RateLimit
    class RedisStore < Store
      @client : Altair::Redis::Client
      @prefix : String

      def initialize(uri : URI, prefix : String = "altair:rl", max_pool_size : Int32 = 10)
        @client = Altair::Redis::Client.new(uri, max_pool_size: max_pool_size)
        @prefix = prefix
      end

      def initialize(url : String, prefix : String = "altair:rl", max_pool_size : Int32 = 10)
        initialize(URI.parse(url), prefix, max_pool_size)
      end

      def hit(key : String, limit : Int32, period : Time::Span, now : Float64? = nil) : Hit
        at = now_or(now)
        current, fraction = Store.window(period, at)
        previous = current - 1
        seconds = period.total_seconds
        reset_in = seconds * (1 - fraction)

        base = "#{@prefix}:#{sanitize(key)}"
        current_key = "#{base}:#{current}"
        previous_key = "#{base}:#{previous}"

        count = @client.incr(current_key)
        # Refresh only on first touch so long-lived windows keep their
        # original expiry instead of sliding forward forever.
        @client.expire(current_key, (seconds * 2).ceil.to_i + 1) if count == 1
        previous_count = (@client.get(previous_key) || "0").to_i

        weighted_before = Store.weighted(previous_count, (count - 1).to_i, fraction)
        if weighted_before >= limit
          @client.decr(current_key)
          ttl = @client.ttl(current_key)
          reset_in = ttl.to_f if ttl > 0
          return Hit.new(false, 0, reset_in)
        end

        Hit.new(true, clamp_remaining(limit - (weighted_before + 1)), reset_in)
      end

      def clear : Nil
        keys = @client.keys("#{@prefix}:*")
        keys.each { |key| @client.del(key) }
      end

      def close : Nil
        @client.close
      end

      private def sanitize(key : String) : String
        key.gsub(/[[:space:]:]/, "_")
      end
    end
  end
end
