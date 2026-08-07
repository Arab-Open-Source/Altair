# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Config`: sensible defaults, per-environment settings
# and application overrides.
require "../spec_helper"

describe Altair::Config do
  it "has sensible defaults" do
    config = Altair::Config.new
    config.port.should eq(3000)
    config.host.should eq("0.0.0.0")
    config.name.should eq("Altair Application")
  end

  it "defaults to parallel execution and a warm database pool" do
    config = Altair::Config.new
    config.parallel_execution?.should be_true
    config.db_max_pool_size.should eq(10)
    config.db_initial_pool_size.should eq(2)
    config.db_max_idle_pool_size.should eq(2)
  end

  it "ships sensible per-environment defaults" do
    config = Altair::Config.new
    config.environments.development.debug?.should be_true
    config.environments.test.debug?.should be_true
    config.environments.production.eager_load?.should be_true
    config.environments.production.debug?.should be_false
  end

  it "resolves the settings bag for a given environment" do
    config = Altair::Config.new
    config.environment(Altair::Env::Development).debug?.should be_true
    config.environment(Altair::Env::Production).eager_load?.should be_true
    config.environment(Altair::Env::Test).debug?.should be_true
  end

  it "lets applications override settings" do
    config = Altair::Config.new
    config.name = "Blog"
    config.port = 4000
    config.name.should eq("Blog")
    config.port.should eq(4000)
  end

  it "lets applications tune per-environment settings" do
    config = Altair::Config.new
    config.environments.production.eager_load = false
    config.environments.production.eager_load?.should be_false
  end

  it "inherits the environment's debug flag into the global config" do
    previous = Altair.env
    Altair.env = Altair::Env::Production
    config = Altair::Config.new
    config.debug?.should be_false
    Altair.env = previous
  end

  it "ships safe-by-default security settings" do
    config = Altair::Config.new
    config.request_id_header.should eq("X-Request-Id")
    config.security_headers["X-Content-Type-Options"].should eq("nosniff")
    config.security_headers["X-Frame-Options"].should eq("SAMEORIGIN")
    config.cors.origins.should be_empty
    config.cors.credentials?.should be_false
    config.middleware.size.should eq(5)
  end
end
