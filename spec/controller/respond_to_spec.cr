# Altair — the batteries-included web framework for Crystal.
#
# End-to-end specs for `respond_to`: one action, several format handlers,
# the requested format (path suffix then `Accept` then `:html`) picks the
# block that runs, and a request for an undeclared format answers 406.
require "../spec_helper"

class RespondController < Altair::Controller
  def show : Nil
    respond_to do |format|
      format.html { render text: "html view" }
      format.json { render json: {name: "post", id: 1} }
    end
  end

  def headless : Nil
    respond_to do |format|
      format.html { render text: "plain" }
    end
  end
end

class RespondApp < Altair::Application
  routes do
    get "/post", to: "respond#show"
    get "/only-html", to: "respond#headless"
  end
end

private def with_respond_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = RespondApp.instance
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  spawn do
    server.start
  end

  wait_until_ready(port)

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

private def wait_until_ready(port : Int32) : Nil
  100.times do
    HTTP::Client.get("http://127.0.0.1:#{port}/ping")
    return
  rescue IO::Error
    sleep 10.milliseconds
  end
  raise "server did not become ready"
end

describe "respond_to" do
  it "runs the html handler by default" do
    with_respond_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/post")
      response.status_code.should eq(200)
      response.body.should eq("html view")
    end
  end

  it "runs the json handler for a format suffix" do
    with_respond_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/post.json")
      response.status_code.should eq(200)
      response.body.should contain(%("name":"post"))
      response.headers["Content-Type"].should contain("application/json")
    end
  end

  it "runs the json handler for an application/json Accept header" do
    with_respond_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/post", headers: HTTP::Headers{"Accept" => "application/json"})
      response.status_code.should eq(200)
      response.body.should contain(%("name":"post"))
    end
  end

  it "answers 406 for an undeclared format" do
    with_respond_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/post.txt")
      response.status_code.should eq(406)
    end
  end

  it "answers 406 when only html is registered and text is requested" do
    with_respond_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/only-html", headers: HTTP::Headers{"Accept" => "text/plain"})
      response.status_code.should eq(406)
    end
  end
end
