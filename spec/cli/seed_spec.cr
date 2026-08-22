# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `db:seed` machinery: blocks registered through
# `Altair::CLI::Project.seeds` stay dormant while their file is required
# (so booting a server never plants data) and run in registration order
# when `db:seed` executes them.
require "../spec_helper"

describe Altair::CLI::Project do
  it "runs registered seed blocks in order and reports success" do
    ran = [] of String
    Altair::CLI::Project.reset_seeds!
    Altair::CLI::Project.seeds { ran << "first" }
    Altair::CLI::Project.seeds { ran << "second" }

    Altair::CLI::Project.seed.should eq(0)
    ran.should eq(["first", "second"])
  end

  it "succeeds without any registered seeds" do
    Altair::CLI::Project.reset_seeds!
    Altair::CLI::Project.seed.should eq(0)
  end

  it "re-runs on every invocation so callers decide idempotency" do
    count = 0
    Altair::CLI::Project.reset_seeds!
    Altair::CLI::Project.seeds { count += 1 }

    Altair::CLI::Project.seed
    Altair::CLI::Project.seed
    count.should eq(2)
  end
end
