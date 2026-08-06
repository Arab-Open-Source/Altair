# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Routing::Router#resolve` (Wave 2): one scan that answers
# both "which route matches" and "which methods are allowed when the method
# does not". The dispatch path uses it so a 405 never pays for a second
# candidate walk. Candidate selection is a three-way merge of the per-group
# ascending index lists — no combined array, no sort — so these specs also
# pin that definition order survives across index groups.
require "../spec_helper"

private def noop_handler : Altair::Routing::Route::Handler
  ->(_request : Altair::HTTP::Request, _response : Altair::HTTP::Response) { }
end

private def build_router(routes : Array(Tuple(String, String)), cache_size : Int32 = 1024)
  registered = routes.map do |(method, pattern)|
    Altair::Routing::Route.new(method: method, pattern: pattern, handler: noop_handler)
  end
  Altair::Routing::Router.new(registered, cache_size)
end

describe Altair::Routing::Router do
  describe "#resolve" do
    it "returns a match for a matching method and path" do
      router = build_router([{"GET", "/posts/:id"}])
      resolution = router.resolve("GET", "/posts/5")
      resolution.match.should_not be_nil
      resolution.match!.params.should eq({"id" => "5"})
      resolution.allowed.should be_nil
    end

    it "returns the allowed methods on a method mismatch" do
      router = build_router([{"GET", "/search"}, {"POST", "/search"}])
      resolution = router.resolve("DELETE", "/search")
      resolution.match.should be_nil
      resolution.allowed.should eq(["GET", "POST"])
    end

    it "returns neither a match nor allowed methods on a true miss" do
      router = build_router([{"GET", "/posts"}])
      resolution = router.resolve("GET", "/nope")
      resolution.match.should be_nil
      resolution.allowed.should be_nil
    end

    it "does not repeat methods in the allowed list" do
      router = build_router([{"GET", "/posts"}, {"POST", "/posts"}, {"PUT", "/posts"}])
      router.resolve("DELETE", "/posts").allowed.should eq(["GET", "POST", "PUT"])
    end

    it "memoizes a resolved match across lookups" do
      router = build_router([{"GET", "/posts/:id"}])
      first = router.resolve("GET", "/posts/5")
      second = router.resolve("GET", "/posts/5")
      first.match!.params.should be(second.match!.params)
    end

    it "resolves the format suffix with its format parameter" do
      router = build_router([{"GET", "/posts/:id"}])
      resolution = router.resolve("GET", "/posts/5.json")
      resolution.match!.params.should eq({"id" => "5", "format" => "json"})
    end

    it "keeps definition order across index groups (param before literal)" do
      router = build_router([{"GET", "/:id"}, {"GET", "/posts"}])
      resolution = router.resolve("GET", "/posts")
      resolution.match!.route.pattern.should eq("/:id")
    end

    it "keeps definition order across index groups (literal before param)" do
      router = build_router([{"GET", "/posts"}, {"GET", "/:id"}])
      resolution = router.resolve("GET", "/posts")
      resolution.match!.route.pattern.should eq("/posts")
    end

    it "keeps definition order across index groups (glob last)" do
      router = build_router([{"GET", "/files/*path"}, {"GET", "/files/notes"}])
      resolution = router.resolve("GET", "/files/notes")
      resolution.match!.route.pattern.should eq("/files/*path")
    end
  end
end
