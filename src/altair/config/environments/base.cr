# Altair — the batteries-included web framework for Crystal.
#
# This file defines the per-environment settings bag. Each of the three
# environments (`development`, `production`, `test`) owns an instance of
# `Altair::Config::Environment`, and every setting is a typed property — a
# deliberate choice that keeps configuration checked at compile time instead
# of relying on loosely-typed hashes at runtime.
module Altair
  class Config
    class Environment
      # Enables verbose debug behaviour: detailed error pages, request
      # logging and relaxed asset checks. Defaults to `true` for
      # development and test, `false` for production.
      property? debug : Bool

      # When `true`, the application eagerly loads all constants at boot
      # instead of lazily. Enabled by default in production to surface
      # load-order bugs early.
      property? eager_load : Bool

      def initialize(@debug = false, @eager_load = false)
      end
    end
  end
end
