# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Env`, the framework's environment enum. Altair
# distinguishes exactly three environments — `Development`, `Production` and
# `Test` — the conventional development lifecycle. The active environment is
# resolved once, lazily, from the `ALTAIR_ENV` environment variable and
# defaults to `Development`.
module Altair
  enum Env
    Development
    Production
    Test

    # Resolves the environment from the `ALTAIR_ENV` environment variable.
    # Unknown values fall back to `Development` so that an unset or
    # misspelled variable never prevents the application from booting.
    def self.from_env : Env
      case ENV["ALTAIR_ENV"]?
      when "production"
        Production
      when "test"
        Test
      else
        Development
      end
    end
  end

  @@env = Env.from_env

  # Returns the currently active environment. The value is resolved from the
  # `ALTAIR_ENV` environment variable on first call and cached afterwards:
  #
  # ```
  # Altair.env              # => Altair::Env::Development
  # Altair.env.development? # => true
  # ```
  def self.env : Env
    @@env
  end

  # Overrides the active environment. Mostly useful in test setups, where
  # specs pin the environment to `Altair::Env::Test`.
  def self.env=(env : Env) : Env
    @@env = env
  end
end
