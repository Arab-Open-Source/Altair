# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Middleware::RequestId`: the middleware honors a
# client-supplied request id, generates a fresh UUID when none arrives, and
# sets both the request accessor and the response echo. It is exercised in
# isolation, wrapping a no-op chain, like the other middleware specs.
require "../spec_helper"

private def reqid_request(headers : HTTP::Headers = HTTP::Headers.new, method : String = "GET", path : String = "/x") : Altair::HTTP::Request
  request = HTTP::Request.new(method, path)
  request.headers.merge!(headers)
  Altair::HTTP::Request.new(request)
end

private def reqid_response : Altair::HTTP::Response
  Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
end

private def reqid_request_id_middleware : Altair::Middleware::RequestId
  Altair::Middleware::RequestId.new(SpecApp.instance)
end

describe Altair::Middleware::RequestId do
  it "echoes a client-supplied request id back on the response" do
    request = reqid_request(HTTP::Headers{"X-Request-Id" => "abc-123"})
    response = reqid_response
    reqid_request_id_middleware.call(request, response, -> { })
    request.request_id.should eq("abc-123")
    response.headers["X-Request-Id"].should eq("abc-123")
  end

  it "generates a unique UUID when the client sends none" do
    request = reqid_request
    response = reqid_response
    reqid_request_id_middleware.call(request, response, -> { })
    request.request_id.should_not be_nil
    request.request_id.not_nil!.should match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    response.headers["X-Request-Id"].should eq(request.request_id)
  end

  it "uses a different id for each request" do
    first = reqid_request
    second = reqid_request
    reqid_request_id_middleware.call(first, reqid_response, -> { })
    reqid_request_id_middleware.call(second, reqid_response, -> { })
    first.request_id.should_not eq(second.request_id)
  end

  it "honors the configured request_id_header" do
    original = SpecApp.instance.config.request_id_header
    SpecApp.instance.config.request_id_header = "X-Trace-Id"
    begin
      request = reqid_request(HTTP::Headers{"X-Trace-Id" => "trace-9"})
      response = reqid_response
      reqid_request_id_middleware.call(request, response, -> { })
      response.headers["X-Trace-Id"].should eq("trace-9")
      response.headers["X-Request-Id"]?.should be_nil
    ensure
      SpecApp.instance.config.request_id_header = original
    end
  end
end
