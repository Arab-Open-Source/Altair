# Altair — the record migrations layer.
#
# Specs for the migration runner: applying pending migrations in order,
# tracking versions, rolling back (with the irreversible guard) and
# regenerating `db/schema.cr` after every run. The migration classes are
# compiled into the suite like real migration files; the runner only needs
# the timestamped files to exist to know what is pending.
require "../spec_helper"
require "file_utils"

private class WaveOneCreatePosts < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:posts) do |t|
      t.string :title
      t.text :body, null: false
    end
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:posts)
  end
end

private class WaveOneAddComments < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:comments) do |t|
      t.string :body
      t.integer :post_id
    end
    schema.add_index(:comments, :post_id)
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:comments)
  end
end

private class WaveOneIrreversible < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:audit_logs) do |t|
      t.string :event
    end
  end
end

private class WaveOneExplodes < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:exploding) do |t|
      t.string :label
    end
    raise RuntimeError.new("boom")
  end
end

private def migrations_dir : Path
  dir = Path.new(Dir.tempdir, "altair_migrations_#{Random.rand(1_000_000)}")
  FileUtils.mkdir_p(dir)
  dir
end

private def with_runner(& : Altair::Record::Migrations::Runner, Altair::Record::Connection ->) : Nil
  dir = migrations_dir
  conn = Altair::Record::Connection.new(
    Altair::Record::Adapters::SQLite3.instance,
    "sqlite3://#{dir.join("test.db")}",
    DB::Pool::Options.new(max_pool_size: 1),
    5.seconds
  )
  runner = Altair::Record::Migrations::Runner.new(
    conn,
    dir,
    Path.new(Dir.tempdir, "altair_schema_#{Random.rand(1_000_000)}.cr"),
    Altair::Record::Adapters::SQLite3.instance
  )
  begin
    yield runner, conn
  ensure
    conn.close
    FileUtils.rm_rf(dir)
  end
end

describe Altair::Record::Migrations::Runner do
  it "applies pending migrations in file order" do
    with_runner do |runner, conn|
      File.write(runner.migrations_dir.join("20260802000001_create_posts.cr"), "")
      File.write(runner.migrations_dir.join("20260802000002_add_comments.cr"), "")
      runner.migrate.should eq(2)
      runner.applied_versions.should eq([
        "20260802000001_create_posts",
        "20260802000002_add_comments",
      ])
      tables = conn.query_one("SELECT COUNT(*) FROM posts") { |rs| rs.read(Int64) }
      tables.should eq(0)
      generated = File.read(runner.schema_path)
      generated.should contain("t.index [:post_id], unique: false, name: \"index_comments_on_post_id\"")
    end
  end

  it "skips already applied migrations" do
    with_runner do |runner, _|
      File.write(runner.migrations_dir.join("20260802000001_create_posts.cr"), "")
      runner.migrate.should eq(1)
      runner.migrate.should eq(0)
    end
  end

  it "regenerates schema.cr after migrating" do
    with_runner do |runner, _|
      File.write(runner.migrations_dir.join("20260802000001_create_posts.cr"), "")
      runner.migrate
      generated = File.read(runner.schema_path)
      generated.should contain("schema.table(:posts)")
      generated.should contain("t.column :title, :string")
      generated.should contain("t.column :body, :text, null: false")
      generated.should contain("class Altair::Record::Schema")
      generated.should contain("META = {")
      generated.should contain("title: {type: :string, null: true, primary: false}")
    end
  end

  it "rolls back the last migration and regenerates schema.cr" do
    with_runner do |runner, conn|
      File.write(runner.migrations_dir.join("20260802000001_create_posts.cr"), "")
      File.write(runner.migrations_dir.join("20260802000002_add_comments.cr"), "")
      runner.migrate
      runner.rollback.should be_true
      runner.applied_versions.should eq(["20260802000001_create_posts"])
      schema_before = File.read(runner.schema_path)
      schema_before.should contain("schema.table(:posts)")
      schema_before.should_not contain("comments")
      exists = conn.query_one("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'comments'") { |rs| rs.read(Int64) }
      exists.should eq(0)
    end
  end

  it "rejects rolling back an irreversible migration with a clear error" do
    with_runner do |runner, _|
      File.write(runner.migrations_dir.join("20260802000001_create_posts.cr"), "")
      File.write(runner.migrations_dir.join("20260802000002_irreversible.cr"), "")
      runner.migrate
      expect_raises(Altair::Error, /irreversible/) do
        runner.rollback
      end
    end
  end

  it "rolls back a migration whose up raises" do
    with_runner do |runner, conn|
      File.write(runner.migrations_dir.join("20260802000001_create_posts.cr"), "")
      File.write(runner.migrations_dir.join("20260802000003_explodes.cr"), "")
      expect_raises(RuntimeError, /boom/) do
        runner.migrate
      end
      runner.applied_versions.should eq(["20260802000001_create_posts"])
      exists = conn.query_one(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'exploding'"
      ) { |rs| rs.read(Int64) }
      exists.should eq(0)
    end
  end

  it "returns false when nothing is applied" do
    with_runner do |runner, _|
      runner.rollback.should be_false
    end
  end
end

describe Altair::Record::Schema, "change_column_null" do
  it "toggles nullability on SQLite by rebuilding the table in place" do
    dir = Path.new(Dir.tempdir, "altair_null_#{Random.rand(1_000_000)}")
    FileUtils.mkdir_p(dir)
    conn = Altair::Record::Connection.new(
      Altair::Record::Adapters::SQLite3.instance,
      "sqlite3://#{dir.join("test.db")}",
      DB::Pool::Options.new(max_pool_size: 1),
      5.seconds
    )
    begin
      schema = Altair::Record::Schema.new(Altair::Record::Adapters::SQLite3.instance, conn)
      schema.create_table(:widgets) do |t|
        t.string :name, null: false
        t.text :note
      end
      schema.add_index(:widgets, :name, unique: true)
      conn.exec(%(INSERT INTO "widgets" ("name", "note") VALUES ('keep', 'first note')))
      conn.exec(%(INSERT INTO "widgets" ("name", "note") VALUES ('blank', 'second note')))

      # A later migration receives a fresh Schema with no in-memory state,
      # so the rebuild must read the shape from the database itself.
      fresh = Altair::Record::Schema.new(Altair::Record::Adapters::SQLite3.instance, conn)
      fresh.change_column_null(:widgets, :note, false)

      names = [] of String
      notes = [] of String
      conn.query(%(SELECT "name", "note" FROM "widgets" ORDER BY "name")) do |rs|
        rs.each do
          names << rs.read(String)
          notes << rs.read(String)
        end
      end
      names.should eq(["blank", "keep"])
      notes.should eq(["second note", "first note"])

      violated = false
      begin
        conn.exec(%(INSERT INTO "widgets" ("name", "note") VALUES ('nullish', NULL)))
      rescue e
        violated = e.message.to_s.includes?("NOT NULL")
      end
      violated.should be_true

      fresh.change_column_null(:widgets, :note, true)
      conn.exec(%(INSERT INTO "widgets" ("name", "note") VALUES ('nullish', NULL)))
      total = conn.query_one(%(SELECT COUNT(*) FROM "widgets")) { |rs| rs.read(Int64) }
      total.should eq(3)

      # The explicit index survived the rebuild, still unique.
      unique_flags = [] of Bool
      conn.query(%(PRAGMA index_list("widgets"))) do |rs|
        rs.each do
          rs.read(Int64)
          rs.read(String)
          unique = rs.read(Int64) == 1
          origin = rs.read(String)
          rs.read(Int64)
          unique_flags << unique if origin == "c"
        end
      end
      unique_flags.should eq([true])
    ensure
      conn.close
      FileUtils.rm_rf(dir)
    end
  end
end
