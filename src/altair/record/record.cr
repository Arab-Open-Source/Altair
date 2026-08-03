# Altair — the batteries-included web framework for Crystal.
#
# This file defines the `Altair::Record` module, the ORM layer's public
# entry: the application connection, the query instrumentation hook and
# the migration runner. Models (Phase 4 wave 2) build on top of it.
module Altair
  module Record
    # The application's connection, opened lazily from `config.db_url` on
    # first use. Raises `Altair::ConfigurationError` when no database is
    # configured. The open is synchronized: under first-touch load many
    # threads can call this at once, and an unsynchronized `||=` would open
    # several pools instead of one.
    def self.connection : Connection
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

    @@query_handlers = [] of Proc(String, Time::Span, Nil)
    @@connection : Connection? = nil
    @@connection_lock = Mutex.new

    # Closes the pooled connection (used by specs and runner scripts).
    def self.close_connection : Nil
      @@connection_lock.synchronize do
        @@connection.try(&.close)
        @@connection = nil
      end
    end
  end
end
