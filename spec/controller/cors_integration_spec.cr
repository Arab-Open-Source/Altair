# Altair — CORS through the real HTTP pipeline.
#
# End-to-end spec for Phase 6 "CORS": an application with CORS origins
# configured boots over HTTP, and real preflight and simple cross-origin
# requests from an `HTTP::Client` get the expected `Access-Control-Allow-*`
# headers. Preflight never reaches the controller; simple requests do and
# still render.
require "../spec_helper"

class CorsApp < Altair::Application
  routes do
    get "/api/things", to: "cors_things#index"
  end
end

class CorsThingsController < Altair::Controller
  def index : Nil
    render text: "things"
  end
end

private def with_cors_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = CorsApp.instance
  app.config.cors.origins = ["https://app.example.com"]
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  done = Channel(Nil).new
  spawn do
    server.start
    done.send(nil)
  end

  wait_until_ready(port)

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

private def wait_until_ready(port : Int32) : Nil
  100.times do
    HTTP::Client.get("http://127.0.0.1:#{port}/api/things")
    return
  rescue IO::Error
    sleep 10.milliseconds
  end
  raise "server did not become ready"
end

describe "cors middleware over http" do
  it "answers preflight requests directly with the allowed origin and methods" do
    with_cors_server do |port|
      response = HTTP::Client.exec(
        "OPTIONS",
        "http://127.0.0.1:#{port}/api/things",
        headers: HTTP::Headers{
          "Origin"                        => "https://app.example.com",
          "Access-Control-Request-Method" => "GET",
        }
      )
      response.headers["Access-Control-Allow-Origin"].should eq("https://app.example.com")
      response.headers["Access-Control-Allow-Methods"].should contain("GET")
      response.status_code.should eq(204)
    end
  end

  it "stamps the allow-origin header on a permitted simple request" do
    with_cors_server do |port|
      response = HTTP::Client.get(
        "http://127.0.0.1:#{port}/api/things",
        headers: HTTP::Headers{"Origin" => "https://app.example.com"}
      )
      response.status_code.should eq(200)
      response.headers["Access-Control-Allow-Origin"].should eq("https://app.example.com")
      response.body.should eq("things")
    end
  end

  it "leaves requests from unpermitted origins untouched" do
    with_cors_server do |port|
      response = HTTP::Client.get(
        "http://127.0.0.1:#{port}/api/things",
        headers: HTTP::Headers{"Origin" => "https://evil.example.com"}
      )
      response.status_code.should eq(200)
      response.body.should eq("things")
      response.headers["Access-Control-Allow-Origin"]?.should be_nil
    end
  end

  it "stamps security headers and request id even on CORS responses" do
    with_cors_server do |port|
      response = HTTP::Client.get(
        "http://127.0.0.1:#{port}/api/things",
        headers: HTTP::Headers{"Origin" => "https://app.example.com", "X-Request-Id" => "cors-1"}
      )
      response.headers["X-Frame-Options"].should eq("SAMEORIGIN")
      response.headers["X-Request-Id"].should eq("cors-1")
    end
  end
end
