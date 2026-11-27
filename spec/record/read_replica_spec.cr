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

  it "does not let another fiber's transaction disable replica routing" do
    with_replica_app do |connection|
      entered = Channel(Nil).new(1)
      release = Channel(Nil).new(1)
      errors = Channel(Exception?).new(1)

      spawn(name: "replica-transaction") do
        connection.transaction do
          connection.exec("INSERT INTO replica_notes (body) VALUES ('transaction only')")
          entered.send(nil)
          release.receive
        end
        errors.send(nil)
      rescue e
        errors.send(e)
      end

      select
      when entered.receive
      when timeout(5.seconds)
        raise "transaction fiber did not enter"
      end

      begin
        connection.replica_routed?.should be_true
        ReplicaNote.all.to_a.size.should eq(0)
      ensure
        release.send(nil)
        select
        when error = errors.receive
          raise error if error
        when timeout(5.seconds)
          raise "transaction fiber did not finish"
        end
      end
    end
  end

  it "keeps replica routing when checkout hooks are registered" do
    with_replica_app do |connection|
      primary_view = ReplicaSpec.setup_pool("sqlite3://./spec/record/replica-primary.db")
      begin
        primary_view.exec("INSERT INTO replica_notes (body) VALUES ('primary only')")
      ensure
        primary_view.close
      end

      called = false
      Altair::Record.on_checkout do |run|
        called = true
        run.call
      end

      connection.replica_routed?.should be_true
      ReplicaNote.all.to_a.size.should eq(0)
      connection.query_one("SELECT count(*) FROM replica_notes") { |rs| rs.read(Int64) }.should eq(0)
      called.should be_true
    end
  end

  it "keeps replica routing when admission control is enabled" do
    with_replica_app do |_connection|
      primary_view = ReplicaSpec.setup_pool("sqlite3://./spec/record/replica-primary.db")
      begin
        primary_view.exec("INSERT INTO replica_notes (body) VALUES ('primary only')")
      ensure
        primary_view.close
      end

      Altair::Record::PermitGate.enable(1)
      begin
        ReplicaNote.all.to_a.size.should eq(0)
      ensure
        Altair::Record::PermitGate.enable(0)
      end
    end
  end

  it "keeps replica routing when query instrumentation is registered" do
    with_replica_app do |_connection|
      primary_view = ReplicaSpec.setup_pool("sqlite3://./spec/record/replica-primary.db")
      begin
        primary_view.exec("INSERT INTO replica_notes (body) VALUES ('primary only')")
      ensure
        primary_view.close
      end

      called = false
      Altair::Record.on_query do |_sql, _elapsed|
        called = true
      end

      ReplicaNote.all.to_a.size.should eq(0)
      called.should be_true
    end
  end

  it "supports explicit primary reads through Relation#on_primary" do
    with_replica_app do |connection|
      primary_view = ReplicaSpec.setup_pool("sqlite3://./spec/record/replica-primary.db")
      begin
        primary_view.exec("INSERT INTO replica_notes (body) VALUES ('primary only')")
      ensure
        primary_view.close
      end

      relation = ReplicaNote.all
      relation.to_a.size.should eq(0)
      relation.on_primary.to_a.size.should eq(1)
      connection.replica_routed?.should be_true
    end
  end

  it "labels query events with their database target" do
    with_replica_app do |connection|
      events = [] of Altair::Record::QueryEvent
      Altair::Record.on_query_event { |event| events << event }

      ReplicaNote.all.to_a
      events.last.target.should eq(Altair::Record::QueryEvent::Target::Replica)

      connection.exec("INSERT INTO replica_notes (body) VALUES ('primary')")
      events.last.target.should eq(Altair::Record::QueryEvent::Target::Primary)

      ReplicaNote.all.on_primary.to_a
      events.last.target.should eq(Altair::Record::QueryEvent::Target::Primary)
    end
  end

  it "counts statements per target" do
    with_replica_app do |connection|
      before = connection.query_target_metrics

      ReplicaNote.all.to_a
      connection.query_one("SELECT count(*) FROM replica_notes") { |rs| rs.read(Int64) }
      ReplicaNote.create(body: "primary")
      ReplicaNote.all.on_primary.to_a

      after = connection.query_target_metrics
      (after[:replica] - before[:replica]).should eq(2)
      (after[:primary] - before[:primary]).should be >= 2
    end
  end

  it "falls back to the primary when the replica is unavailable and recovers" do
    primary_url = "sqlite3://./spec/record/replica-failover-primary.db"
    replica_url = "sqlite3://./spec/record/replica-failover-down/replica.db"
    missing_dir = "spec/record/replica-failover-down"

    [primary_url, replica_url].each do |url|
      path = url.sub("sqlite3://", "")
      File.delete?(path)
      File.delete?("#{path}-wal")
      File.delete?("#{path}-shm")
    end
    Dir.delete?(missing_dir)

    primary_setup = ReplicaSpec.setup_pool(primary_url)
    primary_setup.exec("INSERT INTO replica_notes (body) VALUES ('primary only')")
    primary_setup.close

    replica = DB.open("#{replica_url}?initial_pool_size=0&max_pool_size=1&checkout_timeout=0.1&retry_attempts=1&retry_delay=0")
    connection = Altair::Record::Connection.new(
      Altair::Record::Adapters::SQLite3.instance,
      primary_url,
      DB::Pool::Options.new,
      5.seconds,
      replica,
      100.milliseconds
    )

    begin
      connection.query_one("SELECT count(*) FROM replica_notes") { |rs| rs.read(Int64) }.should eq(1)
      after_failure = connection.query_target_metrics
      after_failure[:failovers].should eq(1)
      after_failure[:primary].should eq(1)
      after_failure[:replica].should eq(0)

      # During the cooldown, reads stay on the primary without another attempt.
      connection.query_one("SELECT count(*) FROM replica_notes") { |rs| rs.read(Int64) }.should eq(1)
      after_cooldown = connection.query_target_metrics
      after_cooldown[:failovers].should eq(1)
      after_cooldown[:primary].should eq(2)

      Dir.mkdir_p(missing_dir)
      replica_setup = ReplicaSpec.setup_pool(replica_url)
      replica_setup.close
      sleep 150.milliseconds

      connection.query_one("SELECT count(*) FROM replica_notes") { |rs| rs.read(Int64) }.should eq(0)
      after_recovery = connection.query_target_metrics
      after_recovery[:failovers].should eq(1)
      after_recovery[:replica].should eq(1)
    ensure
      connection.close
      File.delete?(primary_url.sub("sqlite3://", ""))
      File.delete?(replica_url.sub("sqlite3://", ""))
      File.delete?("#{replica_url.sub("sqlite3://", "")}-wal")
      File.delete?("#{replica_url.sub("sqlite3://", "")}-shm")
      Dir.delete?(missing_dir)
    end
  end

  it "routes INSERT RETURNING through query_one to the primary" do
    with_replica_app do |connection|
      id = connection.query_one("INSERT INTO replica_notes (body) VALUES ('returning') RETURNING id") do |rs|
        rs.read(Int64)
      end
      id.should be > 0
      connection.replica_routed?.should be_false

      connection.query_one("SELECT count(*) FROM replica_notes") { |rs| rs.read(Int64) }.should eq(1)
      metrics = connection.query_target_metrics
      metrics[:primary].should be >= 2
      metrics[:replica].should eq(0)
    end
  end

  it "clears write stickiness when request-scoped state is cleared" do
    with_replica_app do |connection|
      ReplicaNote.create(body: "mine")
      connection.replica_routed?.should be_false

      Altair::Record.clear_fiber_state

      connection.replica_routed?.should be_true
      ReplicaNote.all.to_a.size.should eq(0)
    end
  end
end
