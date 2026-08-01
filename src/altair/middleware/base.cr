# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware`, the base class of the middleware
# pipeline. Middleware wraps the router: each one receives the framework's
# request and response wrappers plus a `chain` proc that continues to the
# next middleware, and finally the router itself. A middleware may answer
# the request directly (short-circuiting the chain, as static-file serving
# does) or run before/after the chain (as request logging does).
#
# ```
# class CacheBusting < Altair::Middleware
#   def call(request, response, chain)
#     response.headers["X-Frame-Options"] = "DENY"
#     chain.call
#   end
# end
# ```
#
# The stack is configured through `config.middleware`, a list of factory
# procs, or by appending middleware from the application class body:
#
# ```
# class Blog < Altair::Application
#   config.name = "Blog"
#   use Altair::Middleware::Logger
#   use Altair::Middleware::Static
# end
# ```
abstract class Altair::Middleware
  # The application this middleware serves, giving access to its
  # configuration and root directory.
  getter app : Altair::Application

  def initialize(@app : Altair::Application)
  end

  # Runs the middleware. Call `chain.call` to continue to the next
  # middleware; skip it to answer the request directly.
  abstract def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
end
