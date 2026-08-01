# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Env`: environment parsing, module-level accessors and
# the development default.
require "../spec_helper"

describe Altair::Env do
  it "parses the ALTAIR_ENV environment variable" do
    ENV["ALTAIR_ENV"] = "production"
    Altair::Env.from_env.should eq(Altair::Env::Production)

    ENV["ALTAIR_ENV"] = "test"
    Altair::Env.from_env.should eq(Altair::Env::Test)

    ENV.delete("ALTAIR_ENV")
    Altair::Env.from_env.should eq(Altair::Env::Development)
  end

  it "falls back to development for unknown values" do
    ENV["ALTAIR_ENV"] = "staging"
    Altair::Env.from_env.should eq(Altair::Env::Development)
    ENV.delete("ALTAIR_ENV")
  end

  it "is readable and overridable at module level" do
    previous = Altair.env
    Altair.env = Altair::Env::Production
    Altair.env.should eq(Altair::Env::Production)
    Altair.env = previous
  end

  it "answers predicate questions" do
    Altair.env = Altair::Env::Development
    Altair.env.development?.should be_true
    Altair.env.production?.should be_false
    Altair.env = Altair::Env::Test
    Altair.env.test?.should be_true
  end
end
