# Altair — Redis-backed cache store.
#
# Implements the `Altair::Cache::Store` contract on top of
# `Altair::Redis::Client`, so cached values survive process restarts and
# are shared across all application instances behind a load balancer.
#
# ```
# config.cache = Altair::Cache::RedisStore.new(
#   Altair::Redis::Client.new(URI.parse(ENV["REDIS_URL"]))
# )
# ```
module Altair
  module Cache
    class RedisStore < Store
      @client : Altair::Redis::Client

      def initialize(@client : Altair::Redis::Client)
      end

      # Reads a value or returns `nil` when absent.
      def read(key : String) : String?
        @client.get("cache:#{key}")
      end

      # Stores a value, optionally expiring it after the supplied duration.
      def write(key : String, value : String, expires_in : Time::Span? = nil) : String
        if expires_in
          @client.setex("cache:#{key}", expires_in.total_seconds.to_i, value)
        else
          @client.set("cache:#{key}", value)
        end
        value
      end

      # Removes one value. Returns whether a key was actually deleted.
      def delete(key : String) : Bool
        @client.del("cache:#{key}") > 0
      end

      # Removes every cache key (SCAN + DEL — memory-safe for large keyspaces).
      def clear : Nil
        @client.scan_each(match: "cache:*") { |key| @client.del(key) }
      end

      # Reads a value or computes and stores it atomically for this store.
      def fetch(key : String, expires_in : Time::Span? = nil, &) : String
        read(key) || write(key, yield, expires_in)
      end
    end
  end
end
