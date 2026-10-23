# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Support::LRUCache`, a thread-safe, fixed-capacity
# least-recently-used cache. The router uses it to memoize route lookups so a
# repeated request path collapses to a hash lookup instead of re-walking the
# route table. Kept as a linked list of nodes in a hash map, get and put are
# both O(1).
module Altair
  module Support
    class LRUCache(K, V)
      # A doubly-linked list node holding one cached value.
      class Node(K, V)
        getter key : K
        property value : V
        property prev : Node(K, V)?
        property next : Node(K, V)?

        def initialize(@key : K, @value : V)
          @prev = nil
          @next = nil
        end
      end

      @capacity : Int32
      @map : Hash(K, Node(K, V))
      @head : Node(K, V)?
      @tail : Node(K, V)?
      @mutex : Mutex
      getter hits : Int64 = 0
      getter misses : Int64 = 0
      getter evictions : Int64 = 0

      # Snapshot of the cache health counters.
      def metrics : NamedTuple(hits: Int64, misses: Int64, evictions: Int64, size: Int32)
        @mutex.synchronize do
          {hits: @hits, misses: @misses, evictions: @evictions, size: @map.size}
        end
      end

      # Resets the hit/miss/eviction counters, keeping the entries.
      def reset_metrics : Nil
        @mutex.synchronize do
          @hits = 0
          @misses = 0
          @evictions = 0
        end
      end

      # The current number of cached entries.
      def size : Int32
        @mutex.synchronize { @map.size }
      end

      def initialize(@capacity : Int32)
        @map = Hash(K, Node(K, V)).new
        @head = nil
        @tail = nil
        @mutex = Mutex.new
      end

      # Returns the cached value for *key*, moving it to the most-recently
      # used position, or `nil` when absent.
      def get(key : K) : V?
        @mutex.synchronize do
          if node = @map[key]?
            @hits += 1
            move_to_front(node)
            node.value
          else
            @misses += 1
            nil
          end
        end
      end

      # Returns the cached value for *key* without touching the hit/miss
      # counters — the re-check inside a build lock. Still moves the entry
      # to the most-recently-used position.
      def peek(key : K) : V?
        @mutex.synchronize do
          if node = @map[key]?
            move_to_front(node)
            node.value
          end
        end
      end

      # Stores *value* under *key*, evicting the least-recently-used entry
      # when the cache is at capacity. A zero capacity stores nothing, so a
      # disabled cache degrades to a plain lookup.
      def put(key : K, value : V) : Nil
        return if @capacity <= 0
        @mutex.synchronize do
          if node = @map[key]?
            node.value = value
            move_to_front(node)
            return
          end
          evict_if_at_capacity
          node = Node(K, V).new(key, value)
          @map[key] = node
          insert_front(node)
        end
      end

      # Clears every entry. Used by specs and when the cache is reconfigured.
      def clear : Nil
        @mutex.synchronize do
          @map.clear
          @head = nil
          @tail = nil
        end
      end

      private def insert_front(node : Node(K, V))
        node.prev = nil
        node.next = @head
        @head.try(&.prev=(node))
        @head = node
        @tail = node if @tail.nil?
      end

      private def move_to_front(node : Node(K, V))
        return if node == @head

        prev = node.prev
        nxt = node.next
        prev.try(&.next=(nxt))
        nxt.try(&.prev=(prev))
        @tail = prev if node == @tail

        insert_front(node)
      end

      private def evict_if_at_capacity
        return if @map.size < @capacity

        if lru = @tail
          prev = lru.prev
          if prev
            prev.next = nil
            @tail = prev
          else
            @head = nil
            @tail = nil
          end
          @map.delete(lru.key)
          @evictions += 1
        end
      end
    end
  end
end
