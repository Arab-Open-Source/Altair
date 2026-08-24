# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::PermitGate`, an admission control
# policy for the database stage. It caps how many fibers may hold a pooled
# connection at once: when a request path checks out a connection beyond
# the limit, the fiber parks on the gate's FIFO semaphore instead of piling
# onto the pool's condition-variable queue. Blocked fibers wait outside the
# pool, so under load the tail latency degrades gracefully instead of
# stacking on the pool's deep wait queue.
#
# The gate subscribes to `Altair::Record.on_checkout`; a zero limit arms
# nothing and the request path pays nothing. The migration runner and CLI
# never install the gate, so bulk work is never serialized by it.
module Altair
  module Record
    class PermitGate
      @@enabled = false
      @@registered = false
      @@semaphore : Altair::Concurrency::Semaphore? = nil
      @@timeout = 5.seconds
      @@lock = Mutex.new

      # Whether the gate is currently armed.
      def self.enabled? : Bool
        @@enabled
      end

      # Arms the gate with `max_active` concurrent connections when the
      # value is positive, registering the checkout hook once. A
      # non-positive value disarms it. Called whenever a request handler is
      # built for an application. `timeout` bounds how long a fiber waits on
      # the FIFO gate; past the deadline it raises
      # `Altair::Concurrency::Timeout` instead of waiting forever, and no
      # permit is left stranded.
      def self.enable(max_active : Int32, timeout : Time::Span = 5.seconds) : Nil
        @@lock.synchronize do
          @@timeout = timeout
          @@semaphore = max_active > 0 ? Altair::Concurrency::Semaphore.new(max_active) : nil
          @@enabled = max_active > 0
          # Re-register when the handler table was wiped under us (specs
          # call `Record.clear_handlers!`) — an armed gate without its
          # hook would silently admit everything.
          register if @@enabled && (!@@registered || !Altair::Record.checkout_hooks?)
        end
      end

      private def self.register : Nil
        Altair::Record.on_checkout do |run|
          if semaphore = @@semaphore
            semaphore.with_permit(@@timeout) { run.call }
          else
            run.call
          end
        end
        @@registered = true
      end
    end
  end
end
