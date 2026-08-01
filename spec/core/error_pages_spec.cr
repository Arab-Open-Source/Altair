# Altair — the batteries-included web framework for Crystal.
#
# End-to-end specs for the error responses: with debug enabled, unknown
# paths answer with a page suggesting nearby routes and the full route
# table, wrong methods list the accepted ones, and crashes render the
# exception with its backtrace. Outside debug mode the framework answers
# with plain text and the standard `Allow` header only — the route table
# never leaks in production.
require "../spec_helper"

class ErrorPagesApp < Altair::Application
  routes do
    get "/posts", to: "error_pages#index"
    get "/posts/:id", to: "error_pages#show"
    post "/posts", to: "error_pages#create"
    get "/crashes", to: "crashes#boom"
  end
end

class ErrorPagesController < Altair::Controller
  def index : Nil
  end

  def show : Nil
  end

  def create : Nil
  end
end

class CrashesController < Altair::Controller
  def boom : Nil
    raise "boom went off"
  end
end

private def with_error_pages_server(debug : Bool, &)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = ErrorPagesApp.instance
  app.config.debug = debug
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
    HTTP::Client.get("http://127.0.0.1:#{port}/posts")
    return
  rescue IO::Error
    sleep 10.milliseconds
  end
  raise "server did not become ready"
end

describe "error pages" do
  describe "in debug mode" do
    it "answers a 404 with suggestions and the route table" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/post")
        response.status_code.should eq(404)
        response.headers["Content-Type"].should start_with("text/html")
        body = response.body
        body.should contain("No route matches")
        body.should contain("Did you mean?")
        body.should contain("<code>/posts</code>")
        body.should contain("Route table")
        body.should contain("/posts/:id")
        body.should contain("error_pages#show")
      end
    end

    it "omits suggestions when nothing is close to the path" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/zzzz")
        response.status_code.should eq(404)
        response.body.should_not contain("Did you mean?")
        response.body.should contain("Route table")
      end
    end

    it "escapes the requested path" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/zzz/<script>")
        response.status_code.should eq(404)
        response.body.should contain("&lt;script&gt;")
        response.body.should_not contain("<script>")
      end
    end

    it "answers a 405 with the accepted methods" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.delete("http://127.0.0.1:#{port}/posts")
        response.status_code.should eq(405)
        response.headers["Allow"].should eq("GET, POST")
        body = response.body
        body.should contain("is not accepted for")
        body.should contain("This path accepts")
        body.should contain("_method")
      end
    end

    it "answers a 500 with the exception and backtrace" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/crashes")
        response.status_code.should eq(500)
        body = response.body
        body.should contain("boom went off")
        body.should contain("Backtrace")
        body.should contain("error_pages_spec.cr")
      end
    end
  end

  describe "outside debug mode" do
    it "answers a 404 with plain text" do
      with_error_pages_server(false) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/post")
        response.status_code.should eq(404)
        response.body.should eq("404 Not Found")
      end
    end

    it "answers a 405 with plain text and the Allow header" do
      with_error_pages_server(false) do |port|
        response = HTTP::Client.delete("http://127.0.0.1:#{port}/posts")
        response.status_code.should eq(405)
        response.headers["Allow"].should eq("GET, POST")
        response.body.should eq("405 Method Not Allowed")
      end
    end

    it "answers a 500 with plain text" do
      with_error_pages_server(false) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/crashes")
        response.status_code.should eq(500)
        response.body.should eq("500 Internal Server Error")
      end
    end
  end
end
