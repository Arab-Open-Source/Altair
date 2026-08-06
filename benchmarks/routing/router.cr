# Altair — the batteries-included web framework for Crystal.
#
# Wave 0 baseline: the HTTP routing layer. This benchmark measures the
# `Altair::Routing::Router` in isolation — no database, no network — so the
# numbers reflect pure matching cost: path splitting, candidate selection,
# segment walking and parameter extraction. Run it with
#
#   crystal run --release benchmarks/routing/router.cr
#
# It reports lookups/sec and allocated bytes per lookup for the interesting
# request shapes: hot literal paths, parameterized paths, cold working sets,
# 404 misses and 405 method mismatches. The results are captured in
# `docs/architecture/performance-audit.md` ("Route layer baseline").
require "../../src/altair"

STDOUT.sync = true

# A no-op handler. Every registered route shares one, so the measurement is
# router-only: the handler is never invoked by `Router#find`.
NOOP = ->(request : Altair::HTTP::Request, response : Altair::HTTP::Response) { }

def route(method : String, pattern : String)
  Altair::Routing::Route.new(method: method, pattern: pattern, handler: NOOP)
end

# A realistic route table: a blog's REST resources, nested comments, a batch
# of top-level `/:name` parameterized routes, glob routes and literal dotted
# routes. The top-level parameterized routes are the worst case for the
# candidate scan, since every request tests all of them.
ROUTES = begin
  table = [] of Altair::Routing::Route
  table << route("GET", "/")
  table << route("GET", "/posts")
  table << route("POST", "/posts")
  table << route("GET", "/posts/new")
  table << route("GET", "/posts/:id")
  table << route("GET", "/posts/:id/edit")
  table << route("PUT", "/posts/:id")
  table << route("PATCH", "/posts/:id")
  table << route("DELETE", "/posts/:id")
  table << route("GET", "/posts/:post_id/comments")
  table << route("POST", "/posts/:post_id/comments")
  table << route("GET", "/posts/:post_id/comments/:id")
  table << route("DELETE", "/posts/:post_id/comments/:id")
  table << route("GET", "/users/:id")
  table << route("GET", "/users/:id/posts")
  table << route("GET", "/pages/:slug")
  table << route("GET", "/search")
  table << route("POST", "/search")
  table << route("GET", "/sitemap.xml")
  table << route("GET", "/favicon.ico")
  {"widgets", "gadgets", "things", "spaces", "boards", "threads", "tags",
   "categories", "authors", "editors", "reviewers", "subscribers", "channels",
   "groups", "teams", "projects", "tasks", "issues", "notes", "drafts"}.each do |name|
    table << route("GET", "/#{name}/:id")
  end
  # First-segment parameterized routes: every request tests the whole group,
  # so these model the "magic route" style of app with many `/:x` top-level
  # patterns.
  {"profile", "wall", "feed", "settings", "billing", "inbox", "outbox",
   "archive", "gallery", "library", "wishlist", "cart", "orders", "checkout",
   "bookmarks", "invites", "reports", "activity"}.each do |seg|
    table << route("GET", "/:#{seg}/:id")
  end
  {"files", "assets", "downloads", "attachments"}.each do |name|
    table << route("GET", "/#{name}/*path")
  end
  table
end

ROUTER = Altair::Routing::Router.new(ROUTES)

# A sink that defeats dead-code elimination: every benchmark block feeds its
# lookup result here, so the compiler cannot prove the lookups are pointless
# and strip them out.
module Sink
  @@total = 0

  def self.add(value : Int32)
    @@total += value
  end

  def self.total
    @@total
  end
end

# Consumes a match (or miss) so the enclosing lookup cannot be optimized away.
def sink_match(match : Altair::Routing::Match?)
  Sink.add(match.try(&.params.size) || 0)
end

# The candidate-scan width for a given first segment, estimated analytically
# from the route table: routes with that literal first segment, plus every
# parameterized route, plus every glob route. This is the work `find` performs
# before segment matching.
def scan_width(first_segment : String?) : Int32
  literal = ROUTES.count { |r| r.segments.first?.try(&.value) == first_segment }
  params = ROUTES.count { |r| r.segments.first?.try(&.kind) == Altair::Routing::Segment::Kind::Param }
  globs = ROUTES.count { |r| r.segments.first?.try(&.kind) == Altair::Routing::Segment::Kind::Glob }
  literal + params + globs
end

# Measures one request shape. The block performs exactly `lookups` `find`
# calls per invocation (usually 1). Reports lookups/sec and bytes allocated
# per lookup, averaged from a GC-frozen run. The allocation pass counts
# `iterations` invocations, scaled down for multi-lookup blocks so the frozen
# heap stays bounded.
def measure(label : String, first_segment : String?, lookups : Int32 = 1, &block)
  width = scan_width(first_segment)

  # Throughput: count invocations within a short wall-clock budget.
  started = Time.instant
  invocations = 0_u64
  while Time.instant - started < 300.milliseconds
    block.call
    invocations += 1
  end
  elapsed = Time.instant - started

  # Allocations: GC-frozen diff across a bounded number of lookups. The
  # iteration count is scaled by the lookups-per-block so the frozen heap
  # stays bounded (~100k lookups per shape).
  iterations = (100_000 / lookups).to_i.clamp(20, 20_000)
  GC.collect
  GC.disable
  before = GC.stats.bytes_since_gc
  iterations.times { block.call }
  after = GC.stats.bytes_since_gc
  GC.enable

  lookups_per_sec = invocations * lookups / elapsed.total_seconds
  bytes_per_lookup = (after - before) / (iterations * lookups)
  printf("%-24s %12.0f lookup/s   %8.1f B/op   (candidates: %d)\n", label, lookups_per_sec, bytes_per_lookup, width)
  STDOUT.flush
end

puts "Altair Router — #{ROUTES.size} routes, cache size #{1024}"
puts "--------------------------------------------------------------"

measure("hot index /posts", "posts") { sink_match(ROUTER.find("GET", "/posts")) }
measure("hot show /posts/5", "posts") { sink_match(ROUTER.find("GET", "/posts/5")) }
measure("hot top param /widgets/7", "widgets") { sink_match(ROUTER.find("GET", "/widgets/7")) }
measure("hot nested /posts/5/comments", "posts") { sink_match(ROUTER.find("GET", "/posts/5/comments")) }
measure("hot dotted /sitemap.xml", "sitemap.xml") { sink_match(ROUTER.find("GET", "/sitemap.xml")) }
measure("root /", nil) { sink_match(ROUTER.find("GET", "/")) }
measure("cold cycle 200 ids (in cache)", "posts", lookups: 200) do
  200.times { |i| sink_match(ROUTER.find("GET", "/posts/#{i}")) }
end
measure("cold cycle 5000 ids (> cache)", "posts", lookups: 5000) do
  5000.times { |i| sink_match(ROUTER.find("GET", "/posts/#{i + 600000}")) }
end
measure("404 /a/b/c/d", nil) { sink_match(ROUTER.find("GET", "/a/b/c/d")) }
measure("404 deep /posts/5/xyz", "posts") { sink_match(ROUTER.find("GET", "/posts/5/xyz")) }
measure("405 DELETE /search", "search") { sink_match(ROUTER.find("DELETE", "/search")) }
puts "--------------------------------------------------------------"
puts "sink total: #{Sink.total}"
