# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Middleware::SecurityHeaders`: the middleware stamps the
# configured security headers onto every response, without overwriting a
# header the application already set, and degrades to a pass-through when the
# configuration is empty.
require "../spec_helper"

private def security_request : Altair::HTTP::Request
  Altair::HTTP::Request.new(HTTP::Request.new("GET", "/"))
end

private def security_response : Altair::HTTP::Response
  Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
end

private def security_middleware : Altair::Middleware::SecurityHeaders
  Altair::Middleware::SecurityHeaders.new(SpecApp.instance)
end

describe Altair::Middleware::SecurityHeaders do
  it "stamps the default security headers on the response" do
    response = security_response
    security_middleware.call(security_request, response, -> { })
    response.headers["X-Content-Type-Options"].should eq("nosniff")
    response.headers["X-Frame-Options"].should eq("SAMEORIGIN")
    response.headers["Referrer-Policy"].should eq("strict-origin-when-cross-origin")
  end

  it "runs the chain so routing still happens" do
    ran = false
    security_middleware.call(security_request, security_response, -> { ran = true })
    ran.should be_true
  end

  it "leaves a header already set by the application untouched" do
    response = security_response
    response.headers["X-Frame-Options"] = "DENY"
    security_middleware.call(security_request, response, -> { })
    response.headers["X-Frame-Options"].should eq("DENY")
  end

  it "follows the configured hash instead of hardcoded values" do
    original = SpecApp.instance.config.security_headers
    SpecApp.instance.config.security_headers = {"X-Custom-Guard" => "1"}
    begin
      response = security_response
      security_middleware.call(security_request, response, -> { })
      response.headers["X-Custom-Guard"].should eq("1")
      response.headers["X-Content-Type-Options"]?.should be_nil
    ensure
      SpecApp.instance.config.security_headers = original
    end
  end

  it "becomes a pass-through when the header hash is empty" do
    original = SpecApp.instance.config.security_headers
    SpecApp.instance.config.security_headers = {} of String => String
    begin
      response = security_response
      security_middleware.call(security_request, response, -> { })
      response.headers["X-Content-Type-Options"]?.should be_nil
      response.headers["X-Frame-Options"]?.should be_nil
    ensure
      SpecApp.instance.config.security_headers = original
    end
  end
end
