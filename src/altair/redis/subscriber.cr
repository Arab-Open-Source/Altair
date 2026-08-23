# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Redis::Subscription`, which wraps a dedicated
# Redis connection in pub/sub mode. Messages arrive asynchronously on a
# dedicated fiber; callbacks fire for each received message.
module Altair
  module Redis
    class Subscription
      getter channels : Array(String)
      @on_message : Proc(String, String, Nil)?
      @conn : Connection

      def initialize(@conn : Connection, @channels : Array(String))
      end

      # Sets the callback fired when a message arrives on any subscribed channel.
      def on_message(&callback : String, String -> Nil) : self
        @on_message = callback
        self
      end

      # Enters subscription mode — blocks until the connection closes or
      # all channels are unsubscribed. Call from a spawned fiber.
      def run : Nil
        conn.send_command(["SUBSCRIBE"] + channels.to_a)
        loop do
          reply = Protocol.decode(conn.io)
          break if reply.nil?
          next unless reply.is_a?(Array)
          action = reply[0].as?(String)
          channel = reply[1].as?(String)
          message = reply.size > 2 ? reply[2].as?(String) : nil
          if action == "message" && (cb = @on_message)
            cb.call(channel.not_nil!, message.not_nil!)
          end
        rescue ::IO::Error
          break
        end
      end

      def close : Nil
        conn.close!
      end

      private getter conn : Connection
    end
  end
end
