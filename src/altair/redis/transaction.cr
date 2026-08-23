# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Redis::Transaction`, which wraps commands in
# MULTI/EXEC for atomic execution. All queued commands execute as a unit —
# either all succeed or none are applied.
module Altair
  module Redis
    class Transaction
      @conn : Connection

      def initialize(@conn : Connection)
      end

      # Sends MULTI and marks the transaction as active.
      def begin! : Nil
        @conn.send_command(["MULTI"])
      end

      def set(key : String, value : String) : Nil
        @conn.send_command(["SET", key, value])
      end

      def get(key : String) : Nil
        @conn.send_command(["GET", key])
      end

      def del(key : String) : Nil
        @conn.send_command(["DEL", key])
      end

      def incr(key : String) : Nil
        @conn.send_command(["INCR", key])
      end

      def expire(key : String, seconds : Int32) : Nil
        @conn.send_command(["EXPIRE", key, seconds.to_s])
      end

      def hset(key : String, field : String, value : String) : Nil
        @conn.send_command(["HSET", key, field, value])
      end

      def publish(channel : String, message : String) : Nil
        @conn.send_command(["PUBLISH", channel, message])
      end

      def lpush(key : String, value : String) : Nil
        @conn.send_command(["LPUSH", key, value])
      end

      # Executes the queued commands atomically and returns their replies.
      # Returns nil if WATCH detected a modification.
      def exec : Array(Protocol::Reply)?
        reply = @conn.send_command(["EXEC"])
        return unless reply.is_a?(Array)
        reply
      end

      # Discards the transaction without executing any queued commands.
      def discard : Nil
        @conn.send_command(["DISCARD"])
      end
    end
  end
end
