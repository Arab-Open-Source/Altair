# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Middleware::RequestId`, the request-identifier
# middleware. Every request is given a unique id: an inbound `X-Request-Id`
# (or `Config#request_id_header`) is honored when present, otherwise a fresh
# UUID is generated. The id is exposed as `Altair::HTTP::Request#request_id`
# and echoed back to the client on the response under the same header, which
# makes both sides of a request traceable in logs and error reports.
require "uuid"

class Altair::Middleware::RequestId < Altair::Middleware
  def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
    header = app.config.request_id_header
    id = request.headers[header]?
    if id.nil? || id.empty?
      id = UUID.random.to_s
    end
    request.request_id = id
    response.headers[header] = id
    chain.call
  end
end
