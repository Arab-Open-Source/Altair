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

describe Altair::Record::Connection do
  it "opens a connection from the application config" do
    conn = Altair::Record.connection_for(SpecApp.instance)
    conn.database.is_a?(DB::Database).should be_true
    conn.close
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
end
