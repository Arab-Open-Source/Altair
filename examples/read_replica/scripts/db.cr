require "altair"
require "../db/schema"
require "./../db/migrations/20261024000001_create_notes"
require "./../src/app"

# Migrates the primary AND the replica — both pools need the schema for
# read routing to serve real rows.
primary = Altair::Record::Connection.for(ReplicaDemo.instance)
replica_url = ReplicaDemo.instance.config.db_replica_url
unless replica_url
  abort "config.db_replica_url is not set"
end
replica = Altair::Record::Connection.new(
  primary.adapter,
  replica_url,
  DB::Pool::Options.new,
  5.seconds
)

case ARGV[0]?
when "migrate"
  [primary, replica].each do |conn|
    runner = Altair::Record::Migrations::Runner.new(
      conn,
      Path.new("db/migrations"),
      Path.new("db/schema.cr"),
      conn.adapter
    )
    count = runner.migrate
    puts count.zero? ? "Already up to date." : "Applied #{count} migration(s)."
  end
when "rollback"
  [primary, replica].each do |conn|
    runner = Altair::Record::Migrations::Runner.new(
      conn,
      Path.new("db/migrations"),
      Path.new("db/schema.cr"),
      conn.adapter
    )
    puts runner.rollback ? "Rolled back one migration." : "Nothing to roll back."
  end
else
  abort "usage: crystal run scripts/db.cr migrate|rollback"
end

replica.close
primary.close
