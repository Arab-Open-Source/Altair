# SQLite-backed application configuration.
class SQLiteCrud < Altair::Application
  config.name = "SQLite CRUD"
  config.port = 4100
  config.db_url = ENV["DATABASE_URL"]? || "sqlite3://./db/crud.db"
end
