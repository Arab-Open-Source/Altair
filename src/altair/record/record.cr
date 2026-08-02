# Altair — the batteries-included web framework for Crystal.
#
# This file defines the `Altair::Record` module, the ORM layer's public
# entry: the application connection, the query instrumentation hook and
# the migration runner. Models (Phase 4 wave 2) build on top of it.
module Altair
  module Record
    # The application's connection, opened lazily from `config.db_url` on
    # first use. Raises `Altair::ConfigurationError` when no database is
    # configured.
    def self.connection : Connection
      app = Altair.application_instance
      raise Altair::ConfigurationError.new("No application instance") unless app
      @@connection ||= Connection.for(app)
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

    # Notifies the instrumentation hooks. Called by the connection.
    def self.notify_query(sql : String, duration : Time::Span) : Nil
      @@query_handlers.each &.call(sql, duration)
    end

    @@query_handlers = [] of Proc(String, Time::Span, Nil)
    @@connection : Connection? = nil

    # Closes the pooled connection (used by specs and runner scripts).
    def self.close_connection : Nil
      @@connection.try(&.close)
      @@connection = nil
    end
  end
end
