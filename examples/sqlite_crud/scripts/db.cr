# Applies or rolls back the SQLite example migration.
require "altair"
require "../db/schema"
require "../src/application"
require "../db/migrations/20260802010000_create_products"

connection = Altair::Record::Connection.for(SQLiteCrud.instance)
runner = Altair::Record::Migrations::Runner.new(
  connection,
  Path.new("db/migrations"),
  Path.new("db/schema.cr"),
  connection.adapter
)

case ARGV[0]?
when "migrate"
  puts "Applied #{runner.migrate} migration(s)."
when "rollback"
  puts runner.rollback ? "Rolled back one migration." : "Nothing to roll back."
else
  abort "usage: crystal run scripts/db.cr -- migrate|rollback"
end

connection.close
