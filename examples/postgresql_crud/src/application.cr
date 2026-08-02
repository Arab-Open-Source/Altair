# PostgreSQL-backed application configuration.
require "altair/record/adapters/postgresql"

class PostgreSQLCrud < Altair::Application
  config.name = "PostgreSQL CRUD"
  config.port = 4200
  config.db_url = ENV["DATABASE_URL"]? || raise(
    Altair::ConfigurationError.new("Set DATABASE_URL to a PostgreSQL URL")
  )
end
