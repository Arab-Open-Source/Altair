# Altair — typed route references.
#
# Routes can point at controller actions with a plain method call
# (`to: PagesController.index`) instead of a string (`"pages#index"`).
# The call is resolved at compile time: a wrong controller class or a
# wrong action name fails the build, and renames are picked up by
# compiler-aware tools. The string form keeps working unchanged.
require "../spec_helper"

class TypedRefsApp < Altair::Application
  routes do
    root to: PagesController.index
    get "/typed", to: PagesController.hello, named: :typed_hello
    post "/typed", to: PostsController.create
    put "/typed/:id", to: PostsController.update
    patch "/typed/:id", to: PostsController.update
    delete "/typed/:id", to: PostsController.destroy
    get "/typed/block" do |_request, response|
      response.text("block")
    end
  end
end

describe "typed route references" do
  it "registers a root route from a typed reference" do
    route = TypedRefsApp.route_set.routes.find!(&.pattern.==("/"))
    route.action.should eq("PagesController#index")
  end

  it "registers a verb route from a typed reference" do
    route = TypedRefsApp.route_set.routes.find!(&.pattern.==("/typed"))
    route.method.should eq("GET")
    route.action.should eq("PagesController#hello")
  end

  it "generates the named helper for a typed reference" do
    route = TypedRefsApp.route_set.routes.find!(&.name.==("typed_hello"))
    route.handler.should_not be_nil
  end

  it "registers CRUD verbs from typed references" do
    methods = TypedRefsApp.route_set.routes.select(&.pattern.==("/typed/:id")).map(&.method)
    methods.should eq(["PUT", "PATCH", "DELETE"])
    actions = TypedRefsApp.route_set.routes.select(&.pattern.==("/typed/:id")).map(&.action)
    actions.should eq(["PostsController#update", "PostsController#update", "PostsController#destroy"])
  end
end
