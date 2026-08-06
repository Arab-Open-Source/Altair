# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `Altair::Routing::Router` route-lookup cache (Wave 1): a
# repeated request to the same `"METHOD path"` reuses the cached match and
# its extracted params instead of re-walking the segments. The cache is LRU,
# matches only (misses are never stored), and honors a configurable size.
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
  describe "route lookup cache" do
    it "reuses the cached params object for a repeated lookup" do
      router = build_router([{"GET", "/posts/:id"}])
      first = router.find("GET", "/posts/5").not_nil!
      second = router.find("GET", "/posts/5").not_nil!
      first.params.should be(second.params)
    end

    it "distinguishes methods in the cache key" do
      router = build_router([{"GET", "/posts"}, {"POST", "/posts"}])
      get_match = router.find("GET", "/posts").not_nil!
      post_match = router.find("POST", "/posts").not_nil!
      # A POST lookup must not answer with the cached GET match.
      post_match.route.method.should eq("POST")
      get_match.params.should_not be(post_match.params)
    end

    it "caches a distinct result per distinct path" do
      router = build_router([{"GET", "/posts/:id"}])
      a = router.find("GET", "/posts/5").not_nil!
      b = router.find("GET", "/posts/6").not_nil!
      a.params.should_not be(b.params)
    end

    it "keeps the extracted params correct on a cache hit" do
      router = build_router([{"GET", "/posts/:id"}])
      first = router.find("GET", "/posts/5").not_nil!
      second = router.find("GET", "/posts/5").not_nil!
      second.params.should eq({"id" => "5"})
      first.params.should be(second.params)
    end

    it "caches the format suffix result with its format parameter" do
      router = build_router([{"GET", "/posts/:id"}])
      first = router.find("GET", "/posts/5.json").not_nil!
      second = router.find("GET", "/posts/5.json").not_nil!
      second.params["format"].should eq("json")
      second.params["id"].should eq("5")
      first.params.should be(second.params)
    end

    it "evicts the least-recently-used entry at capacity" do
      router = build_router([{"GET", "/:a"}, {"GET", "/:b"}, {"GET", "/:c"}], cache_size: 2)
      x = router.find("GET", "/a").not_nil!
      router.find("GET", "/b").not_nil!
      router.find("GET", "/c").not_nil! # evicts /a
      evicted = router.find("GET", "/a").not_nil!
      evicted.params.should_not be(x.params)
    end

    it "reorders entries on access (LRU, not FIFO)" do
      router = build_router([{"GET", "/:a"}, {"GET", "/:b"}, {"GET", "/:c"}], cache_size: 2)
      router.find("GET", "/a").not_nil!
      b = router.find("GET", "/b").not_nil!
      router.find("GET", "/c").not_nil! # evicts /a (least recently used)
      b_hit = router.find("GET", "/b").not_nil!
      b_hit.params.should be(b.params) # /b survived, /a was evicted
    end

    it "never caches a miss, so 404 scans cannot evict hot entries" do
      router = build_router([{"GET", "/:a"}, {"GET", "/:b"}], cache_size: 1)
      hot = router.find("GET", "/a").not_nil!
      100.times { |i| router.find("GET", "/missing/#{i}") }
      again = router.find("GET", "/a").not_nil!
      again.params.should be(hot.params)
    end

    it "returns nil for a cache-hit miss the same as a miss" do
      router = build_router([{"GET", "/posts"}])
      2.times { router.find("GET", "/nope").should be_nil }
    end

    it "does not cache when the cache size is zero" do
      router = build_router([{"GET", "/posts/:id"}], cache_size: 0)
      first = router.find("GET", "/posts/5").not_nil!
      second = router.find("GET", "/posts/5").not_nil!
      first.params.should_not be(second.params)
    end
  end
end
