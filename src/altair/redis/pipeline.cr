# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Redis::Pipeline`, which batches multiple
# commands into a single network round trip. Commands are queued locally,
# flushed together, and their replies read back in order.
module Altair
  module Redis
    class Pipeline
      @commands = [] of Array(String)
      @conn : Connection

      def initialize(@conn : Connection)
      end

      def set(key : String, value : String) : Nil
        queue(["SET", key, value])
      end

      def get(key : String) : Nil
        queue(["GET", key])
      end

      def del(key : String) : Nil
        queue(["DEL", key])
      end

      def incr(key : String) : Nil
        queue(["INCR", key])
      end

      def expire(key : String, seconds : Int32) : Nil
        queue(["EXPIRE", key, seconds.to_s])
      end

      def ping : Nil
        queue(["PING"])
      end

      # Flushes all queued commands in one write and reads the replies.
      def flush_and_read : Array(Protocol::Reply)
        return [] of Protocol::Reply if @commands.empty?
        @conn.send_pipeline(@commands, @commands.size)
      ensure
        @commands.clear
      end

      private def queue(args : Array(String)) : Nil
        @commands << args
      end
    end
  end
end
