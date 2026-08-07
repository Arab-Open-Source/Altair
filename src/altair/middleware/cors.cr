# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware::Cors`, the cross-origin resource
# sharing middleware. It is opt-in through `Config#cors`: with an empty
# origins list (the default) it is a pass-through, and it only engages once
# an application names the origins it trusts.
#
# For a permitted simple cross-origin request the middleware stamps an
# `Access-Control-Allow-Origin` header (plus credentials when configured)
# and lets the request through; a preflight `OPTIONS` request is answered
# directly with the allowed methods, headers and age, never reaching the
# router. Unpermitted origins and requests without an `Origin` header pass
# through untouched, and `chain.call` always runs unless preflight answered.
class Altair::Middleware::Cors < Altair::Middleware
  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    cors = app.config.cors
    return chain.call if cors.origins.empty?

    origin = request.headers["Origin"]?
    return chain.call if origin.nil?

    return chain.call unless cors.origin_allowed?(origin)

    if request.method == "OPTIONS" && request.headers["Access-Control-Request-Method"]?
      answer_preflight(request, origin, response)
    else
      response.headers["Access-Control-Allow-Origin"] = cors.allow_origin_header(origin)
      response.headers["Access-Control-Allow-Credentials"] = "true" if cors.credentials?
      chain.call
    end
  end

  # Answers a preflight request with the allowed origin, methods, headers
  # and age, short-circuiting the chain with a 204.
  private def answer_preflight(request : Altair::HTTP::Request, origin : String, response : Altair::HTTP::Response) : Nil
    cors = app.config.cors
    response.headers["Access-Control-Allow-Origin"] = cors.allow_origin_header(origin)
    response.headers["Access-Control-Allow-Methods"] = cors.methods
    response.headers["Access-Control-Allow-Headers"] = cors.allow_headers(request.headers["Access-Control-Request-Headers"]?)
    response.headers["Access-Control-Allow-Credentials"] = "true" if cors.credentials?
    if max_age = cors.max_age
      response.headers["Access-Control-Max-Age"] = max_age.to_s
    end
    response.head(::HTTP::Status::NO_CONTENT)
  end
end
