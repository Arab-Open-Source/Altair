# Altair — the batteries-included web framework for Crystal.
#
# End-to-end specs: a real application with routes is booted over real HTTP
# and exercised through the wire — matched params, block handlers, 404 for
# unknown paths, 405 with `Allow` for wrong methods, HEAD-requests-GET and
# the `_method` form override. The singleton guard from Phase 0 requires
# resetting the application instance before and after this suite.
require "../spec_helper"

class RoutingApp < Altair::Application
  routes do
    root to: "pages#index"
    get "/hello/:name" do |request, response|
      response.print("hello #{request.params["name"]}")
    end
    resources :posts
  end
end

private def with_routing_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = RoutingApp.instance
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
    HTTP::Client.get("http://127.0.0.1:#{port}/")
    return
  rescue IO::Error
    sleep 10.milliseconds
  end
  raise "server did not become ready"
end

describe "routing integration" do
  it "dispatches a block handler with matched params" do
    with_routing_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/hello/altair")
      response.status_code.should eq(200)
      response.body.should eq("hello altair")
    end
  end

  it "dispatches to controllers" do
    with_routing_server do |port|
      HTTP::Client.get("http://127.0.0.1:#{port}/posts").status_code.should eq(200)
      HTTP::Client.get("http://127.0.0.1:#{port}/posts/5").status_code.should eq(200)
      HTTP::Client.get("http://127.0.0.1:#{port}/posts/new").status_code.should eq(200)
    end
  end

  it "answers 404 for unknown paths" do
    with_routing_server do |port|
      HTTP::Client.get("http://127.0.0.1:#{port}/nope").status_code.should eq(404)
    end
  end

  it "answers 405 with the Allow header for known paths with the wrong method" do
    with_routing_server do |port|
      response = HTTP::Client.post("http://127.0.0.1:#{port}/posts/5")
      response.status_code.should eq(405)
      response.headers["Allow"]?.should eq("GET, PUT, PATCH, DELETE")
    end
  end

  it "matches HEAD requests against GET routes" do
    with_routing_server do |port|
      HTTP::Client.head("http://127.0.0.1:#{port}/posts").status_code.should eq(200)
    end
  end

  it "honours the `_method` form override" do
    with_routing_server do |port|
      response = HTTP::Client.post(
        "http://127.0.0.1:#{port}/posts/5",
        form: "title=updated&_method=PUT",
        headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
      )
      response.status_code.should eq(200)
    end
  end
end
