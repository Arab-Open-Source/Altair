# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Connection`, the framework's database
# connection. It wraps a `DB::Database` pool with an adapter, applies the
# application's pool settings, and exposes an instrumentation hook —
# `Altair::Record.on_query` — that every executed statement passes through,
# the base for query logging and N+1 detection later.
require "atomic"

module Altair
  module Record
    class Connection
      # Returns the application's connection, opened lazily from
      # `config.db_url` on first use. Raises when no URL is configured.
      # The adapter is picked from the URL scheme: `sqlite3://` uses
      # SQLite, `postgres://` and `postgresql://` use the PostgreSQL
      # adapter, which a project loads by requiring
      # `altair/record/adapters/postgresql` (and declaring `crystal-pg`).
      def self.for(app : Altair::Application) : Connection
        url = app.config.db_url
        raise Altair::ConfigurationError.new(
          "No database configured: set config.db_url, e.g. \"sqlite3://./db/app.db\""
        ) unless url
        pool_options = DB::Pool::Options.new(
          initial_pool_size: app.config.db_initial_pool_size,
          max_pool_size: app.config.db_max_pool_size,
          max_idle_pool_size: app.config.db_max_idle_pool_size,
          checkout_timeout: app.config.db_checkout_timeout
        )
        adapter = if url.starts_with?("postgres") || url.starts_with?("postgresql")
                    {% if Altair::Record::Adapters.has_constant?("PostgreSQL") %}
                      Adapters::PostgreSQL.instance
                    {% else %}
                      raise Altair::ConfigurationError.new(
                        "The PostgreSQL adapter is not loaded — require \"altair/record/adapters/postgresql\" " \
                        "and add crystal-pg to your dependencies"
                      )
                    {% end %}
                  else
                    Adapters::SQLite3.instance
                  end
        connection_url = url
        if url.starts_with?("postgres") || url.starts_with?("postgresql")
          uri = URI.parse(url)
          params = uri.query_params
          timeout_ms = app.config.db_query_timeout.total_milliseconds.to_i
          params["statement_timeout"] = timeout_ms.to_s if timeout_ms > 0
          uri.query = params.to_s
          connection_url = uri.to_s
        end
        new(adapter, connection_url, pool_options, app.config.db_query_timeout)
      end

      # The adapter in use.
      getter adapter : Adapter

      # The underlying database pool.
      getter database : DB::Database

      # The checked-out transaction connection, keyed by the fiber that owns
      # the transaction. Each fiber gets its own connection, so concurrent
      # transactions on the shared connection never clobber each other.
      @active_connections = {} of Fiber => DB::Connection

      # Savepoint counters, keyed by fiber, for nested transactions. Keeping
      # these per fiber guarantees a fiber never reuses another fiber's
      # savepoint name.
      @savepoint_counters = {} of Fiber => Int32

      # Serializes access to the two maps above. Requests run on a shared
      # execution context whose fibers can migrate between OS threads, so an
      # unsynchronized map corrupts under parallel load — a fiber would then
      # freeze inside `delete`, stranding its transaction connection open
      # forever. The lock is held only around a map operation, never around
      # query execution or the transaction body.
      @lock = Mutex.new

      # The number of fibers currently inside a transaction. Read without
      # the lock by every statement: when it is zero, no fiber owns a
      # transaction connection, and the per-query `active_connection` check
      # short-circuits to `nil` instead of paying a mutex acquisition that
      # every fiber on every thread would otherwise contend on.
      @active_transactions = Atomic(Int32).new(0)

      def initialize(@adapter : Adapter, url : String, pool_options : DB::Pool::Options, @query_timeout : Time::Span)
        @database = @adapter.connect(url, pool_options)
      end

      # Executes a statement with bound parameters, notifying the
      # instrumentation hooks. Every value travels as a bind parameter —
      # never interpolated into the SQL string. Inside a transaction the
      # statement runs on the calling fiber's transaction connection.
      # Acquisition wait is excluded from reported SQL time: the granular
      # `QueryEvent` carries checkout and sql durations separately. When no
      # query or event handler is registered the connection takes its
      # zero-cost path and never reads the clock.
      def exec(sql : String, *db_args, args : Enumerable? = nil) : DB::ExecResult
        if measure?
          measured_statement(sql, QueryEvent::Operation.from_sql(sql)) do |conn, meter|
            result = uninitialized DB::ExecResult
            meter.sql = measured do
              result = conn.fetch_or_build_prepared_statement(sql).exec(*db_args, args: args)
            end
            result
          end
        elsif conn = active_connection
          conn.fetch_or_build_prepared_statement(sql).exec(*db_args, args: args)
        elsif Altair::Record.checkout_hooks?
          run_checkout { @database.exec(sql, *db_args, args: args) }
        else
          @database.exec(sql, *db_args, args: args)
        end
      end

      # Runs a query with bound parameters, yielding each row to the
      # block. `values:` binds a variable-length collection, for
      # `IN (...)` clauses. Row-reading time is tracked as decode time in
      # the granular event, separate from the checkout wait.
      def query(sql : String, *args, values : Enumerable? = nil, &block : DB::ResultSet ->) : Nil
        if measure?
          measured_statement(sql, QueryEvent::Operation.from_sql(sql)) do |conn, meter|
            sql_started = Time.instant
            conn.query(sql, *args, args: values) do |rs|
              meter.sql = Time.instant - sql_started
              meter.add_decode(measured { block.call(rs) })
            end
          end
        elsif conn = active_connection
          conn.fetch_or_build_prepared_statement(sql).query(*args, args: values) do |rs|
            block.call(rs)
          end
        elsif Altair::Record.checkout_hooks?
          run_checkout do
            @database.query(sql, *args, args: values) do |rs|
              block.call(rs)
            end
          end
        else
          @database.query(sql, *args, args: values) do |rs|
            block.call(rs)
          end
        end
      end

      # Runs a query expecting a single row, yielded to the block.
      def query_one(sql : String, *args, &block : DB::ResultSet -> U) : U forall U
        if measure?
          measured_statement(sql, QueryEvent::Operation.from_sql(sql)) do |conn, meter|
            sql_started = Time.instant
            conn.query_one(sql, *args) do |rs|
              meter.sql = Time.instant - sql_started
              start = Time.instant
              value = block.call(rs)
              meter.add_decode(Time.instant - start)
              value
            end
          end
        elsif conn = active_connection
          conn.fetch_or_build_prepared_statement(sql).query(*args) do |rs|
            rs.move_next || raise DB::NoResultsError.new("No results")
            block.call(rs)
          end
        elsif Altair::Record.checkout_hooks?
          run_checkout do
            @database.query_one(sql, *args) { |rs| block.call(rs) }
          end
        else
          @database.query_one(sql, *args) { |rs| block.call(rs) }
        end
      end

      # Returns the last auto-generated id of an insert result.
      def last_insert_id(result : DB::ExecResult) : Int64
        @adapter.last_insert_id(result)
      end

      # Runs the block inside a transaction; the transaction rolls back
      # when the block raises, and the raise propagates. Statements inside
      # the block reuse the transaction's connection, so the pool is never
      # double-checked-out. A nested call runs on a savepoint of the
      # current transaction instead of checking out another connection.
      # The active connection is tracked per fiber, so concurrent fibers
      # each get an isolated transaction.
      def transaction(&block : Proc(Nil)) : Nil
        fiber = Fiber.current
        if active?(fiber)
          savepoint_transaction(fiber) { block.call }
        elsif Altair::Record.checkout_hooks?
          run_checkout do
            @database.transaction do |tx|
              register_active(fiber, tx.connection)
              begin
                block.call
              ensure
                clear_active(fiber)
              end
            end
          end
        else
          @database.transaction do |tx|
            register_active(fiber, tx.connection)
            begin
              block.call
            ensure
              clear_active(fiber)
            end
          end
        end
      end

      # Runs the block on a savepoint of the active transaction. A raise
      # rolls back to the savepoint and propagates; `DB::Rollback` rolls
      # back to the savepoint only, discarding its work without aborting
      # the outer transaction.
      private def savepoint_transaction(fiber : Fiber, &block : Proc(Nil)) : Nil
        name = "altair_sp_#{next_savepoint_counter(fiber)}"
        exec("SAVEPOINT #{@adapter.quote_identifier(name)}")
        begin
          block.call
        rescue DB::Rollback
          exec("ROLLBACK TO #{@adapter.quote_identifier(name)}")
          exec("RELEASE #{@adapter.quote_identifier(name)}")
          return
        rescue ex
          exec("ROLLBACK TO #{@adapter.quote_identifier(name)}")
          exec("RELEASE #{@adapter.quote_identifier(name)}")
          raise ex
        end
        exec("RELEASE #{@adapter.quote_identifier(name)}")
      end

      # Whether the fiber owns a transaction connection.
      private def active?(fiber : Fiber) : Bool
        @lock.synchronize { @active_connections.has_key?(fiber) }
      end

      # The calling fiber's active transaction connection, if any. The fast
      # path reads an atomic counter instead of the mutex: when no
      # transaction is active anywhere the answer is always `nil`.
      private def active_connection : DB::Connection?
        return if @active_transactions.get == 0
        @lock.synchronize { @active_connections[Fiber.current]? }
      end

      # Records the fiber as the owner of a transaction connection. The
      # counter increments before the map write so a concurrent statement
      # that reads it never misses a registered transaction.
      private def register_active(fiber : Fiber, connection : DB::Connection) : Nil
        @active_transactions.add(1)
        @lock.synchronize { @active_connections[fiber] = connection }
      end

      # Drops the fiber's transaction state once its transaction ends. The
      # counter decrements after the map delete so a concurrent statement
      # only ever sees a consistent pair.
      private def clear_active(fiber : Fiber) : Nil
        @lock.synchronize do
          @active_connections.delete(fiber)
          @savepoint_counters.delete(fiber)
        end
        @active_transactions.sub(1)
      end

      # The next savepoint name, unique within the fiber's transaction.
      private def next_savepoint_counter(fiber : Fiber) : Int32
        @lock.synchronize do
          count = @savepoint_counters[fiber]? || 0
          @savepoint_counters[fiber] = count + 1
          count
        end
      end

      # Closes the pool. Tests call this to release file handles.
      def close : Nil
        @database.close
      end

      # Runs the registered checkout hooks around a connection acquisition,
      # preserving the block's return value.
      private def run_checkout(&block : -> U) : U forall U
        Altair::Record.run_checkout_hooks(&block)
      end

      # Whether any timing hook is registered. The zero-cost path (no clock
      # reads) is taken only when this is false.
      private def measure? : Bool
        Altair::Record.query_handlers? || Altair::Record.query_event_handlers?
      end

      # Runs the block and returns how long it took.
      private def measured(& : -> U) : Time::Span forall U
        start = Time.instant
        yield
        Time.instant - start
      end

      # Runs a statement with granular timing, reporting a `QueryEvent`
      # regardless of success. Inside a transaction the connection is already
      # held, so checkout wait is zero. Otherwise the acquisition wait (the
      # admission gate plus the pool checkout) is timed separately from the
      # SQL execution, and the connection is always returned to the pool —
      # even when the statement raises or the checkout times out.
      private def measured_statement(
        sql : String,
        op : QueryEvent::Operation,
        &block : DB::Connection, QueryMeter -> U
      ) : U forall U
        meter = QueryMeter.new
        started = Time.instant
        success = true
        result = uninitialized U
        begin
          if conn = active_connection
            # The statement-specific runner records SQL and decode spans at
            # their exact boundaries. Wrapping the whole block here would
            # fold row decoding back into sql_time for transactions.
            result = block.call(conn, meter)
          else
            checkout_started = Time.instant
            inner = ->(cn : DB::Connection) {
              meter.checkout = Time.instant - checkout_started
              result = block.call(cn, meter)
              nil
            }
            callback = ->(run : Proc(DB::Connection, Nil)) {
              @database.retry do
                checked = uninitialized DB::Connection
                begin
                  checked = @database.checkout
                rescue ex
                  meter.checkout = Time.instant - checkout_started
                  raise ex
                end
                begin
                  run.call(checked)
                ensure
                  checked.release
                end
              end
            }
            if Altair::Record.checkout_hooks?
              run_checkout { callback.call(inner) }
            else
              callback.call(inner)
            end
          end
        rescue ex
          success = false
          meter.checkout = Time.instant - started if meter.checkout.zero? && !active_connection
          raise ex
        ensure
          if Altair::Record.query_event_handlers?
            Altair::Record.notify_query_event(
              sql, @adapter.class.name, op,
              meter.checkout, meter.sql, meter.decode, success
            )
          end
          if Altair::Record.query_handlers?
            Altair::Record.notify_query(sql, Time.instant - started)
          end
        end
        result
      end

      # Pool statistics read on demand (for observability). Reading them is
      # opt-in and never runs in the hot path.
      def pool_stats : DB::Pool::Stats?
        @database.pool.stats
      end
    end

    # Accumulates timing for a single statement, shared between the measured
    # runner and the row-reading block so decode time can be summed across
    # many rows without leaking through the block's return value.
    class QueryMeter
      property checkout : Time::Span = Time::Span::ZERO
      property sql : Time::Span = Time::Span::ZERO
      property decode : Time::Span = Time::Span::ZERO

      # Adds a row-reading span to the running decode total.
      def add_decode(span : Time::Span) : Nil
        @decode += span
      end
    end
  end
end
