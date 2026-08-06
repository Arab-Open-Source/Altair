# Altair — the batteries-included web framework for Crystal.
#
# Wave 3: the HTTP request wrapper. This benchmark measures how much work
# `Altair::HTTP::Request` does on construction versus on first parameter
# access. Since Wave 3 made `query_params`, `json` and the unified `params`
# bag lazy, constructing a request should parse nothing, and a request whose
# handler never reads parameters should stay at near-zero allocations. Run it
# with
#
#   crystal run --release benchmarks/http/request.cr
#
# Numbers are captured in `docs/architecture/performance-audit.md` ("Request
# layer").
require "../../src/altair"

STDOUT.sync = true

# A request whose handler reads GET params parses the query string and builds
# the unified bag.
def measured_request(path : String, body : String? = nil, content_type : String? = nil)
  raw = HTTP::Request.new("GET", path)
  raw.body = body
  raw.headers["Content-Type"] = content_type if content_type
  raw
end

QUERY_RAW = measured_request("/posts?page=2&sort=title&tag=altair&page=1")
FORM_RAW  = measured_request("/posts", "title=x&body=Hello", "application/x-www-form-urlencoded")
JSON_RAW  = measured_request("/posts", %({"title": "Hello", "count": 3}), "application/json")

# A sink that defeats dead-code elimination
module Sink
  @@total = 0

  def self.add(value : Int32)
    @@total += value
  end

  def self.total
    @@total
  end
end

# Measures one benchmark block. The block performs `work` request operations
# per invocation. Reports ops/sec and bytes/op, GC-frozen as in the router
# benchmark.
def measure(label : String, work : Int32 = 1, &block)
  started = Time.instant
  invocations = 0_u64
  while Time.instant - started < 300.milliseconds
    block.call
    invocations += 1
  end
  elapsed = Time.instant - started

  iterations = (100_000 / work).to_i.clamp(20, 20_000)
  GC.collect
  GC.disable
  before = GC.stats.bytes_since_gc
  iterations.times { block.call }
  after = GC.stats.bytes_since_gc
  GC.enable

  ops_per_sec = invocations * work / elapsed.total_seconds
  bytes_per_op = (after - before) / (iterations * work)
  printf("%-28s %12.0f op/s   %8.1f B/op\n", label, ops_per_sec, bytes_per_op)
  STDOUT.flush
end

puts "Altair HTTP Request"
puts "--------------------------------------------------------------"

measure("construct GET (no params read)") do
  req = Altair::HTTP::Request.new(QUERY_RAW)
  Sink.add(req.path.bytesize)
end
measure("construct GET + read a param") do
  req = Altair::HTTP::Request.new(QUERY_RAW)
  Sink.add(req.params["page"]?.try(&.bytesize) || 0)
end
measure("construct POST form + read a param") do
  req = Altair::HTTP::Request.new(FORM_RAW)
  Sink.add(req.params["title"]?.try(&.bytesize) || 0)
end
measure("construct POST json + read json + scalar") do
  req = Altair::HTTP::Request.new(JSON_RAW)
  Sink.add((req.json.try(&.as_h.size) || 0) + (req.params["title"]?.try(&.bytesize) || 0))
end
puts "--------------------------------------------------------------"
puts "sink total: #{Sink.total}"
