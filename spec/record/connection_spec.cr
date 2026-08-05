# Altair — the record connection layer.
#
# Specs for the connection wrapper: opening from the application config,
# executing statements with bound parameters, the last-insert-id path and
# the instrumentation hook every query passes through.
require "../spec_helper"

private def spec_connection : Altair::Record::Connection
  conn = Altair::Record.connection_for(SpecApp.instance)
  conn.exec("DROP TABLE IF EXISTS widgets")
  conn.exec("CREATE TABLE widgets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)")
  conn
end

# A connection allowed to grow beyond the single-connection test pool, so
# concurrent transactions each get their own pooled connection. The pool is
# fully warm (initial = idle = max) so the leak assertions below can compare
# open versus idle counts exactly.
private def concurrent_connection : Altair::Record::Connection
  app = SpecApp.instance
  original = {
    initial: app.config.db_initial_pool_size,
    max:     app.config.db_max_pool_size,
    idle:    app.config.db_max_idle_pool_size,
  }
  app.config.db_initial_pool_size = 16
  app.config.db_max_pool_size = 16
  app.config.db_max_idle_pool_size = 16
  begin
    conn = Altair::Record.connection_for(app)
    conn.exec("DROP TABLE IF EXISTS widgets")
    conn.exec("CREATE TABLE widgets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)")
    conn
  ensure
    app.config.db_initial_pool_size = original[:initial]
    app.config.db_max_pool_size = original[:max]
    app.config.db_max_idle_pool_size = original[:idle]
  end
end

# Whether the backend allows several concurrent writers across connections.
# SQLite is single-writer, so true concurrency is only possible on a server
# database (PostgreSQL).
private def parallel_writers?(conn : Altair::Record::Connection) : Bool
  !conn.adapter.class.name.includes?("SQLite")
end

describe Altair::Record::Connection do
  it "opens a connection from the application config" do
    conn = Altair::Record.connection_for(SpecApp.instance)
    conn.database.is_a?(DB::Database).should be_true
    conn.close
  end

  it "passes the application's pool settings into the database pool" do
    app = SpecApp.instance
    original = {
      initial: app.config.db_initial_pool_size,
      max:     app.config.db_max_pool_size,
      idle:    app.config.db_max_idle_pool_size,
    }
    app.config.db_initial_pool_size = 2
    app.config.db_max_pool_size = 8
    app.config.db_max_idle_pool_size = 4
    begin
      conn = Altair::Record.connection_for(app)
      stats = conn.database.pool.stats
      stats.max_connections.should eq(8)
      stats.open_connections.should eq(2)
      stats.idle_connections.should eq(2)
    ensure
      conn.try(&.close)
      app.config.db_initial_pool_size = original[:initial]
      app.config.db_max_pool_size = original[:max]
      app.config.db_max_idle_pool_size = original[:idle]
    end
  end

  it "raises a configuration error without a db_url" do
    app = SpecApp.instance
    old_url = app.config.db_url
    app.config.db_url = nil
    begin
      expect_raises(Altair::ConfigurationError, /No database configured/) do
        Altair::Record::Connection.for(app)
      end
    ensure
      app.config.db_url = old_url
    end
  end

  it "executes with bound parameters and reports the last insert id" do
    conn = spec_connection
    begin
      result = conn.exec("INSERT INTO widgets (name) VALUES (?)", "alpha")
      conn.last_insert_id(result).should be > 0
    ensure
      conn.close
    end
  end

  it "queries rows through the block API" do
    conn = spec_connection
    begin
      conn.exec("INSERT INTO widgets (name) VALUES (?)", "alpha")
      names = [] of String
      conn.query("SELECT name FROM widgets ORDER BY id") do |rs|
        rs.each { names << rs.read(String) }
      end
      names.should eq(["alpha"])
    ensure
      conn.close
    end
  end

  it "never interpolates values into SQL" do
    conn = spec_connection
    begin
      conn.exec("INSERT INTO widgets (name) VALUES (?)", "a'b; DROP TABLE widgets")
      count = conn.query_one("SELECT COUNT(*) FROM widgets") { |rs| rs.read(Int64) }
      count.should eq(1)
    ensure
      conn.close
    end
  end

  it "notifies on_query handlers with the sql and duration" do
    conn = spec_connection
    seen = [] of String
    begin
      handler = ->(sql : String, _duration : Time::Span) { seen << sql }
      Altair::Record.on_query(&handler)
      conn.exec("INSERT INTO widgets (name) VALUES (?)", "beta")
      conn.exec("SELECT COUNT(*) FROM widgets")
      seen.size.should eq(2)
      seen[0].should contain("INSERT INTO widgets")
    ensure
      conn.close
    end
  end

  it "commits a transaction when the block succeeds" do
    conn = spec_connection
    begin
      conn.transaction do
        conn.exec("INSERT INTO widgets (name) VALUES (?)", "kept")
      end
      count = conn.query_one("SELECT COUNT(*) FROM widgets") { |rs| rs.read(Int64) }
      count.should eq(1)
    ensure
      conn.close
    end
  end

  it "rolls back a transaction when the block raises" do
    conn = spec_connection
    begin
      expect_raises(Exception) do
        conn.transaction do
          conn.exec("INSERT INTO widgets (name) VALUES (?)", "doomed")
          raise "boom"
        end
      end
      count = conn.query_one("SELECT COUNT(*) FROM widgets") { |rs| rs.read(Int64) }
      count.should eq(0)
    ensure
      conn.close
    end
  end

  it "isolates concurrent transactions across fibers" do
    conn = concurrent_connection
    unless parallel_writers?(conn)
      pending! "SQLite serializes writers — run this on a server database"
      conn.close
    end
    n = 4
    arrived = Channel(Nil).new
    go = Channel(Nil).new
    completed = Channel(Int32).new

    n.times do |i|
      spawn do
        conn.transaction do
          conn.exec("INSERT INTO widgets (name) VALUES (?)", "fiber-#{i}")
          arrived.send(nil)
          go.receive
        end
        completed.send(1)
      end
    end

    n.times { arrived.receive }
    n.times { go.send(nil) }
    total = 0
    n.times { total += completed.receive }
    total.should eq(n)
    count = conn.query_one("SELECT COUNT(*) FROM widgets") { |rs| rs.read(Int64) }
    count.should eq(n)
    conn.close
  end

  it "keeps a rolling-back fiber from rolling back another fiber's work" do
    conn = concurrent_connection
    unless parallel_writers?(conn)
      pending! "SQLite serializes writers — run this on a server database"
      conn.close
    end
    arrived = Channel(Nil).new
    go = Channel(Nil).new
    done = Channel(Int32).new

    # A enters its transaction first and will roll back (raises at the end).
    spawn do
      begin
        conn.transaction do
          conn.exec("INSERT INTO widgets (name) VALUES (?)", "doomed-A")
          arrived.send(nil)
          go.receive
          raise "rollback A"
        end
      rescue
      end
      done.send(1)
    end

    arrived.receive
    # B now starts a transaction while A's transaction is still open. B is
    # independent and must commit its own insert.
    spawn do
      conn.transaction do
        conn.exec("INSERT INTO widgets (name) VALUES (?)", "kept-B")
      end
      done.send(1)
    end

    go.send(nil)
    2.times { done.receive }
    count = conn.query_one("SELECT COUNT(*) FROM widgets") { |rs| rs.read(Int64) }
    count.should eq(1)
    conn.close
  end

  it "returns every pooled connection after a batch of transactions" do
    conn = concurrent_connection
    begin
      32.times do
        conn.transaction do
          conn.exec("INSERT INTO widgets (name) VALUES (?)", "row")
        end
      end
      stats = conn.database.pool.stats
      stats.open_connections.should eq(16)
      stats.idle_connections.should eq(16)
    ensure
      conn.close
    end
  end

  it "runs checkout hooks around a connection acquisition, preserving its value" do
    conn = spec_connection
    around = 0
    handler = ->(run : Proc(Nil)) {
      around += 1
      run.call
    }
    Altair::Record.on_checkout(&handler)
    count = conn.query_one("SELECT COUNT(*) FROM widgets") { |rs| rs.read(Int64) }
    count.should eq(0)
    around.should eq(1)
    conn.close
  end

  it "wraps a transaction once as a single acquisition, not once per statement" do
    conn = spec_connection
    around = 0
    handler = ->(run : Proc(Nil)) {
      around += 1
      run.call
    }
    Altair::Record.on_checkout(&handler)
    begin
      conn.transaction do
        conn.exec("INSERT INTO widgets (name) VALUES (?)", "one")
        conn.exec("INSERT INTO widgets (name) VALUES (?)", "two")
      end
    ensure
      conn.close
    end
    around.should eq(1)
  end

  it "does not re-wrap statements inside an active transaction" do
    conn = spec_connection
    around = 0
    handler = ->(run : Proc(Nil)) {
      around += 1
      run.call
    }
    Altair::Record.on_checkout(&handler)
    begin
      conn.transaction do
        conn.exec("INSERT INTO widgets (name) VALUES (?)", "one")
        count = conn.query_one("SELECT COUNT(*) FROM widgets") { |rs| rs.read(Int64) }
        count.should eq(1)
      end
    ensure
      conn.close
    end
    around.should eq(1)
  end
end
