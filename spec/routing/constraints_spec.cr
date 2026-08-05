# Altair — the batteries-included web framework for Crystal.
#
# Specs for route `constraints:`: a regular expression attached to a path
# parameter. A route only matches when every constrained parameter satisfies
# its regex, so `/posts/abc` no longer reaches a `:id` constrained to
# `/\d+/`. Covers verb-level and `resources`-level constraints, nested
# inheritance, format interaction and HTTP dispatch.
require "../spec_helper"

class ConstraintEchoController < Altair::Controller
  def show : Nil
    render text: "id=#{params["id"]}"
  end

  def index : Nil
    render text: "index"
  end

  def preview : Nil
    render text: "preview #{params["id"]}"
  end
end

class IssuesController < Altair::Controller
  def index : Nil
    render text: "index"
  end

  def show : Nil
    render text: "id=#{params["id"]}"
  end

  def preview : Nil
    render text: "preview #{params["id"]}"
  end
end

class ConstraintApp < Altair::Application
  routes do
    get "/posts/:id", to: ConstraintEchoController.show,
      constraints: {id: /\d+/}
    get "/users/:name/roles/:id", to: ConstraintEchoController.show,
      constraints: {name: /[a-z]+/, id: /\d+/}
    resources :issues, only: [:index, :show], constraints: {id: /\d{4}/} do
      member do
        get :preview
      end
    end
  end
end

private def constraint_router : Altair::Routing::Router
  Altair::Routing::Router.new(ConstraintApp.route_set.routes)
end

describe "route constraints" do
  it "matches a parameter satisfying its constraint" do
    match = constraint_router.find("GET", "/posts/5")
    match.should_not be_nil
    match.not_nil!.params["id"].should eq("5")
  end

  it "rejects a parameter violating its constraint" do
    constraint_router.find("GET", "/posts/abc").should be_nil
  end

  it "constrains every parameter of a multi-parameter pattern" do
    match = constraint_router.find("GET", "/users/neo/roles/2")
    match.should_not be_nil
    match.not_nil!.params["name"].should eq("neo")
    match.not_nil!.params["id"].should eq("2")

    constraint_router.find("GET", "/users/Neo/roles/2").should be_nil
    constraint_router.find("GET", "/users/neo/roles/x").should be_nil
  end

  it "constrains a resource's member routes but not its index" do
    constraint_router.find("GET", "/issues/2024").should_not be_nil
    constraint_router.find("GET", "/issues/abcd").should be_nil
    constraint_router.find("GET", "/issues").should_not be_nil
  end

  it "keeps member routes inside a constrained resource constrained" do
    constraint_router.find("GET", "/issues/2024/preview").should_not be_nil
    constraint_router.find("GET", "/issues/abcd/preview").should be_nil
  end

  it "applies constraints to the id before format extraction" do
    constraint_router.find("GET", "/issues/2024.json").should_not be_nil
    constraint_router.find("GET", "/issues/abcd.json").should be_nil
  end

  it "leaves generated path helpers unconstrained" do
    ConstraintApp.issue_path(2024).should eq("/issues/2024")
    ConstraintApp.issues_path.should eq("/issues")
  end
end

private def with_constraint_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = ConstraintApp.instance
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  done = Channel(Nil).new
  spawn do
    server.start
    done.send(nil)
  end

  100.times do
    HTTP::Client.get("http://127.0.0.1:#{port}/issues")
    break
  rescue IO::Error
    sleep 10.milliseconds
  end

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

describe "constraints integration" do
  it "serves a request whose parameters satisfy the constraints" do
    with_constraint_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/issues/2024")
      response.status_code.should eq(200)
      response.body.should eq("id=2024")
    end
  end

  it "answers 404 for a path whose parameters violate the constraints" do
    with_constraint_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/issues/abcd")
      response.status_code.should eq(404)
    end
  end
end
