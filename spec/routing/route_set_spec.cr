# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Routing::RouteSet` and `Altair::Routing::Segment`:
# pattern parsing, registration and the duplicate-route guard.
require "../spec_helper"

private def noop_handler : Altair::Routing::Route::Handler
  ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) { }
end

describe Altair::Routing::Segment do
  describe ".parse" do
    it "splits a pattern into static and parameter segments" do
      segments = Altair::Routing::Segment.parse("/posts/:id")
      segments.size.should eq(2)
      segments[0].static?.should be_true
      segments[0].value.should eq("posts")
      segments[1].param?.should be_true
      segments[1].value.should eq("id")
    end

    it "parses paths with multiple parameters" do
      segments = Altair::Routing::Segment.parse("/books/:book_id/chapters/:chapter_id")
      segments.map(&.value).should eq(["books", "book_id", "chapters", "chapter_id"])
    end

    it "ignores leading and trailing slashes" do
      Altair::Routing::Segment.parse("/").should be_empty
      Altair::Routing::Segment.parse("/posts").size.should eq(1)
    end
  end
end

describe Altair::Routing::RouteSet do
  it "registers routes in definition order" do
    set = Altair::Routing::RouteSet.new
    set.register("GET", "/posts", noop_handler, "posts#index", "posts_path")
    set.register("POST", "/posts", noop_handler, "posts#create", "posts_path")
    set.routes.size.should eq(2)
    set.routes[0].method.should eq("GET")
    set.routes[1].action.should eq("posts#create")
  end

  it "rejects duplicate method and pattern pairs" do
    set = Altair::Routing::RouteSet.new
    set.register("GET", "/posts", noop_handler)
    expect_raises(Altair::ConfigurationError, /duplicate route/) do
      set.register("GET", "/posts", noop_handler)
    end
  end

  it "allows the same pattern under different methods" do
    set = Altair::Routing::RouteSet.new
    set.register("GET", "/posts", noop_handler)
    set.register("POST", "/posts", noop_handler)
    set.routes.size.should eq(2)
  end

  it "parses the pattern into segments at registration" do
    set = Altair::Routing::RouteSet.new
    route = set.register("GET", "/posts/:id", noop_handler)
    route.segments.map(&.value).should eq(["posts", "id"])
  end

  it "exposes routes through the per-class registry" do
    set = Altair::Routing.route_set_for(RouteSetSpecApp)
    set.routes.size.should eq(1)
    set.routes.first.pattern.should eq("/registry")
  end
end

class RouteSetSpecApp < Altair::Application
  routes do
    get "/registry", to: "registry#index"
  end
end
