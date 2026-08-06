# Altair — the batteries-included web framework for Crystal.
#
# This file defines the `Altair::Record` module, the ORM layer's public
# entry: the application connection, the query instrumentation hook and
# the migration runner. Models (Phase 4 wave 2) build on top of it.
module Altair
  module Record
    # The application's connection, opened lazily from `config.db_url` on
    # first use. Raises `Altair::ConfigurationError` when no database is
    # configured. The steady path is lock-free: once open, `@@connection` is
    # read directly on every call, so high-concurrency workloads never
    # serialize on the init mutex. The mutex is only taken to open the pool
    # on first touch (double-checked) and to close/reopen it.
    def self.connection : Connection
      conn = @@connection
      return conn if conn
      app = Altair.application_instance
      raise Altair::ConfigurationError.new("No application instance") unless app
      @@connection_lock.synchronize do
        @@connection ||= Connection.for(app)
      end
    end

    # The connection for the given application, used before the instance
    # is set (e.g. by migration runner scripts).
    def self.connection_for(app : Altair::Application) : Connection
      Connection.for(app)
    end

    # Timing details for a single executed statement. Unlike the legacy
    # `on_query` hook — which reports one total duration — the event records
    # how long acquisition vs. execution vs. result-reading each took, so pool
    # or admission wait is never mistaken for SQL time. Values always travel
    # as bind parameters, so the SQL holds no data. An event fires for every
    # statement, whether it completes or raises.
    struct QueryEvent
      # The kind of operation inferred from the statement's leading keyword.
      enum Operation
        Query
        Insert
        Update
        Delete
        Other

        # Maps a SQL string to its operation, based on its leading keyword.
        def self.from_sql(sql : String) : Operation
          prefix = sql.lstrip[0, 8].upcase
          case
          when prefix.starts_with?("INSERT") then Operation::Insert
          when prefix.starts_with?("UPDATE") then Operation::Update
          when prefix.starts_with?("DELETE") then Operation::Delete
          when prefix.starts_with?("SELECT") then Operation::Query
          else                                    Operation::Other
          end
        end
      end

      getter sql : String
      getter adapter : String
      getter operation : Operation
      getter checkout_wait : Time::Span
      getter sql_time : Time::Span
      getter decode_time : Time::Span
      getter? success : Bool

      def initialize(
        @sql : String,
        @adapter : String,
        @operation : Operation,
        @checkout_wait : Time::Span,
        @sql_time : Time::Span,
        @decode_time : Time::Span,
        @success : Bool,
      )
      end

      # The total wall-clock time the statement spanned.
      def total : Time::Span
        checkout_wait + sql_time + decode_time
      end
    end

    # Registers a hook called after every executed query with the SQL and
    # its duration:
    #
    # ```
    # Altair::Record.on_query do |sql, duration|
    #   Log.info { "#{sql} took #{duration}" }
    # end
    # ```
    def self.on_query(&handler : Proc(String, Time::Span, Nil)) : Nil
      @@query_handlers << handler
    end

    # Whether any query handler is registered. The connection skips the
    # per-statement timing entirely when this is false.
    def self.query_handlers? : Bool
      !@@query_handlers.empty?
    end

    # Notifies the instrumentation hooks. Called by the connection.
    def self.notify_query(sql : String, duration : Time::Span) : Nil
      @@query_handlers.each &.call(sql, duration)
    end

    # Registers a hook called after every executed statement with a granular
    # `QueryEvent` that separates acquisition wait from SQL time and decode
    # time, and records whether the statement succeeded. The hook is called
    # in an `ensure`, so it also fires when the statement raises — without
    # ever receiving bind values or sensitive data:
    #
    # ```
    # Altair::Record.on_query_event do |event|
    #   Log.info {
    #     "#{event.operation} checkout=#{event.checkout_wait} " \
    #     "sql=#{event.sql_time} decode=#{event.decode_time}"
    #   }
    # end
    # ```
    #
    # This API is independent of the legacy `on_query`, which keeps reporting
    # a single total duration. Registering either arms the per-statement
    # timing; a bare application with neither hook pays no clock reads.
    def self.on_query_event(&handler : Proc(QueryEvent, Nil)) : Nil
      @@query_event_handlers << handler
    end

    # Whether any granular event handler is registered.
    def self.query_event_handlers? : Bool
      !@@query_event_handlers.empty?
    end

    # Notifies the granular event handlers. Called by the connection.
    def self.notify_query_event(
      sql : String,
      adapter : String,
      operation : QueryEvent::Operation,
      checkout_wait : Time::Span,
      sql_time : Time::Span,
      decode_time : Time::Span,
      success : Bool,
    ) : Nil
      @@query_event_handlers.each &.call(
        QueryEvent.new(sql, adapter, operation, checkout_wait, sql_time, decode_time, success)
      )
    end

    # Registers a hook run around every connection acquisition. The hook
    # receives a continuation proc it must call to perform the actual work:
    #
    # ```
    # Altair::Record.on_checkout do |run|
    #   acquire
    #   run.call
    #   release
    # end
    # ```
    #
    # Hooks run inside out in registration order. The connection skips the
    # seam entirely when no hook is registered.
    def self.on_checkout(&handler : Proc(Proc(Nil), Nil)) : Nil
      @@checkout_handlers << handler
    end

    # Whether any checkout hook is registered. The connection takes its
    # zero-cost path when this is false.
    def self.checkout_hooks? : Bool
      !@@checkout_handlers.empty?
    end

    # Runs the registered checkout hooks around the block, preserving the
    # block's return value. The first registered hook runs first.
    def self.run_checkout_hooks(&block : -> U) : U forall U
      if @@checkout_handlers.empty?
        block.call
      else
        value = uninitialized U
        inner = -> { value = block.call; nil }
        @@checkout_handlers.reverse_each do |handler|
          prev = inner
          inner = -> { handler.call(prev); nil }
        end
        inner.call
        value
      end
    end

    @@query_handlers = [] of Proc(String, Time::Span, Nil)
    @@query_event_handlers = [] of Proc(QueryEvent, Nil)
    @@checkout_handlers = [] of Proc(Proc(Nil), Nil)
    @@connection : Connection? = nil
    @@connection_lock = Mutex.new

    # Closes the pooled connection (used by specs and runner scripts). The
    # nil write happens under the lock so a concurrent fast-path reader
    # either sees the previous connection (about to be closed, already
    # returned to the pool) or sees nil and reopens — never a dangling
    # reference.
    def self.close_connection : Nil
      @@connection_lock.synchronize do
        @@connection.try(&.close)
        @@connection = nil
      end
    end
  end
end
