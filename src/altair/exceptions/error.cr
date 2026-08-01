# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Error`, the root of the framework's exception
# hierarchy. Every exception raised by Altair — configuration mistakes, HTTP
# errors, missing routes and record-not-found conditions alike — inherits
# from this class, so applications can rescue framework errors with a single
# `rescue Altair::Error` clause.
module Altair
  class Error < Exception
  end
end
