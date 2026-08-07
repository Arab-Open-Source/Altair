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
    get "/chained", to: "crashes#chained"
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

  def chained : Nil
    inner = begin
      raise "inner root cause"
    rescue e
      e
    end
    raise Exception.new("outer failure", inner)
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

    it "links clickable suggestions to the suggested path" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/post")
        response.status_code.should eq(404)
        response.body.should contain(%(<a href="/posts"><code>/posts</code></a>))
      end
    end

    it "shows the route line that would make the path work" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/post")
        response.status_code.should eq(404)
        response.body.should contain(%(get "/post", to: "error_pages#index"))
      end
    end

    it "respects a _method override in the fix suggestion" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.post(
          "http://127.0.0.1:#{port}/post",
          form: "_method=PUT",
          headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
        )
        response.status_code.should eq(404)
        response.body.should contain(%(put "/post", to: "error_pages#index"))
      end
    end

    it "keeps parameter patterns unlinked but suggested as code" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/postx/5")
        response.status_code.should eq(404)
        body = response.body
        body.should contain("<code>/posts/:id</code>")
        body.should_not contain("<a href")
      end
    end

    it "escapes the requested path" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/zzz/<script>")
        response.status_code.should eq(404)
        body = response.body
        body.should contain("&lt;script&gt;")
        body.should_not contain("/zzz/<script>")
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
        body.should contain("How to send the right method")
        body.should contain(%(value="delete"))
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

    it "reports the route that was handling the request" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/crashes")
        response.status_code.should eq(500)
        response.body.should contain("crashes#boom")
      end
    end

    it "shows the request parameters in the context" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/crashes?from=spec")
        response.status_code.should eq(500)
        body = response.body
        body.should contain("from")
        body.should contain("spec")
      end
    end

    it "never shows sensitive headers" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get(
          "http://127.0.0.1:#{port}/crashes",
          headers: HTTP::Headers{"Authorization" => "Bearer secret"}
        )
        response.status_code.should eq(500)
        response.body.should_not contain("Bearer secret")
      end
    end

    it "highlights the failing line in a source preview" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/crashes")
        response.status_code.should eq(500)
        body = response.body
        body.should contain("class=\"source\"")
        body.should contain(%(raise &quot;boom went off&quot;))
        body.should contain("error_pages_spec.cr:34")
      end
    end

    it "walks the exception chain down to the root cause" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/chained")
        response.status_code.should eq(500)
        body = response.body
        body.should contain("Exception chain")
        body.should contain("outer failure")
        body.should contain("inner root cause")
      end
    end

    it "shows the environment strip with route and middleware counts" do
      with_error_pages_server(true) do |port|
        response = HTTP::Client.get("http://127.0.0.1:#{port}/post")
        response.status_code.should eq(404)
        body = response.body
        body.should contain("5 routes")
        body.should contain("5 middleware")
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
