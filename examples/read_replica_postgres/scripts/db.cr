require "altair"
require "altair/record/adapters/postgresql"
require "../db/schema"
require "../db/migrations/20261127210000_create_items"
require "../src/app"

connection = Altair::Record::Connection.for(ReadReplicaPostgres.instance)
runner = Altair::Record::Migrations::Runner.new(
  connection,
  Path.new("db/migrations"),
  Path.new("db/schema.cr"),
  connection.adapter
)

case ARGV[0]?
when "migrate"
  count = runner.migrate
  puts count.zero? ? "Already up to date." : "Applied #{count} migration(s) on the primary."
when "rollback"
  puts runner.rollback ? "Rolled back one migration on the primary." : "Nothing to roll back."
else
  abort "usage: crystal run scripts/db.cr migrate|rollback"
end

connection.close
