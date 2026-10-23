# Specs for read replicas (config.db_replica_url): plain SELECTs route to
# the replica pool, writes and transactions pin the fiber's reads to the
# primary, and the primary never sees replica-routed traffic. Two SQLite
# files make the routing observable: a row written directly on the primary
# is invisible to a replica-routed read, and vice versa.
require "../spec_helper"
require "./model_fixtures_spec"

class ReplicaNote < Altair::Record::Model
  table :replica_notes
end

module ReplicaSpec
  ROOT = Path[File.join(__DIR__, "..")].expand.to_s

  def self.reset_files : Nil
    File.delete(ROOT + "/record/replica-primary.db") if File.exists?(ROOT + "/record/replica-primary.db")
    File.delete(ROOT + "/record/replica-replica.db") if File.exists?(ROOT + "/record/replica-replica.db")
  end

  def self.create_table(connection : Altair::Record::Connection) : Nil
    connection.exec(
      "CREATE TABLE IF NOT EXISTS replica_notes (" \
      "id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT, " \
      "created_at DATETIME, updated_at DATETIME)"
    )
  end

  # A standalone pool over one URL, used to prepare each database's schema
  # without touching the Record connection — an `exec` on that one would
  # pin the calling fiber's reads to the primary.
  def self.setup_pool(url : String) : Altair::Record::Connection
    pool = Altair::Record::Connection.new(
      Altair::Record::Adapters::SQLite3.instance, url, DB::Pool::Options.new, 5.seconds
    )
    create_table(pool)
    pool
  end
end

class ReplicaApp < Altair::Application
  # URLs are set per example in `with_replica_app` — class bodies run at
  # file load, when the shared application instance already exists.
end

private def with_replica_app(& : Altair::Record::Connection -> Nil) : Nil
  ReplicaSpec.reset_files
  primary_setup = ReplicaSpec.setup_pool("sqlite3://./spec/record/replica-primary.db")
  replica_setup = ReplicaSpec.setup_pool("sqlite3://./spec/record/replica-replica.db")
  previous = Altair.application_instance
  Altair.application_instance = nil
  Altair::Record.close_connection
  begin
    app = ReplicaApp.instance
    app.config.name = "ReplicaApp"
    app.config.db_url = "sqlite3://./spec/record/replica-primary.db"
    app.config.db_replica_url = "sqlite3://./spec/record/replica-replica.db"
    connection = Altair::Record.connection
    yield connection
  ensure
    Altair::Record.close_connection
    Altair.application_instance = previous
    primary_setup.close
    replica_setup.close
    ReplicaSpec.reset_files
  end
end

describe "read replicas" do
  it "routes plain SELECTs to the replica pool" do
    with_replica_app do |connection|
      connection.replica.should_not be_nil
      connection.replica_routed?.should be_true
      connection.exec("INSERT INTO replica_notes (body) VALUES ('primary only')")
      # The exec pinned this fiber; a fresh fiber (no writes yet) reads the
      # replica, which never saw the primary-only row.
      results = Channel(Int32).new(1)
      spawn(name: "replica-probe") { results.send(ReplicaNote.all.to_a.size) }
      results.receive.should eq(0)
    end
  end

  it "pins reads to the primary after a write on the same fiber" do
    with_replica_app do |connection|
      ReplicaNote.create(body: "mine")
      connection.replica_routed?.should be_false
      ReplicaNote.all.to_a.size.should eq(1)
    end
  end

  it "keeps transactional reads on the primary" do
    with_replica_app do |connection|
      ReplicaNote.transaction do
        connection.replica_routed?.should be_false
        connection.exec("INSERT INTO replica_notes (body) VALUES ('in tx')")
        ReplicaNote.all.to_a.size.should eq(1)
      end
      # Reads stay pinned after the transaction ends (same fiber).
      connection.replica_routed?.should be_false
    end
  end

  it "keeps writes on the primary and out of the replica" do
    with_replica_app do |connection|
      connection.exec("INSERT INTO replica_notes (body) VALUES ('count me')")
      replica_view = ReplicaSpec.setup_pool("sqlite3://./spec/record/replica-replica.db")
      begin
        replica_view.query_one?("SELECT count(*) FROM replica_notes") { |rs| rs.read(Int64) }.should eq(0)
      ensure
        replica_view.close
      end
    end
  end
end
