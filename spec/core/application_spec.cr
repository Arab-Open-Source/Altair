# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Application`: singleton semantics, class-level config
# access, root detection and the single-application guard.
require "../spec_helper"

class SecondApp < Altair::Application
end

describe Altair::Application do
  it "returns the same instance on every call" do
    SpecApp.instance.should be(SpecApp.instance)
  end

  it "exposes configuration from the subclass body" do
    SpecApp.config.name.should eq("SpecApp")
  end

  it "detects the root directory from the working directory" do
    SpecApp.instance.root.to_s.should eq(Dir.current)
  end

  it "allows overriding the root directory" do
    app = SpecApp.instance
    app.root = Path.new("/tmp/opencode")
    app.root.to_s.should eq("/tmp/opencode")
  end

  it "refuses a second application instance" do
    expect_raises(Altair::ConfigurationError) do
      SecondApp.instance
    end
  end
end
