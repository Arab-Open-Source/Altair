# Altair — cache stores.
#
# This file defines the small cache contract and its bounded in-process
# implementation. Applications can replace `config.cache` with a store that
# shares values across processes while callers keep the same API.
module Altair
  module Cache
    # The storage contract used by `Altair.cache`.
    abstract class Store
      # Reads a value or returns `nil` when it is absent or expired.
      abstract def read(key : String) : String?

      # Stores a value, optionally expiring it after the supplied duration.
      abstract def write(key : String, value : String, expires_in : Time::Span? = nil) : String

      # Removes one value.
      abstract def delete(key : String) : Bool

      # Removes every value.
      abstract def clear : Nil

      # Reads a value or computes and stores it atomically for this store.
      def fetch(key : String, expires_in : Time::Span? = nil, & : -> String) : String
        read(key) || write(key, yield, expires_in)
      end
    end

    # A mutex-protected in-process store with a bounded entry count.
    class MemoryStore < Store
      private struct Entry
        getter value : String
        getter expires_at : Time::Instant?

        def initialize(@value : String, @expires_at : Time::Instant?)
        end

        def expired? : Bool
          expires_at.try { |time| Time.instant >= time } || false
        end
      end

      @entries = {} of String => Entry
      @lock = Mutex.new

      # The maximum number of retained values. The oldest stored value is
      # removed when this bound is reached.
      getter max_entries : Int32

      def initialize(@max_entries : Int32 = 1_000)
        raise ArgumentError.new("cache max_entries must be positive") if @max_entries <= 0
      end

      def read(key : String) : String?
        @lock.synchronize do
          entry = @entries[key]?
          if entry && entry.expired?
            @entries.delete(key)
            nil
          else
            entry.try(&.value)
          end
        end
      end

      def write(key : String, value : String, expires_in : Time::Span? = nil) : String
        raise ArgumentError.new("cache expiry must not be negative") if expires_in && expires_in < Time::Span.zero
        @lock.synchronize do
          @entries.delete(@entries.keys.first) if !@entries.has_key?(key) && @entries.size >= max_entries
          @entries[key] = Entry.new(value, expires_in.try { |duration| Time.instant + duration })
        end
        value
      end

      def delete(key : String) : Bool
        @lock.synchronize { !@entries.delete(key).nil? }
      end

      def clear : Nil
        @lock.synchronize { @entries.clear }
      end

      def fetch(key : String, expires_in : Time::Span? = nil, & : -> String) : String
        @lock.synchronize do
          entry = @entries[key]?
          if entry && !entry.expired?
            next entry.value
          end
          @entries.delete(key) if entry
          value = yield
          @entries.delete(@entries.keys.first) if @entries.size >= max_entries
          @entries[key] = Entry.new(value, expires_in.try { |duration| Time.instant + duration })
          value
        end
      end
    end
  end

  # Returns the current application's configured cache store.
  def self.cache : Altair::Cache::Store
    application_instance.try(&.config.cache) || raise Altair::ConfigurationError.new("No application instance")
  end
end
