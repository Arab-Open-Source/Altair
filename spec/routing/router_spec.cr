# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Routing::Router`: segment matching, parameter
# extraction, definition-order priority, HEAD-requests-GET and 405 method
# detection.
require "../spec_helper"

private def noop_handler : Altair::Routing::Route::Handler
  ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) { }
end

private def build_router(routes : Array(Tuple(String, String)))
  registered = routes.map do |(method, pattern)|
    Altair::Routing::Route.new(
      method: method,
      pattern: pattern,
      handler: noop_handler,
      action: "pages#index",
    )
  end
  Altair::Routing::Router.new(registered)
end

describe Altair::Routing::Router do
  describe "#find" do
    it "matches a static path" do
      router = build_router([{"GET", "/posts"}])
      match = router.find("GET", "/posts")
      match.should_not be_nil
      match.not_nil!.route.pattern.should eq("/posts")
      match.not_nil!.params.should be_empty
    end

    it "extracts parameter values from the path" do
      router = build_router([{"GET", "/posts/:id"}])
      match = router.find("GET", "/posts/5")
      match.should_not be_nil
      match.not_nil!.params["id"].should eq("5")
    end

    it "extracts multiple parameters" do
      router = build_router([{"GET", "/books/:book_id/chapters/:chapter_id"}])
      match = router.find("GET", "/books/3/chapters/7")
      match.not_nil!.params.should eq({"book_id" => "3", "chapter_id" => "7"})
    end

    it "decodes percent-encoded parameter values" do
      router = build_router([{"GET", "/hello/:name"}])
      match = router.find("GET", "/hello/altair%20rocks")
      match.not_nil!.params["name"].should eq("altair rocks")
    end

    it "returns nil when the path does not match" do
      router = build_router([{"GET", "/posts"}])
      router.find("GET", "/nope").should be_nil
    end

    it "returns nil when the segment count differs" do
      router = build_router([{"GET", "/posts/:id"}])
      router.find("GET", "/posts").should be_nil
      router.find("GET", "/posts/5/extra").should be_nil
    end

    it "returns nil when the method does not match" do
      router = build_router([{"GET", "/posts"}])
      router.find("POST", "/posts").should be_nil
    end

    it "matches HEAD requests against GET routes" do
      router = build_router([{"GET", "/posts"}])
      router.find("HEAD", "/posts").should_not be_nil
    end

    it "prefers the first route in definition order" do
      router = build_router([{"GET", "/posts/:id"}, {"GET", "/posts/new"}])
      match = router.find("GET", "/posts/new")
      match.not_nil!.params["id"].should eq("new")
      match.not_nil!.route.pattern.should eq("/posts/:id")
    end

    it "matches a parameter against a later static segment" do
      router = build_router([{"GET", "/posts/new"}, {"GET", "/posts/:id"}])
      match = router.find("GET", "/posts/new")
      match.not_nil!.route.pattern.should eq("/posts/new")
    end
  end

  describe "#allowed_for" do
    it "returns the allowed methods when the path exists but the method does not" do
      router = build_router([{"GET", "/posts"}, {"POST", "/posts"}])
      allowed = router.allowed_for("/posts")
      allowed.should eq(["GET", "POST"])
    end

    it "returns nil when the path matches nothing" do
      router = build_router([{"GET", "/posts"}])
      router.allowed_for("/nope").should be_nil
    end

    it "does not repeat methods" do
      router = build_router([{"GET", "/posts"}, {"POST", "/posts"}, {"PUT", "/posts"}])
      router.allowed_for("/posts").should eq(["GET", "POST", "PUT"])
    end
  end

  describe "#empty?" do
    it "is true without routes and false otherwise" do
      Altair::Routing::Router.new([] of Altair::Routing::Route).empty?.should be_true
      build_router([{"GET", "/posts"}]).empty?.should be_false
    end
  end
end
