# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware::SecurityHeaders`, the middleware
# that stamps the framework's default security headers onto every response.
# It runs before the router, so the headers land on routed responses,
# static files and framework-generated errors alike.
#
# The header set is `Config#security_headers` — a `String => String` mapping
# applied verbatim. Entries are only written when the response does not
# already carry the header, so an application that sets its own value (or a
# more specific one) wins. Set `config.security_headers` to `{} of
# String => String` to turn the middleware into a pass-through.
class Altair::Middleware::SecurityHeaders < Altair::Middleware
  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    app.config.security_headers.each do |name, value|
      response.headers[name] = value unless response.headers[name]?
    end
    chain.call
  end
end
