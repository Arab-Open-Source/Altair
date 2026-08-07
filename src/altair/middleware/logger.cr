# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware::Logger`, the request logger. It is
# the first middleware in the default stack: it times the request, lets the
# rest of the pipeline run, then writes a single line per request through
# the application's logger, e.g.
#
# ```
# GET /posts -> 200 (1.2ms)
# ```
#
# Because it wraps the whole pipeline, every response is logged — routed
# actions, 404s and 405s alike. Swap `config.logger` on the application to
# redirect these lines.
class Altair::Middleware::Logger < Altair::Middleware
  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    started = Time.instant
    chain.call
    elapsed = (Time.instant - started).total_milliseconds.round(1)
    suffix = if id = request.request_id
               " (#{id})"
             else
               ""
             end
    app.config.logger.info { "#{request.method} #{request.path} -> #{response.status.value} (#{elapsed}ms)#{suffix}" }
  end
end
