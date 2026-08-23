# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Redis::Pool`, a lightweight connection pool
# for Redis connections. Callers check out connections for exclusive use,
# then return them for reuse. Idle connections beyond `max_idle` are closed.
module Altair
  module Redis
    class Pool
      @idle = [] of Connection
      @lock = Mutex.new

      def initialize(@max_size : Int32 = 10, @idle_timeout : Time::Span = 5.minutes,
                     &@factory : -> Connection)
      end

      # Checks out a connection from the pool, creating a new one if none
      # are idle and the pool is not at capacity.
      def checkout : Connection
        @lock.synchronize do
          while conn = @idle.shift?
            return conn if conn.connected?
            conn.close!
          end
        end
        @factory.call
      end

      # Returns a connection to the pool for reuse.
      def checkin(conn : Connection) : Nil
        @lock.synchronize { @idle << conn }
      end

      # Closes every idle connection in the pool.
      def close : Nil
        @lock.synchronize do
          @idle.each(&.close!)
          @idle.clear
        end
      end

      # The number of currently idle connections.
      def size : Int32
        @lock.synchronize { @idle.size }
      end

      # Checks out a connection, yields it to the block, then checks it back in.
      def checkout(& : Connection -> U) : U forall U
        conn = checkout
        begin
          yield conn
        ensure
          checkin(conn)
        end
      end
    end
  end
end
