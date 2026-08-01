# Altair — the batteries-included web framework for Crystal.
#
# Core framework specs: version constant and environment handling.
require "./spec_helper"

describe Altair do
  it "exposes a version constant" do
    Altair::VERSION.should_not be_empty
  end

  it "is pinned to the test environment by the suite" do
    Altair.env.should eq(Altair::Env::Test)
  end
end
