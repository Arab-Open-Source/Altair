# Altair benchmark — record hot-path allocation benchmark.
#
# Measures bytes allocated per operation for the record write and read
# paths (and the request JSON body parse that feeds the write path). The
# Boehm collector is disabled while a measurement runs (`GC_disable`), so
# `GC_get_bytes_since_gc` grows by exactly what the operation allocated;
# warmup iterations before each measurement build prepared statements, the
# pool and caches first. Wall time per operation is reported as a secondary
# number — it depends on the host and the database round trip, the heap
# delta does not.
#
# Run from this directory (the app's shard root):
#
#   crystal run bench/record_bench.cr
#
# Uses DATABASE_URL when set, otherwise a scratch SQLite file.

ENV["DATABASE_URL"] ||= "sqlite3:///tmp/record_bench.db"
File.delete("/tmp/record_bench.db") if File.exists?("/tmp/record_bench.db")

require "altair"
require "altair/record/adapters/postgresql"
require "../db/schema"
require "../src/models/item"
require "../src/controllers/application_controller"
require "../src/controllers/items_controller"
require "../src/application"

@[Link("gc")]
lib LibBoehm
  fun disable = GC_disable
  fun enable = GC_enable
  fun get_bytes_since_gc = GC_get_bytes_since_gc : LibC::SizeT
end

module RecordBench
  # Runs `iterations` copies of the block with the collector disabled and
  # prints bytes/op (heap delta) and ns/op (wall clock).
  def self.measure(label : String, iterations : Int32 = 2_000, &block : ->) : Nil
    25.times { block.call }
    GC.collect
    LibBoehm.disable
    start = Time.instant
    before = LibBoehm.get_bytes_since_gc
    iterations.times { block.call }
    after = LibBoehm.get_bytes_since_gc
    finish = Time.instant
    LibBoehm.enable
    bytes = (after - before) // iterations
    ns = (finish - start).total_nanoseconds / iterations
    puts "%-38s %10d B/op %8.1f ns/op" % {label, bytes, ns}
  end

  # Mirrors ItemsController#item_json so the measured string is byte-for-byte
  # the response the server would render.
  def self.item_json(item : Item) : String
    String.build do |io|
      JSON.build(io) do |json|
        json.object do
          json.field "id", item.id
          json.field "name", item.name
          json.field "price", item.price
        end
      end
    end
  end
end

# Build the shared application (reads DATABASE_URL and pool sizing from
# application.cr) and open the pool.
Bench.instance
Altair::Record.connection

if (ENV["DATABASE_URL"]? || "").starts_with?("sqlite")
  Altair::Record.connection.exec(
    "CREATE TABLE IF NOT EXISTS items_altair (" \
    "id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, price REAL NOT NULL)"
  )
end

seed = Item.create(name: "seed", price: 1.0)
seed_id = seed.id.not_nil!
raw_insert = "INSERT INTO items_altair (name, price) VALUES (" \
             "#{Altair::Record.connection.adapter.placeholder(0)}, " \
             "#{Altair::Record.connection.adapter.placeholder(1)}) RETURNING id"

puts "Altair record allocation benchmark"
puts "Crystal #{Crystal::VERSION} | #{ENV["DATABASE_URL"]? || "sqlite3 scratch"} | frozen-GC heap delta"
puts
puts "%-38s %10s %8s" % {"operation", "B/op", "ns/op"}

RecordBench.measure("baseline (empty loop)") { }
RecordBench.measure("JSON.parse (flat request body)") { JSON.parse(%({"name":"bench","price":12.5})) }
RecordBench.measure("JSON::PullParser (flat body, no tree)") do
  JSON::PullParser.new(%({"name":"bench","price":12.5})).tap do |parser|
    parser.read_object do |key|
      case key
      when "name"  then parser.read_string
      when "price" then parser.read_float
      else              parser.skip
      end
    end
  end
end
record = Item.new(name: "bench", price: 12.5)
RecordBench.measure("Item.new (model construction)", 20_000) { Item.new(name: "bench", price: 12.5) }
RecordBench.measure("record.valid? (no validations)", 20_000) { record.valid? }
RecordBench.measure("Item.create (full write path)") { Item.create(name: "bench", price: 12.5) }
RecordBench.measure("item.save (fresh record)") do
  item = Item.new(name: "bench", price: 12.5)
  item.save
end
RecordBench.measure("raw exec (adapter floor)") do
  Altair::Record.connection.exec(raw_insert, "bench", 12.5)
end
RecordBench.measure("Item.find(seed_id) (select + decode)") { Item.find(seed_id) }
RecordBench.measure("item_json (response build)", 20_000) { RecordBench.item_json(seed) }
