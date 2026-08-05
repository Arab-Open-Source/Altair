# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Concurrency::Semaphore`, a counting semaphore
# built on a buffered `Channel`. Acquisition and release are strict FIFO:
# the channel's receiver queue hands a permit to the longest-waiting fiber,
# so a burst of waiters unblocks in arrival order — the fair behavior the
# database pool's condition-variable path lacks. It is the primitive behind
# `Altair::Record::PermitGate`.
module Altair
  module Concurrency
    # A counting semaphore. `acquire` removes a permit, blocking the
    # calling fiber until one is available; `release` returns one. Permits
    # are handed out FIFO, so no waiter is starved.
    class Semaphore
      # The permit tokens. One buffered slot per permit; a receiver
      # corresponds to one held permit or one waiting fiber.
      @permits = Channel(Int32).new(0)

      # Opens the semaphore with `permits` tokens available.
      def initialize(permits : Int32)
        @permits = Channel(Int32).new(permits)
        permits.times { @permits.send(1) }
      end

      # Removes and returns one permit, blocking until one is available.
      def acquire : Nil
        @permits.receive
      end

      # Returns one permit to the semaphore.
      def release : Nil
        @permits.send(1)
      end

      # Acquires one permit around the block, always releasing it, even
      # when the block raises.
      def with_permit(& : -> U) : U forall U
        acquire
        begin
          yield
        ensure
          release
        end
      end
    end
  end
end
