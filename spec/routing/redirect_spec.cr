# Altair — the batteries-included web framework for Crystal.
#
# Specs for `redirect`: a permanent path redirect declared in the routes
# block. `redirect "/old/draft", to: "/posts"` registers a route that
# answers every request method with 301 (Moved Permanently) and a
# `Location` header pointing at the destination. Redirects match any method
# but never appear in a 405 `Allow` header. Covers router-level matching and
# real HTTP dispatch.
require "../spec_helper"

class RedirectApp < Altair::Application
  routes do
    redirect "/old/draft", to: "/posts"
    redirect "/legacy/about", to: "/about"
    namespace :admin do
      redirect "/old", to: "/admin/posts"
    end
    get "/posts", to: PagesController.index
    get "/about", to: PagesController.about
    get "/admin/posts", to: Admin::PostsController.index
  end
end

private def redirect_router : Altair::Routing::Router
  Altair::Routing::Router.new(RedirectApp.route_set.routes)
end

describe "redirect routes" do
  it "registers a redirect route under the ANY method" do
    route = RedirectApp.route_set.routes.find!(&.pattern.==("/old/draft"))
    route.method.should eq("ANY")
    route.action.should be_nil
    route.name.should be_nil
  end

  it "matches every request method" do
    redirect_router.find("GET", "/old/draft").should_not be_nil
    redirect_router.find("POST", "/old/draft").should_not be_nil
    redirect_router.find("PUT", "/old/draft").should_not be_nil
    redirect_router.find("DELETE", "/old/draft").should_not be_nil
    redirect_router.find("HEAD", "/old/draft").should_not be_nil
  end

  it "does not match paths outside the redirect pattern" do
    redirect_router.find("GET", "/old/draft/extra").should be_nil
    redirect_router.find("GET", "/old").should be_nil
  end

  it "never appears in the allowed methods of a path" do
    redirect_router.allowed_for("/old/draft").should be_nil
  end

  it "matches a redirect with a format suffix" do
    match = redirect_router.find("GET", "/legacy/about.html")
    match.should_not be_nil
    match.not_nil!.params["format"].should eq("html")
  end
end

private def with_redirect_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = RedirectApp.instance
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
      HTTP::Client.get("http://127.0.0.1:#{port}/about")
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

describe "redirect integration" do
  it "answers 301 with the Location header for any method" do
    with_redirect_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/old/draft")
      response.status_code.should eq(301)
      response.headers["Location"].should eq("/posts")

      response = HTTP::Client.delete("http://127.0.0.1:#{port}/old/draft")
      response.status_code.should eq(301)
      response.headers["Location"].should eq("/posts")
    end
  end

  it "redirects inside a namespace" do
    with_redirect_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/admin/old")
      response.status_code.should eq(301)
      response.headers["Location"].should eq("/admin/posts")
    end
  end

  it "leaves ordinary routes untouched" do
    with_redirect_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/about")
      response.status_code.should eq(200)
    end
  end
end
