# Altair — the batteries-included web framework for Crystal.
#
# Specs for the implicit format suffix: a path ending in `.{ext}` matches a
# route with the extension stripped and the extension exposed as
# `params["format"]` (Rails semantics, e.g. `/posts/5.json` exercises
# `GET /posts/:id` with `id` = `5`, `format` = `json`). Covers router-level
# matching and real HTTP dispatch.
require "../spec_helper"

class FormatEchoController < Altair::Controller
  def show : Nil
    render text: "id=#{params["id"]} format=#{params["format"]?}"
  end

  def index : Nil
    render text: "index format=#{params["format"]?}"
  end
end

class FormatApp < Altair::Application
  routes do
    get "/posts/:id", to: FormatEchoController.show, named: :post
    get "/posts", to: FormatEchoController.index
    get "/sitemap.xml", to: FormatEchoController.index, named: :sitemap
  end
end

private def format_router : Altair::Routing::Router
  Altair::Routing::Router.new(FormatApp.route_set.routes)
end

describe "implicit format suffix" do
  it "matches a param route with the id and the format extracted" do
    match = format_router.find("GET", "/posts/5.json")
    match.should_not be_nil
    match.not_nil!.params["id"].should eq("5")
    match.not_nil!.params["format"].should eq("json")
  end

  it "does not set a format parameter without a suffix" do
    match = format_router.find("GET", "/posts/5")
    match.should_not be_nil
    match.not_nil!.params["format"]?.should be_nil
    match.not_nil!.params["id"].should eq("5")
  end

  it "matches a static collection route with a format suffix" do
    match = format_router.find("GET", "/posts.json")
    match.should_not be_nil
    match.not_nil!.params["format"].should eq("json")
  end

  it "leaves a literal dotted static route alone" do
    match = format_router.find("GET", "/sitemap.xml")
    match.should_not be_nil
    match.not_nil!.params.empty?.should be_true
  end

  it "uses the last dot as the format delimiter" do
    match = format_router.find("GET", "/posts/5.tar.gz")
    match.should_not be_nil
    match.not_nil!.params["id"].should eq("5.tar")
    match.not_nil!.params["format"].should eq("gz")
  end

  it "treats a trailing dot as no format" do
    match = format_router.find("GET", "/posts/5.")
    match.should_not be_nil
    match.not_nil!.params["id"].should eq("5.")
    match.not_nil!.params["format"]?.should be_nil
  end

  it "does not strip dots in the middle of a path" do
    format_router.find("GET", "/a.b/c").should be_nil
  end

  it "returns nil when neither the stripped nor the raw path match" do
    format_router.find("GET", "/nope.json").should be_nil
  end
end

private def with_format_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = FormatApp.instance
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  done = Channel(Nil).new
  spawn do
    server.start
    done.send(nil)
  end

  100.times do
    begin
      HTTP::Client.get("http://127.0.0.1:#{port}/posts")
      break
    rescue IO::Error
      sleep 10.milliseconds
    end
  end

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

describe "format integration" do
  it "serves format and id parameters to the controller" do
    with_format_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/posts/7.json")
      response.status_code.should eq(200)
      response.body.should eq("id=7 format=json")
    end
  end

  it "dispatches a format suffix to a static collection route" do
    with_format_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/posts.json")
      response.status_code.should eq(200)
      response.body.should eq("index format=json")
    end
  end

  it "answers HEAD on a format-suffixed path" do
    with_format_server do |port|
      response = HTTP::Client.head("http://127.0.0.1:#{port}/posts/7.json")
      response.status_code.should eq(200)
    end
  end

  it "answers 405 with the matching methods for a format-suffixed path" do
    with_format_server do |port|
      response = HTTP::Client.post("http://127.0.0.1:#{port}/posts/7.json")
      response.status_code.should eq(405)
      response.headers["Allow"].should eq("GET")
    end
  end
end
