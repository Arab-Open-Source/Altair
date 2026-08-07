# Altair — the `database.yml` loader.
#
# Specs for `Altair::Config::Database`: which section is picked for the
# active environment, the merged settings, and the no-op behaviours when
# the file or section is missing. A fresh project has no `config/` at the
# spec root, so nil-loader behaviour is the default for the suite.
require "../spec_helper"
require "file_utils"

private def with_database_dir(& : Path ->)
  dir = Path.new(Dir.tempdir, "altair_db_#{Random.rand(100_000)}")
  Dir.mkdir_p(Path.new(dir, "config").to_s)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir.to_s)
  end
end

private def write_database_yml(dir : Path, content : String) : Nil
  File.write(Path.new(dir, "config", "database.yml"), content)
end

describe Altair::Config::Database do
  around_each do |example|
    previous = ENV.to_h
    example.run
    previous.each { |k, v| ENV[k] = v }
  end

  it "applies the active environment's section" do
    with_database_dir do |dir|
      write_database_yml(dir, <<-YAML)
        development:
          url: "sqlite3://./db/dev.db"
        production:
          url: "postgresql://user:pass@localhost/blog_production"
          pool: 24
          checkout_timeout: 7.5
        YAML
      config = Altair::Config.new
      Altair::Config::Database.apply(config, dir, Altair::Env::Production).should be_true
      config.db_url.should eq "postgresql://user:pass@localhost/blog_production"
      config.db_max_pool_size.should eq 24
      config.db_checkout_timeout.should eq 7.5
    end
  end

  it "picks the development section when development is active" do
    with_database_dir do |dir|
      write_database_yml(dir, <<-YAML)
        development:
          url: "sqlite3://./db/blog.db"
        production:
          url: "postgresql://user:pass@localhost/blog_production"
        YAML
      config = Altair::Config.new
      Altair::Config::Database.apply(config, dir, Altair::Env::Development).should be_true
      config.db_url.should eq "sqlite3://./db/blog.db"
    end
  end

  it "applies initial and max idle pool and the query timeout" do
    with_database_dir do |dir|
      write_database_yml(dir, <<-YAML)
        test:
          url: "sqlite3://./db/blog_test.db"
          initial_pool: 4
          max_idle_pool: 4
          query_timeout: 3.0
        YAML
      config = Altair::Config.new
      Altair::Config::Database.apply(config, dir, Altair::Env::Test).should be_true
      config.db_initial_pool_size.should eq 4
      config.db_max_idle_pool_size.should eq 4
      config.db_query_timeout.should eq Time::Span.new(nanoseconds: 3_000_000_000)
    end
  end

  it "leaves the configuration untouched when the file is missing" do
    with_database_dir do |dir|
      config = Altair::Config.new
      Altair::Config::Database.apply(config, dir, Altair::Env::Production).should be_false
      config.db_url.should be_nil
      config.db_max_pool_size.should eq 10
    end
  end

  it "leaves the configuration untouched when the environment is absent" do
    with_database_dir do |dir|
      write_database_yml(dir, <<-YAML)
        development:
          url: "sqlite3://./db/dev.db"
        YAML
      config = Altair::Config.new
      Altair::Config::Database.apply(config, dir, Altair::Env::Production).should be_false
      config.db_url.should be_nil
    end
  end

  it "merges inherited settings from a shared default" do
    with_database_dir do |dir|
      write_database_yml(dir, <<-YAML)
        defaults: &defaults
          pool: 8
        production:
          <<: *defaults
          url: "sqlite3://./db/blog.db"
        YAML
      config = Altair::Config.new
      Altair::Config::Database.apply(config, dir, Altair::Env::Production).should be_true
      config.db_max_pool_size.should eq 8
    end
  end
end
