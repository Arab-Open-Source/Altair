# Altair — the batteries-included web framework for Crystal.
#
# Specs for the glob segment `*path`: a catch-all parameter that captures
# the remainder of the path, joined with `/`. `/files/*path` matches
# `/files/a/b/c` with `path` = `"a/b/c"`. Because the glob owns the rest of
# the path, a format suffix is never stripped from it: `/files/a.txt`
# yields `path` = `"a.txt"`, not `path` = `"a"` plus `format` = `"txt"`.
# Covers router-level matching, generated helpers and real HTTP dispatch.
require "../spec_helper"

class GlobApp < Altair::Application
  routes do
    get "/files/*path", to: FilesController.index, named: :files
    get "/files", to: FilesController.about
  end
end

private def glob_router : Altair::Routing::Router
  Altair::Routing::Router.new(GlobApp.route_set.routes)
end

describe "glob routes" do
  it "captures the remainder of the path joined with slashes" do
    match = glob_router.find("GET", "/files/a/b/c")
    match.should_not be_nil
    match.not_nil!.params["path"].should eq("a/b/c")
  end

  it "captures a single segment" do
    match = glob_router.find("GET", "/files/readme")
    match.should_not be_nil
    match.not_nil!.params["path"].should eq("readme")
  end

  it "URI-decodes every captured segment" do
    match = glob_router.find("GET", "/files/a%20b/c")
    match.should_not be_nil
    match.not_nil!.params["path"].should eq("a b/c")
  end

  it "requires at least one segment after the prefix" do
    glob_only = Altair::Routing::Router.new(GlobApp.route_set.routes.select(&.glob?).to_a)
    glob_only.find("GET", "/files").should be_nil
  end

  it "does not strip a format suffix from a glob capture" do
    match = glob_router.find("GET", "/files/a.txt")
    match.should_not be_nil
    match.not_nil!.params["path"].should eq("a.txt")
    match.not_nil!.params["format"]?.should be_nil
  end

  it "still matches a static route on the prefix" do
    match = glob_router.find("GET", "/files")
    match.should_not be_nil
    match.not_nil!.route.action.should eq("FilesController#about")
  end

  it "generates a path helper taking the captured string" do
    GlobApp.files_path("a/b").should eq("/files/a/b")
    GlobApp.files_path("readme").should eq("/files/readme")
  end
end

class GlobEchoApp < Altair::Application
  routes do
    get "/docs/*path" do |request, response|
      response.text("path=#{request.params["path"]}")
    end
  end
end

private def with_glob_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = GlobEchoApp.instance
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
      HTTP::Client.get("http://127.0.0.1:#{port}/docs/a")
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

describe "glob integration" do
  it "dispatches the captured remainder to the handler" do
    with_glob_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/docs/guide/usage")
      response.status_code.should eq(200)
      response.body.should eq("path=guide/usage")
    end
  end

  it "keeps a dotted file name inside the capture" do
    with_glob_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/docs/manual.pdf")
      response.status_code.should eq(200)
      response.body.should eq("path=manual.pdf")
    end
  end

  it "answers 404 when the glob prefix alone is requested" do
    with_glob_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/docs")
      response.status_code.should eq(404)
    end
  end
end
