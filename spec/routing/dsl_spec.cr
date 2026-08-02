# Altair — the batteries-included web framework for Crystal.
#
# Specs for the routing DSL: `root`, the HTTP verb macros (`get`, `post`,
# `put`, `patch`, `delete`), `to:` actions, handler blocks and `named:`
# helpers. Everything the DSL generates is verified at compile time — the
# route registrations are inspected through `route_set` and the generated
# helpers are called directly.
require "../spec_helper"

class DslApp < Altair::Application
  routes do
    root to: "pages#index"
    get "/hello/:name", to: "pages#hello", named: :greeting
    get "/about", to: "pages#about"
    get "/status" do |_request, response|
      response.print("ok")
    end
    post "/posts", to: "posts#create"
    put "/posts/:id", to: "posts#update"
    patch "/posts/:id", to: "posts#update"
    delete "/posts/:id", to: "posts#destroy"
  end
end

describe "routing DSL" do
  describe "registration" do
    it "registers every route in definition order" do
      DslApp.route_set.routes.map { |route| "#{route.method} #{route.pattern}" }.should eq([
        "GET /",
        "GET /hello/:name",
        "GET /about",
        "GET /status",
        "POST /posts",
        "PUT /posts/:id",
        "PATCH /posts/:id",
        "DELETE /posts/:id",
      ])
    end

    it "records the controller action for `to:` routes" do
      DslApp.route_set.routes.map(&.action).should eq([
        "pages#index", "pages#hello", "pages#about", nil,
        "posts#create", "posts#update", "posts#update", "posts#destroy",
      ])
    end

    it "gives the root route its default name" do
      DslApp.route_set.routes[0].name.should eq("root")
    end

    it "records the explicit name for `named:` routes" do
      DslApp.route_set.routes[1].name.should eq("greeting")
    end

    it "leaves unnamed routes unnamed" do
      DslApp.route_set.routes[2].name.should be_nil
    end
  end

  describe "generated helpers" do
    it "generates root_path" do
      DslApp.root_path.should eq("/")
    end

    it "generates a helper per `named:` route, interpolating the params" do
      DslApp.greeting_path("altair").should eq("/hello/altair")
    end
  end
end
