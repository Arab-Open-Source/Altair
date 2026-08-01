# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::ConfigurationError`, raised whenever an
# application is set up in an invalid way — for example, when a second
# application subclass is defined, or when required settings are missing.
# Applications typically never rescue this class: a configuration error is a
# developer error that should surface immediately at boot time.
module Altair
  class ConfigurationError < Altair::Error
  end
end
