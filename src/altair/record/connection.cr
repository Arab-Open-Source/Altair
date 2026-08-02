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
      def self.for(app : Altair::Application) : Connection
        url = app.config.db_url
        raise Altair::ConfigurationError.new(
          "No database configured: set config.db_url, e.g. \"sqlite3://./db/app.db\""
        ) unless url
        pool_options = DB::Pool::Options.new(
          max_pool_size: app.config.db_max_pool_size,
          checkout_timeout: app.config.db_checkout_timeout
        )
        new(Adapters::SQLite3.instance, url, pool_options, app.config.db_query_timeout)
      end

      # The adapter in use.
      getter adapter : Adapter

      # The underlying database pool.
      getter database : DB::Database

      # The checked-out transaction connection, while a transaction runs.
      @active_connection : DB::Connection?

      def initialize(@adapter : Adapter, url : String, pool_options : DB::Pool::Options, @query_timeout : Time::Span)
        @database = @adapter.connect(url, pool_options)
        @active_connection = nil
      end

      # Executes a statement with bound parameters, notifying the
      # instrumentation hooks. Every value travels as a bind parameter —
      # never interpolated into the SQL string. Inside a transaction the
      # statement runs on the transaction's checked-out connection.
      def exec(sql : String, *args) : DB::ExecResult
        start = Time.instant
        result = if conn = @active_connection
                   conn.fetch_or_build_prepared_statement(sql).exec(*args)
                 else
                   @database.exec(sql, *args)
                 end
        notify(sql, Time.instant - start)
        result
      end

      # Runs a query with bound parameters, yielding each row to the block.
      def query(sql : String, *args, &block : DB::ResultSet ->) : Nil
        start = Time.instant
        if conn = @active_connection
          conn.fetch_or_build_prepared_statement(sql).query(*args) do |rs|
            yield rs
          end
        else
          @database.query(sql, *args) do |rs|
            yield rs
          end
        end
        notify(sql, Time.instant - start)
      end

      # Runs a query expecting a single row, yielded to the block.
      def query_one(sql : String, *args, &block : DB::ResultSet -> U) : U forall U
        start = Time.instant
        result = if conn = @active_connection
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
      # double-checked-out.
      def transaction(&block : Proc(Nil)) : Nil
        @database.transaction do |tx|
          previous = @active_connection
          @active_connection = tx.connection
          begin
            block.call
          ensure
            @active_connection = previous
          end
        end
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
