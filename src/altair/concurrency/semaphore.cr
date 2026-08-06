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
    # Raised when a permit could not be acquired within the configured
    # deadline. Subclasses the HTTP error hierarchy so an admission timeout
    # surfaces as a 503 by default; applications may map it differently via
    # `rescue_from`.
    class Timeout < Altair::HTTP::Error
      def initialize(message : String = "Database admission timeout: no permit available in time")
        super(message, ::HTTP::Status::SERVICE_UNAVAILABLE)
      end
    end

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

      # Removes one permit if one becomes available within the span,
      # returning whether it was acquired. Never blocks past the deadline.
      def acquire(timeout : Time::Span) : Bool
        select
        when @permits.receive
          true
        when timeout(timeout)
          false
        end
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

      # Acquires one permit within the deadline around the block, raising
      # `Altair::Concurrency::Timeout` when none becomes available. The
      # permit is always released, even when the block raises.
      def with_permit(timeout : Time::Span, & : -> U) : U forall U
        raise Timeout.new unless acquire(timeout)
        begin
          yield
        ensure
          release
        end
      end
    end
  end
end
