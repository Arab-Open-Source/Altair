# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Redis::Client`, the public entry point for
# every Redis operation. It wraps a `Pool` of `Connection`s and exposes a
# fluent, typed API for all core Redis commands organised by data type.
#
# ```
# client = Altair::Redis::Client.new(URI.parse("redis://localhost:6379"))
# client.set("key", "value", ex: 5.minutes)
# client.get("key")           # => "value"
# client.publish("ch", "msg") # => subscribers reached
# ```
require "./protocol"
require "./connection"
require "./pool"
require "./pipeline"
require "./transaction"

module Altair
  module Redis
    class Client
      @pool : Pool

      def initialize(uri : URI, max_pool_size : Int32 = 10,
                     connect_timeout : Int32 = 5, tls : Bool = false)
        password = uri.password
        db = uri.path.lchop("/").to_i? || 0
        @pool = Pool.new(max_size: max_pool_size) do
          Connection.new(uri, tls: tls, password: password, database: db,
            connect_timeout: connect_timeout)
        end
      end

      def initialize(url : String, **opts)
        initialize(URI.parse(url), **opts)
      end

      # Convenience for pub/sub — checks out a dedicated connection for
      # exclusive subscription use (not returned to the pool until closed).
      def subscribe_connection : Connection
        @pool.checkout
      end

      def return_connection(conn : Connection) : Nil
        @pool.checkin(conn)
      end

      def close : Nil
        @pool.close
      end

      # ── Strings ──────────────────────────────────────────────────────────

      def set(key : String, value : String, *, ex : Time::Span? = nil,
              px : Time::Span? = nil, nx : Bool = false, xx : Bool = false) : Bool
        args = ["SET", key, value]
        args << "EX" << ex.total_seconds.to_i.to_s if ex
        args << "PX" << px.total_milliseconds.to_i.to_s if px
        args << "NX" if nx
        args << "XX" if xx
        reply = run(args)
        reply == "OK"
      end

      def get(key : String) : String?
        as_optional_string(run(["GET", key]))
      end

      def setex(key : String, seconds : Int32, value : String) : Bool
        run(["SETEX", key, seconds.to_s, value]) == "OK"
      end

      def del(*keys : String) : Int64
        as_int(run(["DEL"] + keys.to_a))
      end

      def exists(*keys : String) : Int64
        as_int(run(["EXISTS"] + keys.to_a))
      end

      def incr(key : String) : Int64
        as_int(run(["INCR", key]))
      end

      def incrby(key : String, amount : Int64) : Int64
        as_int(run(["INCRBY", key, amount.to_s]))
      end

      def decr(key : String) : Int64
        as_int(run(["DECR", key]))
      end

      def decrby(key : String, amount : Int64) : Int64
        as_int(run(["DECRBY", key, amount.to_s]))
      end

      def mset(mapping : Hash(String, String)) : Bool
        args = ["MSET"]
        mapping.each { |k, v| args << k << v }
        run(args) == "OK"
      end

      def mget(*keys : String) : Array(String?)
        as_array(run(["MGET"] + keys.to_a)).map { |v| v.as?(String) }
      end

      def ttl(key : String) : Int64
        as_int(run(["TTL", key]))
      end

      def expire(key : String, seconds : Int32) : Bool
        as_int(run(["EXPIRE", key, seconds.to_s])) == 1
      end

      def persist(key : String) : Bool
        as_int(run(["PERSIST", key])) == 1
      end

      # ── Hashes ───────────────────────────────────────────────────────────

      def hset(key : String, field : String, value : String) : Int64
        as_int(run(["HSET", key, field, value]))
      end

      def hget(key : String, field : String) : String?
        as_optional_string(run(["HGET", key, field]))
      end

      def hdel(key : String, *fields : String) : Int64
        as_int(run(["HDEL", key] + fields.to_a))
      end

      def hexists(key : String, field : String) : Bool
        as_int(run(["HEXISTS", key, field])) == 1
      end

      def hgetall(key : String) : Hash(String, String)
        result = Hash(String, String).new
        as_array(run(["HGETALL", key])).each_slice(2) do |pair|
          result[pair[0].as(String)] = pair[1].as(String)
        end
        result
      end

      # ── Lists ────────────────────────────────────────────────────────────

      def lpush(key : String, *values : String) : Int64
        as_int(run(["LPUSH", key] + values.to_a))
      end

      def rpush(key : String, *values : String) : Int64
        as_int(run(["RPUSH", key] + values.to_a))
      end

      def lrange(key : String, start : Int32, stop : Int32) : Array(String)
        as_array(run(["LRANGE", key, start.to_s, stop.to_s])).map(&.as(String))
      end

      def llen(key : String) : Int64
        as_int(run(["LLEN", key]))
      end

      def lpop(key : String) : String?
        as_optional_string(run(["LPOP", key]))
      end

      def rpop(key : String) : String?
        as_optional_string(run(["RPOP", key]))
      end

      # ── Sets ─────────────────────────────────────────────────────────────

      def sadd(key : String, *members : String) : Int64
        as_int(run(["SADD", key] + members.to_a))
      end

      def srem(key : String, *members : String) : Int64
        as_int(run(["SREM", key] + members.to_a))
      end

      def sismember(key : String, member : String) : Bool
        as_int(run(["SISMEMBER", key, member])) == 1
      end

      def smembers(key : String) : Set(String)
        Set.new(as_array(run(["SMEMBERS", key])).map(&.as(String)))
      end

      def scard(key : String) : Int64
        as_int(run(["SCARD", key]))
      end

      # ── Sorted Sets ──────────────────────────────────────────────────────

      def zadd(key : String, score : Float64, member : String) : Bool
        as_int(run(["ZADD", key, score.to_s, member])) == 1
      end

      def zrange(key : String, start : Int32, stop : Int32) : Array(String)
        as_array(run(["ZRANGE", key, start.to_s, stop.to_s])).map(&.as(String))
      end

      def zscore(key : String, member : String) : Float64?
        reply = run(["ZSCORE", key, member])
        return if reply.nil?
        reply.as?(String).try(&.to_f) || reply.as?(Float64)
      end

      def zrem(key : String, member : String) : Bool
        as_int(run(["ZREM", key, member])) == 1
      end

      def zcard(key : String) : Int64
        as_int(run(["ZCARD", key]))
      end

      # ── Keys ─────────────────────────────────────────────────────────────

      def keys(pattern : String = "*") : Array(String)
        as_array(run(["KEYS", pattern])).map(&.as(String))
      end

      def type(key : String) : String
        run(["TYPE", key]).as?(String) || "none"
      end

      def dbsize : Int64
        as_int(run(["DBSIZE"]))
      end

      # Cursor-based iteration — memory-safe for large keyspaces.
      def scan_each(match : String? = nil, count : Int32 = 10, & : String -> Nil) : Nil
        cursor = "0"
        loop do
          args = ["SCAN", cursor]
          args += ["MATCH", match] if match
          args += ["COUNT", count.to_s]
          batch = as_array(run(args))
          cursor = batch[0].as(String)
          batch[1].as(Array).each { |key| yield key.as(String) }
          break if cursor == "0"
        end
      end

      # ── Server ───────────────────────────────────────────────────────────

      def ping : Bool
        run(["PING"]) == "PONG"
      end

      def echo(message : String) : String
        run(["ECHO", message]).as(String)
      end

      def flushdb : Bool
        run(["FLUSHDB"]) == "OK"
      end

      # ── Pub/Sub ──────────────────────────────────────────────────────────

      def publish(channel : String, message : String) : Int64
        as_int(run(["PUBLISH", channel, message]))
      end

      # Opens a dedicated subscription connection and yields a subscriber.
      # Blocks the calling fiber — spawn for non-blocking usage.
      def subscribe(*channels : String, &) : Nil
        conn = subscribe_connection
        begin
          conn.write_only(["SUBSCRIBE"] + channels.to_a)
          sub = Subscription.new(conn, channels.map(&.to_s).to_a)
          yield sub
        rescue ex : IO::Error
          conn.close!
          raise Altair::Redis::ConnectionLost.new("subscribe failed: #{ex.message}")
        end
      end

      # ── Pipeline & Transaction delegates ─────────────────────────────────

      # Sends multiple commands in a single round trip:
      #
      # ```
      # results = client.pipeline do |pipe|
      #   pipe.set("a", "1")
      #   pipe.incr("counter")
      #   pipe.get("a")
      # end
      # ```
      def pipeline(& : Pipeline -> Nil) : Array(Protocol::Reply)
        @pool.checkout do |conn|
          pipe = Pipeline.new(conn)
          yield pipe
          pipe.flush_and_read
        end
      end

      # Runs commands atomically inside MULTI/EXEC:
      #
      # ```
      # client.multi do |txn|
      #   txn.set("session", data)
      #   txn.expire("session", 3600)
      # end
      # ```
      def multi(& : Transaction -> Nil) : Array(Protocol::Reply)?
        @pool.checkout do |conn|
          txn = Transaction.new(conn)
          txn.begin!
          yield txn
          txn.exec
        end
      end

      # Optimistic locking via WATCH/UNWATCH.
      def watch(*keys : String, &) : Nil
        @pool.checkout do |conn|
          conn.send_command(["WATCH"] + keys)
          yield
        end
        @pool.checkout(&.send_command(["UNWATCH"]))
      end

      private def run(args : Array(String)) : Protocol::Reply
        @pool.checkout(&.send_command(args))
      end

      private def as_string(reply : Protocol::Reply) : String
        reply.as(String)
      end

      private def as_optional_string(reply : Protocol::Reply) : String?
        reply.as?(String)
      end

      private def as_int(reply : Protocol::Reply) : Int64
        reply.as(Int64)
      end

      private def as_array(reply : Protocol::Reply) : Array(Protocol::Reply)
        reply.as(Array)
      end
    end
  end
end
