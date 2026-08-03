# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Record::Connection`, the framework's database
# connection. It wraps a `DB::Database` pool with an adapter, applies the
# application's pool settings, and exposes an instrumentation hook —
# `Altair::Record.on_query` — that every executed statement passes through,
# the base for query logging and N+1 detection later.
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
        new(adapter, url, pool_options, app.config.db_query_timeout)
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

      def initialize(@adapter : Adapter, url : String, pool_options : DB::Pool::Options, @query_timeout : Time::Span)
        @database = @adapter.connect(url, pool_options)
      end

      # Executes a statement with bound parameters, notifying the
      # instrumentation hooks. Every value travels as a bind parameter —
      # never interpolated into the SQL string. Inside a transaction the
      # statement runs on the calling fiber's transaction connection.
      def exec(sql : String, *db_args, args : Enumerable? = nil) : DB::ExecResult
        start = Time.instant
        result = if conn = active_connection
                   conn.fetch_or_build_prepared_statement(sql).exec(*db_args, args: args)
                 else
                   @database.exec(sql, *db_args, args: args)
                 end
        notify(sql, Time.instant - start)
        result
      end

      # Runs a query with bound parameters, yielding each row to the
      # block. `values:` binds a variable-length collection, for
      # `IN (...)` clauses.
      def query(sql : String, *args, values : Enumerable? = nil, & : DB::ResultSet ->) : Nil
        start = Time.instant
        if conn = active_connection
          conn.fetch_or_build_prepared_statement(sql).query(*args, args: values) do |rs|
            yield rs
          end
        else
          @database.query(sql, *args, args: values) do |rs|
            yield rs
          end
        end
        notify(sql, Time.instant - start)
      end

      # Runs a query expecting a single row, yielded to the block.
      def query_one(sql : String, *args, & : DB::ResultSet -> U) : U forall U
        start = Time.instant
        result = if conn = active_connection
                   conn.fetch_or_build_prepared_statement(sql).query(*args) do |rs|
                     rs.move_next || raise DB::NoResultsError.new("No results")
                     yield rs
                   end
                 else
                   @database.query_one(sql, *args) { |rs| yield rs }
                 end
        notify(sql, Time.instant - start)
        result
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
        if @active_connections.has_key?(fiber)
          savepoint_transaction(fiber) { block.call }
        else
          @database.transaction do |tx|
            @active_connections[fiber] = tx.connection
            begin
              block.call
            ensure
              @active_connections.delete(fiber)
              @savepoint_counters.delete(fiber)
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

      # The calling fiber's active transaction connection, if any.
      private def active_connection : DB::Connection?
        @active_connections[Fiber.current]?
      end

      # The next savepoint name, unique within the fiber's transaction.
      private def next_savepoint_counter(fiber : Fiber) : Int32
        count = @savepoint_counters[fiber]? || 0
        @savepoint_counters[fiber] = count + 1
        count
      end

      # Closes the pool. Tests call this to release file handles.
      def close : Nil
        @database.close
      end

      private def notify(sql : String, duration : Time::Span) : Nil
        Altair::Record.notify_query(sql, duration)
      end
    end
  end
end
