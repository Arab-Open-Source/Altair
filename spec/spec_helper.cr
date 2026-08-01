# Altair — the batteries-included web framework for Crystal.
#
# Shared setup for the framework's test suite. The suite pins the active
# environment to `Test` and defines `SpecApp`, the single application used
# across all specs — mirroring how a real Altair project defines its one and
# only application subclass.
require "spec"
require "http/client"
require "../src/altair"

Altair.env = Altair::Env::Test

class SpecApp < Altair::Application
  config.name = "SpecApp"
end
