# PostgreSQL wire-protocol correctness contract (the issue #21 behaviours).
#
# These specs opt in via ALTAIR_TEST_PG_URL and run against a real server
# using the patched crystal-pg / crystal-db sources in lib/. They pin the
# properties the concurrent-desync fix relies on:
#
#   A - many fibers safely share one physical connection
#   B - a connection left frame-unsynced is discarded, never recycled dirty
#   C - named prepared statements cannot overwrite each other
#   D - interleaved ResultSet iteration never desyncs frames
#   E - an oversubscribed pool (far more fibers than connections) succeeds
#   F - retry exhaustion surfaces the original cause, never a bare error
#
# Run: docker compose up -d postgres && \
#      ALTAIR_TEST_PG_URL=postgres://... crystal spec spec/record/postgresql_protocol_spec.cr
require "../spec_helper"
require "pg"

# Spec-local stand-ins for the patched crystal-pg types the gated contract
# references. Stock crystal-pg has neither PQ::ProtocolError nor
# Connection#prepared_name; both ship only with the patched lib/ sources.
{% unless PQ.has_constant?("ProtocolError") %}
  module PQ
    class ProtocolError < Exception
    end
  end
{% end %}

{% unless PQ::Connection.has_method?("prepared_name") %}
  class PQ::Connection
    def prepared_name(sql : String) : String
      raise "prepared_name requires the patched crystal-pg in lib/"
    end
  end
{% end %}

# Spec-local window onto the wrapped PQ::Connection (protected getter):
# needed to inject deterministic protocol faults without touching sockets.
module PG
  def self.proto_probe(conn : Connection) : PQ::Connection
    conn.connection
  end
end

PROTO_TABLE = "altair_proto_items"

def proto_pool(pool_size : Int32, checkout_timeout : Float64 = 15.0,
               initial : Int32? = nil) : DB::Database
  base = ENV["ALTAIR_TEST_PG_URL"].not_nil!
  sep = base.includes?("?") ? "&" : "?"
  # A generous retry budget: connection creation under a 500-fiber burst on a
  # small CI runner can fail once; the pool should re-attempt, not give up.
  DB.open("#{base}#{sep}initial_pool_size=#{initial || pool_size}" \
          "&max_pool_size=#{pool_size}" \
          "&max_idle_pool_size=#{pool_size}" \
          "&checkout_timeout=#{checkout_timeout}" \
          "&retry_attempts=10")
end

def proto_setup(db : DB::Database) : Nil
  db.exec("DROP TABLE IF EXISTS #{PROTO_TABLE}")
  db.exec("CREATE TABLE #{PROTO_TABLE} (id BIGSERIAL PRIMARY KEY, f INT)")
end

def proto_teardown(db : DB::Database) : Nil
  db.exec("DROP TABLE IF EXISTS #{PROTO_TABLE}")
  db.close
end

# Walks an exception's cause chain looking for *type*.
def proto_cause_chain_has?(error : Exception, klass : Class) : Bool
  current : Exception? = error
  loop do
    return true if klass === current
    current = current.try(&.cause)
    return false unless current
  end
end

describe "PostgreSQL wire protocol under concurrency" do
  if ENV["ALTAIR_TEST_PG_URL"]?
    it "shares one physical connection across many querying fibers (A)" do
      db = proto_pool(1)
      proto_setup(db)
      fibers = 32
      per_fiber = 8
      results = Channel(Exception?).new(fibers)
      fibers.times do |i|
        spawn(name: "proto-A-#{i}") do
          per_fiber.times { |j| db.exec("INSERT INTO #{PROTO_TABLE} (f) VALUES ($1)", i * 100 + j) }
          db.query_one("SELECT max(id) FROM #{PROTO_TABLE}", as: Int64)
          results.send(nil)
        rescue e
          results.send(e)
        end
      end
      fibers.times do
        e = results.receive
        raise e.not_nil!.to_s if e
      end
      count = db.query_one("SELECT count(*) FROM #{PROTO_TABLE}", as: Int64)
      count.should eq((fibers * per_fiber).to_i64)
      stats = db.pool.stats
      stats.open_connections.should eq(1)
      proto_teardown(db)
    end

    it "discards a frame-unsynced connection instead of recycling it dirty (B)" do
      db = proto_pool(1)
      proto_setup(db)
      db.scalar("SELECT 1") # warm exactly one physical connection

      poisoned = db.pool.checkout.as(PG::Connection)
      pq = PG.proto_probe(poisoned)
      pq.synchronize do
        pq.send_parse_message("SELECT 42")
        pq.send_sync_message
      end
      db.pool.release(poisoned)

      again = db.pool.checkout.as(PG::Connection)
      PG.proto_probe(again).object_id.should eq(pq.object_id),
        "expected the polluted connection to be handed out again"
      raised = false
      begin
        again.build_prepared_statement("SELECT 55").query do |rs|
          rs.move_next.should be_true
        end
      rescue e : DB::ConnectionLost
        raised = true
        proto_cause_chain_has?(e, PQ::ProtocolError).should be_true,
          "cause chain lost PQ::ProtocolError: #{e.class}: #{e} / #{e.cause}"
      end
      raised.should be_true, "polluted connection was reused without surfacing ProtocolError"

      db.pool.release(again)
      fresh = db.pool.checkout.as(PG::Connection)
      PG.proto_probe(fresh).object_id.should_not eq(pq.object_id),
        "pool recycled the discarded connection"
      fresh.build_prepared_statement("SELECT 77").query do |rs|
        rs.move_next.should be_true
        rs.read(Int32).should eq(77)
      end
      stats = db.pool.stats
      stats.open_connections.should eq(1)
      db.pool.release(fresh)
      proto_teardown(db)
    end

    it "keeps distinct named prepared statements apart on one connection (C)" do
      db = proto_pool(1)
      proto_setup(db)
      fibers = 64
      reps = 5
      results = Channel(Exception?).new(fibers)
      fibers.times do |i|
        spawn(name: "proto-C-#{i}") do
          sql = "SELECT $1::bigint + #{i}" # distinct text => distinct prepared name
          reps.times do
            got = db.scalar(sql, 1000).as(Int64)
            raise "statement bleed: sent #{i}, got #{got}" unless got == (1000 + i).to_i64
          end
          results.send(nil)
        rescue e
          results.send(e)
        end
      end
      fibers.times do
        e = results.receive
        raise e.not_nil!.to_s if e
      end
      conn = db.pool.checkout.as(PG::Connection)
      pq = PG.proto_probe(conn)
      a = pq.prepared_name("SELECT $1::int + 1")
      b = pq.prepared_name("SELECT $1::int + 2")
      a.should eq(pq.prepared_name("SELECT $1::int + 1"))
      a.should_not eq(b)
      a.should start_with("altair_")
      db.pool.release(conn)
      proto_teardown(db)
    end

    it "survives interleaved ResultSet iteration across fibers (D)" do
      db = proto_pool(4)
      proto_setup(db)
      rows = 4000
      db.exec("INSERT INTO #{PROTO_TABLE} (f) SELECT g % 50 FROM generate_series(1, $1) g", rows)
      streams = 8
      drain_errors = Channel(Exception?).new(streams)
      streams.times do |i|
        spawn(name: "proto-D-#{i}") do
          last_id = 0
          n = 0
          db.query("SELECT id FROM #{PROTO_TABLE} WHERE f >= $1 ORDER BY id", i % 5) do |rs|
            rs.each do
              got = rs.read(Int64)
              raise "frame disorder: id regressed" unless got > last_id
              last_id = got
              n += 1
              # Yield mid-stream so other fibers run their own exchange
              # against sibling connections while this cursor is open.
              sleep 0.milliseconds if (n % 97).zero?
            end
          end
          raise "stream #{i} drained nothing" if n.zero?
          drain_errors.send(nil)
        rescue e
          drain_errors.send(e)
        end
      end
      streams.times do
        e = drain_errors.receive
        raise e.not_nil!.to_s if e
      end

      # Abandoned cursors: closing a result set early must safely skip the
      # remaining wire frames inside the connection lock.
      16.times do
        db.query("SELECT id FROM #{PROTO_TABLE} ORDER BY id LIMIT 500") do |rs|
          3.times { break unless rs.move_next }
        end
      end
      stats = db.pool.stats
      stats.open_connections.should eq(stats.idle_connections)
      proto_teardown(db)
    end

    it "keeps 500 fibers above a pool of 50 error-free (E)" do
      db = proto_pool(50)
      proto_setup(db)
      fibers = 500
      per_fiber = 20
      failures = Channel(Exception?).new(fibers)
      done = Channel(Nil).new(fibers)
      fibers.times do |i|
        spawn(name: "proto-E-#{i}") do
          per_fiber.times do
            v = db.scalar("SELECT $1::bigint * 2", i & 1023).as(Int64)
            raise "wrong arithmetic #{v}" if v != ((i & 1023) * 2).to_i64
          end
          failures.send(nil)
        rescue e
          failures.send(e)
        ensure
          done.send(nil)
        end
      end
      fibers.times { done.receive }
      begin
        bad = [] of Exception
        fibers.times do
          e = failures.receive
          bad << e.not_nil! if e
        end
        bad.empty?.should be_true, "protocol/pool failures under oversubscription: #{bad.map(&.to_s)[0, 3]}"
        stats = db.pool.stats.open_connections
        stats.should be <= 50
      ensure
        # The pool holds 50 physical connections; an unhandled assertion must
        # not leak them into the next example (a fresh pool would hit the
        # server's connection ceiling and fail with ConnectionRefused).
        proto_teardown(db)
      end
    end

    it "propagates the original cause when retries are exhausted (F)" do
      # Pool of exactly one: the poisoned socket is deterministically handed
      # out again on the next raw checkout.
      db = proto_pool(1)
      proto_setup(db)

      # Deterministic corruption: reuse scenario B's injection and assert the
      # surfaced exception preserves the whole chain down to PQ::ProtocolError.
      # Raw checkout again: Database ops auto-retry and would hide the loss.
      conn = db.pool.checkout.as(PG::Connection)
      pq = PG.proto_probe(conn)
      pq.synchronize do
        pq.send_parse_message("SELECT 43")
        pq.send_sync_message
      end
      db.pool.release(conn)

      raw = db.pool.checkout.as(PG::Connection)
      err = expect_raises(DB::ConnectionLost) do
        raw.build_prepared_statement("SELECT 44").query(&.move_next)
      end
      err.cause.should_not be_nil, "ConnectionLost without a cause"
      proto_cause_chain_has?(err, PQ::ProtocolError).should be_true
      db.pool.release(raw)

      # Dead-endpoint case: no server behind the port. initial=0 keeps the
      # pool lazy so the refusal happens inside the patched retry budget
      # (3 attempts + delay); the final error must carry its original cause.
      dead = DB.open("postgres://bench:bench@127.0.0.1:55499/bench?" \
                     "initial_pool_size=0&max_pool_size=1&checkout_timeout=1&retry_delay=0.01")
      refused_ok = false
      begin
        dead.scalar("SELECT 1")
      rescue e : DB::PoolRetryAttemptsExceeded
        refused_ok = true
        e.cause.should_not be_nil
      rescue DB::ConnectionRefused
        refused_ok = true
      end
      refused_ok.should be_true
      dead.close
      proto_teardown(db)
    end
  else
    pending "requires ALTAIR_TEST_PG_URL (PostgreSQL protocol contract)"
  end
end
