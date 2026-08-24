# Altair — the database management commands.
#
# Specs for `Altair::CLI::Project.create_databases` / `.drop_databases`:
# per-environment URLs from `config/database.yml`, idempotent creates,
# SQLite files materialized in place, and the production drop guard.
require "../spec_helper"
require "file_utils"

private def in_tempdir(&)
  dir = Path.new(Dir.tempdir, "altair_db_#{Random.rand(1_000_000)}")
  FileUtils.mkdir_p(dir)
  previous = Dir.current
  begin
    Dir.cd(dir.to_s)
    yield dir
  ensure
    Dir.cd(previous)
    FileUtils.rm_rf(dir)
  end
end

private class DbApp < Altair::Application
end

describe Altair::CLI::Project do
  describe ".create_databases" do
    it "materializes every environment's SQLite database" do
      in_tempdir do
        Dir.mkdir_p("config")
        File.write("config/database.yml", <<-YAML)
          development:
            url: "sqlite3://./db/blog_development.db"
          test:
            url: "sqlite3://./db/blog_test.db"
          YAML
        created = Altair::CLI::Project.create_databases
        created.should eq(2)
        File.exists?("db/blog_development.db").should be_true
        File.exists?("db/blog_test.db").should be_true
      end
    end

    it "is idempotent over existing databases" do
      in_tempdir do
        Dir.mkdir_p("config")
        File.write("config/database.yml", "development:\n  url: \"sqlite3://./db/again.db\"\n")
        Altair::CLI::Project.create_databases
        Altair::CLI::Project.create_databases.should eq(1)
      end
    end

    it "reports zero and does nothing without a database.yml" do
      in_tempdir do
        Altair::CLI::Project.create_databases.should eq(0)
      end
    end

    it "resolves the maintenance URL for a postgres target" do
      url = Altair::CLI::Project.maintenance_url(URI.parse("postgres://user:pass@db.host:5433/app_production"))
      url.to_s.should eq("postgres://user:pass@db.host:5433/postgres")
    end
  end

  describe ".drop_databases" do
    it "removes the environment databases" do
      in_tempdir do
        Dir.mkdir_p("config")
        File.write("config/database.yml", "development:\n  url: \"sqlite3://./db/gone.db\"\n")
        Altair::CLI::Project.create_databases
        File.exists?("db/gone.db").should be_true
        Altair::CLI::Project.drop_databases.should eq(1)
        File.exists?("db/gone.db").should be_false
      end
    end

    it "refuses to drop in production without force" do
      in_tempdir do
        Dir.mkdir_p("config")
        File.write("config/database.yml", "production:\n  url: \"sqlite3://./db/prod.db\"\n")
        Altair::CLI::Project.create_databases
        previous = Altair.env
        Altair.env = Altair::Env::Production
        begin
          Altair::CLI::Project.drop_databases.should eq(-1)
          File.exists?("db/prod.db").should be_true
          Altair::CLI::Project.drop_databases(force: true).should eq(1)
          File.exists?("db/prod.db").should be_false
        ensure
          Altair.env = previous
        end
      end
    end
  end
end
