# Altair — the batteries-included web framework for Crystal.
#
# End-to-end view specs: a real application boots over real HTTP and the
# template pipeline runs — compile-time `.ecr` transpilation, typed locals,
# layouts with `yield`, partials and the htmx layer (request detection,
# fragment rendering, `HX-Trigger`). These specs prove the Phase 3 exit
# criteria: escaping by default, layouts, partials and helpers working in
# the browser.
require "../spec_helper"

class ViewApp < Altair::Application
  routes do
    root to: "view_pages#index"
    get "/posts", to: "view_posts#index"
    get "/posts/raw", to: "view_posts#show"
    get "/posts/list", to: "view_posts#list"
    get "/posts/forms", to: "view_posts#forms"
    post "/posts", to: "view_posts#create"
  end
end

class ViewPagesController < Altair::Controller
  templates "pages",
    root: "spec/controller/fixtures/views",
    layout: "application",
    index: {name: String}

  def index : Nil
    render :index, locals: {name: "World"}
  end
end

class ViewPostsController < Altair::Controller
  templates "posts",
    root: "spec/controller/fixtures/views",
    layout: "application",
    index: {title: String, posts: Array(Int32)},
    show: {title: String, raw: String},
    form: {title: String},
    list: NamedTuple.new,
    forms: NamedTuple.new

  def route(id : Int32) : String
    "/posts/#{id}"
  end

  def index : Nil
    render :index, layout: !request.hx_request?, locals: {title: "Posts", posts: [1, 2, 3]}
  end

  def show : Nil
    render :show, locals: {title: "<script>alert(1)</script>", raw: "<b>bold</b>"}
  end

  def list : Nil
    render :list, layout: false
  end

  def forms : Nil
    render :forms
  end

  def create : Nil
    hx_trigger(:post_created)
    render :index, layout: !request.hx_request?, locals: {title: "Posts", posts: [7]}
  end
end

private def with_view_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = ViewApp.instance
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  spawn do
    server.start
  end

  100.times do
    HTTP::Client.get("http://127.0.0.1:#{port}/posts")
    break
  rescue IO::Error
    sleep 10.milliseconds
  end

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

private def hx_headers : HTTP::Headers
  HTTP::Headers{"HX-Request" => "true"}
end

describe "view rendering" do
  it "renders a full page inside the layout, with escaping by default" do
    with_view_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/")
      response.status_code.should eq(200)
      response.body.should contain("<div id=\"page\">")
      response.body.should contain("<h1>World</h1>")
      response.body.should end_with("</body>\n</html>\n")
    end
  end

  it "renders an action with typed locals and code blocks" do
    with_view_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/posts")
      response.status_code.should eq(200)
      response.body.should contain("<h1>Posts</h1>")
      response.body.should contain("<li id=\"post-1\">1</li>")
      response.body.should contain("<li id=\"post-3\">3</li>")
    end
  end

  it "answers an htmx request with a bare fragment" do
    with_view_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/posts", headers: hx_headers)
      response.status_code.should eq(200)
      response.body.should start_with("<h1>Posts</h1>")
      response.body.should_not contain("<html>")
    end
  end

  it "escapes interpolated values and keeps raw and literal output" do
    with_view_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/posts/raw")
      response.body.should contain("&lt;script&gt;alert(1)&lt;/script&gt;")
      response.body.should contain("<p><b>bold</b></p>")
      response.body.should contain("<p><% not a tag </p>")
    end
  end

  it "renders a partial inside a template" do
    with_view_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/posts/list")
      response.body.should eq("<section>\n  <label>inner</label>\n</section>\n")
    end
  end

  it "renders form_for blocks with helpers as actions, including nested parens" do
    with_view_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/posts/forms")
      response.status_code.should eq(200)
      response.body.should contain("<form action=\"/submit\"")
      response.body.should contain "<form action=\"/posts/1\" method=\"post\" class=\"inline\">"
      response.body.should contain(">Delete</button>")
      response.body.should contain(">Save</button>")
    end
  end

  it "renders a fragment on an htmx create and triggers an event" do
    with_view_server do |port|
      response = HTTP::Client.post(
        "http://127.0.0.1:#{port}/posts",
        form: "title=New",
        headers: hx_headers
      )
      response.status_code.should eq(200)
      response.headers["HX-Trigger"].should eq("post_created")
      response.body.should start_with("<h1>Posts</h1>")
      response.body.should_not contain("<html>")
    end
  end

  it "renders a full page on a non-htmx create" do
    with_view_server do |port|
      response = HTTP::Client.post(
        "http://127.0.0.1:#{port}/posts",
        form: "title=New",
        headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
      )
      response.status_code.should eq(200)
      response.body.should contain("<html>")
    end
  end
end
