# Altair — the batteries-included web framework for Crystal.
#
# Specs for the database test helpers: `Altair::Test.transactional` keeps
# every write inside a rolled-back transaction, and `Altair::Test.migrate!`
# applies pending migrations through the same engine the CLI drives.
require "./../spec_helper"
require "./../record/model_fixtures_spec"

private def remove_tree(dir : Path) : Nil
  return unless Dir.exists?(dir.to_s)
  Dir.children(dir.to_s).each do |child|
    path = dir / child
    File.directory?(path.to_s) ? remove_tree(path) : File.delete(path)
  end
  Dir.delete(dir.to_s)
end

# Compiled into the spec process so the migration registry knows it — the
# runner matches pending files to compiled classes by name, exactly as a
# project's launcher requires its migrations.
class CreateAltairTestWidgets < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:altair_test_widgets) do |t|
      t.string :name
    end
  end
end

describe "Altair::Test database helpers" do
  before_each do
    RecordSpec.setup_database
  end

  describe "transactional" do
    it "keeps writes invisible outside the block" do
      Altair::Test.transactional do
        Post.create(title: "ephemeral", views: 1, published: true)
        Post.count.should eq(1)
      end
      Post.count.should eq(0)
    end

    it "rolls back when the block raises" do
      expect_raises(ArgumentError, "boom") do
        Altair::Test.transactional do
          Post.create(title: "doomed", views: 1, published: true)
          raise ArgumentError.new("boom")
        end
      end
      Post.count.should eq(0)
    end

    it "supports nested transactional blocks through savepoints" do
      Altair::Test.transactional do
        Post.create(title: "outer", views: 1, published: true)
        Altair::Test.transactional do
          Post.create(title: "inner", views: 1, published: true)
        end
        Post.count.should eq(2)
      end
      Post.count.should eq(0)
    end
  end

  describe "migrate!" do
    it "applies a pending migration and regenerates the schema file" do
      work = Path.new("/tmp/opencode/altair-migrate-spec-#{Random::Secure.hex(4)}")
      migrations_dir = work / "db" / "migrations"
      schema_path = work / "db" / "schema.cr"
      Dir.mkdir_p(migrations_dir.to_s)

      version = Time.utc.to_s("%Y%m%d%H%M%S")
      File.write(migrations_dir / "#{version}_create_altair_test_widgets.cr",
        "# The compiled class lives in this spec file; the runner matches by name.\n")

      begin
        count = Altair::Test.migrate!(SpecApp, migrations_dir: migrations_dir, schema_path: schema_path)
        count.should be >= 1

        tables = Altair::Record.connection.query_one(
          "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'altair_test_widgets'"
        ) { |rs| rs.read(Int64) }
        tables.should eq(1)

        File.exists?(schema_path).should be_true
        File.read(schema_path).should contain("altair_test_widgets")
      ensure
        conn = Altair::Record.connection
        conn.exec("DROP TABLE IF EXISTS altair_test_widgets")
        conn.exec(
          "DELETE FROM schema_migrations WHERE version = #{conn.adapter.placeholder(0)}", version
        )
        remove_tree(work)
      end
    end

    it "reports zero when nothing is pending" do
      work = Path.new("/tmp/opencode/altair-migrate-spec-empty-#{Random::Secure.hex(4)}")
      migrations_dir = work / "db" / "migrations"
      schema_path = work / "db" / "schema.cr"
      Dir.mkdir_p(migrations_dir.to_s)

      begin
        Altair::Test.migrate!(SpecApp, migrations_dir: migrations_dir, schema_path: schema_path).should eq(0)
      ensure
        remove_tree(work)
      end
    end
  end
end
