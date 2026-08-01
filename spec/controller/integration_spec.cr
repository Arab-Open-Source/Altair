# Altair — the batteries-included web framework for Crystal.
#
# End-to-end controller specs: a real application with routes boots over
# real HTTP and the full pipeline runs — middleware, router and instance
# controllers. These specs prove the Phase 2 exit criterion: a full
# controller works end to end, with `render`, `redirect_to`, `head` and
# merged params, all dispatched through the generated route handlers.
require "../spec_helper"

class BooksApp < Altair::Application
  routes do
    resources :books
    get "/health", to: "books#health"
    get "/ping", to: "books#ping"
  end
end

class BooksController < Altair::Controller
  include BooksApp::RouteHelpers

  @@titles = [] of String

  def self.titles : Array(String)
    @@titles
  end

  def self.reset
    @@titles.clear
  end

  def index : Nil
    render html: "<h1>Books</h1>"
  end

  def new : Nil
    render html: "<form>new book</form>"
  end

  def create : Nil
    @@titles << params["title"]
    redirect_to books_path
  end

  def show : Nil
    render json: %({"id": "#{params["id"]}", "page": "#{params["page"]?}"})
  end

  def edit : Nil
    render html: "<form>edit book</form>"
  end

  def update : Nil
    @@titles << params["title"]
    redirect_to books_path
  end

  def destroy : Nil
    redirect_to books_path
  end

  def health : Nil
    render text: "ok"
  end

  def ping : Nil
    head ::HTTP::Status::NO_CONTENT
  end
end

private def with_books_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  BooksController.reset
  app = BooksApp.instance
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
    HTTP::Client.get("http://127.0.0.1:#{port}/ping")
    return
  rescue IO::Error
    sleep 10.milliseconds
  end
  raise "server did not become ready"
end

describe "controller integration" do
  it "dispatches index through an instance controller" do
    with_books_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/books")
      response.status_code.should eq(200)
      response.headers["Content-Type"].should start_with("text/html")
      response.body.should eq("<h1>Books</h1>")
    end
  end

  it "dispatches show with route and query params merged" do
    with_books_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/books/5?page=2")
      response.status_code.should eq(200)
      response.headers["Content-Type"].should start_with("application/json")
      response.body.should eq(%({"id": "5", "page": "2"}))
    end
  end

  it "renders plain text responses" do
    with_books_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/health")
      response.status_code.should eq(200)
      response.headers["Content-Type"].should start_with("text/plain")
      response.body.should eq("ok")
    end
  end

  it "answers head requests with a bare status" do
    with_books_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/ping")
      response.status_code.should eq(204)
      response.body.should eq("")
    end
  end

  it "redirects through a generated path helper" do
    with_books_server do |port|
      response = HTTP::Client.post(
        "http://127.0.0.1:#{port}/books",
        form: "title=Altair+in+Action",
        headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
      )
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/books")
      BooksController.titles.size.should eq(1)
    end
  end

  it "returns 404 through the middleware pipeline for unknown paths" do
    with_books_server do |port|
      HTTP::Client.get("http://127.0.0.1:#{port}/nope").status_code.should eq(404)
    end
  end
end
