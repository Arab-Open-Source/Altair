# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Middleware::Cors`: with no origins configured the
# middleware passes every request through untouched; with origins configured
# it answers preflight requests itself and stamps `Access-Control-Allow-*`
# headers on permitted simple requests, leaving unpermitted origins alone.
require "../spec_helper"

private def cors_request(method : String = "GET", origin : String? = "https://app.example.com", request_method : String? = nil) : Altair::HTTP::Request
  raw = HTTP::Request.new(method, "/api/things")
  raw.headers["Origin"] = origin if origin
  raw.headers["Access-Control-Request-Method"] = request_method if request_method
  Altair::HTTP::Request.new(raw)
end

private def cors_response : Altair::HTTP::Response
  Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
end

private def cors_middleware : Altair::Middleware::Cors
  Altair::Middleware::Cors.new(SpecApp.instance)
end

private def with_cors(origins : Array(String), credentials : Bool = false, &)
  config = SpecApp.instance.config.cors
  original_origins = config.origins
  original_credentials = config.credentials?
  config.origins = origins
  config.credentials = credentials
  begin
    yield
  ensure
    config.origins = original_origins
    config.credentials = original_credentials
  end
end

describe Altair::Middleware::Cors do
  it "passes everything through when no origins are configured" do
    response = cors_response
    cors_middleware.call(cors_request("GET", "https://evil.example.com"), response, -> { })
    response.headers["Access-Control-Allow-Origin"]?.should be_nil
    response.headers["Access-Control-Allow-Methods"]?.should be_nil
  end

  it "stamps allow-origin on a permitted simple request and runs the chain" do
    with_cors(["https://app.example.com"]) do
      ran = false
      response = cors_response
      cors_middleware.call(cors_request("GET"), response, -> { ran = true })
      response.headers["Access-Control-Allow-Origin"].should eq("https://app.example.com")
      ran.should be_true
    end
  end

  it "leaves a request from an unpermitted origin untouched" do
    with_cors(["https://app.example.com"]) do
      response = cors_response
      cors_middleware.call(cors_request("GET", "https://evil.example.com"), response, -> { })
      response.headers["Access-Control-Allow-Origin"]?.should be_nil
    end
  end

  it "answers preflight requests directly without running the chain" do
    with_cors(["https://app.example.com"]) do
      ran = false
      response = cors_response
      cors_middleware.call(
        cors_request("OPTIONS", "https://app.example.com", "GET"),
        response,
        -> { ran = true }
      )
      response.headers["Access-Control-Allow-Origin"].should eq("https://app.example.com")
      response.headers["Access-Control-Allow-Methods"].should contain("GET")
      response.headers["Access-Control-Allow-Headers"].should contain("Content-Type")
      response.status.should eq(::HTTP::Status::NO_CONTENT)
      ran.should be_false
    end
  end

  it "does not answer preflight for an unpermitted origin" do
    with_cors(["https://app.example.com"]) do
      ran = false
      response = cors_response
      cors_middleware.call(
        cors_request("OPTIONS", "https://evil.example.com", "GET"),
        response,
        -> { ran = true }
      )
      response.headers["Access-Control-Allow-Origin"]?.should be_nil
      ran.should be_true
    end
  end

  it "grants any origin when configured with a wildcard" do
    with_cors(["*"]) do
      response = cors_response
      cors_middleware.call(cors_request("GET", "https://any.example.com"), response, -> { })
      response.headers["Access-Control-Allow-Origin"].should eq("*")
    end
  end

  it "echoes the exact origin for credentials with a wildcard" do
    with_cors(["*"], credentials: true) do
      response = cors_response
      cors_middleware.call(cors_request("GET", "https://app.example.com"), response, -> { })
      response.headers["Access-Control-Allow-Origin"].should eq("https://app.example.com")
      response.headers["Access-Control-Allow-Credentials"].should eq("true")
    end
  end

  it "includes credentials and max-age headers when configured" do
    with_cors(["https://app.example.com"], credentials: true) do
      original_max = SpecApp.instance.config.cors.max_age
      SpecApp.instance.config.cors.max_age = 3600_i64
      begin
        response = cors_response
        cors_middleware.call(
          cors_request("OPTIONS", "https://app.example.com", "PUT"),
          response,
          -> { }
        )
        response.headers["Access-Control-Allow-Origin"].should eq("https://app.example.com")
        response.headers["Access-Control-Allow-Credentials"].should eq("true")
        response.headers["Access-Control-Max-Age"].should eq("3600")
      ensure
        SpecApp.instance.config.cors.max_age = original_max
      end
    end
  end
end
