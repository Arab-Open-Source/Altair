# Altair — integration specs for the Redis client against a real Redis server.
#
# These specs are gated on the ALTAIR_REDIS_URL environment variable.
# Without it, they are skipped with a clear message (same pattern as
# ALTAIR_TEST_PG_URL for PostgreSQL contract tests).
#
# To run: docker compose up -d redis && ALTAIR_REDIS_URL=redis://localhost:6379 crystal spec spec/altair/redis/
require "../../spec_helper"
require "../../../src/altair/redis/client"
require "../../../src/altair/redis/pipeline"
require "../../../src/altair/redis/transaction"
require "../../../src/altair/redis/subscriber"

def with_redis(& : Altair::Redis::Client -> Nil)
  url = ENV.fetch("ALTAIR_REDIS_URL", nil)
  unless url
    # Without ALTAIR_REDIS_URL these specs cannot run — the caller should
    # check ENV before calling. Docker: docker compose up -d redis
    raise "ALTAIR_REDIS_URL not set — run docker compose up -d redis first"
  end
  client = Altair::Redis::Client.new(URI.parse(url))
  client.flushdb
  begin
    yield client
  ensure
    client.close
  end
end

describe Altair::Redis::Client do
  describe "strings" do
    it "round-trips a value" do
      with_redis do |client|
        client.set("key", "value").should be_true
        client.get("key").should eq("value")
        client.del("key").should eq(1)
        client.get("key").should be_nil
      end
    end

    it "supports SETEX for expiring keys" do
      with_redis do |client|
        client.setex("temp", 60, "data").should be_true
        client.ttl("temp").should be > 0
        client.persist("temp").should be_true
        client.ttl("temp").should eq(-1)
      end
    end

    it "supports SET NX for atomic create-if-not-exists" do
      with_redis do |client|
        client.set("lock", "first", nx: true).should be_true
        client.set("lock", "second", nx: true).should be_false
      end
    end

    it "increments and decrements" do
      with_redis do |client|
        client.incr("counter").should eq(1)
        client.incrby("counter", 10).should eq(11)
        client.decr("counter").should eq(10)
        client.del("counter")
      end
    end

    it "supports MSET and MGET" do
      with_redis do |client|
        client.mset({"a" => "1", "b" => "2"})
        client.mget("a", "b").should eq(["1", "2"])
      end
    end
  end

  describe "hashes" do
    it "stores and retrieves hash fields" do
      with_redis do |client|
        client.hset("user:1", "name", "Ali")
        client.hget("user:1", "name").should eq("Ali")
        all = client.hgetall("user:1")
        all["name"].should eq("Ali")
        client.hdel("user:1", "name")
        client.hexists("user:1", "name").should be_false
      end
    end
  end

  describe "lists" do
    it "pushes and pops from both ends" do
      with_redis do |client|
        client.rpush("queue", "a", "b", "c")
        client.llen("queue").should eq(3)
        client.lpop("queue").should eq("a")
        client.rpop("queue").should eq("c")
      end
    end

    it "ranges correctly" do
      with_redis do |client|
        client.rpush("list", "one", "two", "three")
        client.lrange("list", 0, -1).should eq(["one", "two", "three"])
        client.lrange("list", 0, 0).should eq(["one"])
      end
    end
  end

  describe "sets" do
    it "adds, checks membership and removes" do
      with_redis do |client|
        client.sadd("tags", "crystal", "web")
        client.sismember("tags", "crystal").should be_true
        client.scard("tags").should eq(2)
        client.srem("tags", "web")
        client.smembers("tags").should eq(Set{"crystal"})
      end
    end
  end

  describe "sorted sets" do
    it "adds, ranges by score, and removes" do
      with_redis do |client|
        client.zadd("lb", 100.0, "alice")
        client.zadd("lb", 200.0, "bob")
        client.zrange("lb", 0, -1).should eq(["alice", "bob"])
        client.zscore("lb", "bob").should eq(200.0)
        client.zrem("lb", "alice")
        client.zcard("lb").should eq(1)
      end
    end
  end

  describe "keys" do
    it "checks existence and type" do
      with_redis do |client|
        client.set("k", "v")
        client.exists("k").should eq(1)
        client.type("k").should eq("string")
        client.del("k")
        client.exists("k").should eq(0)
      end
    end

    it "iterates keys via scan_each" do
      with_redis do |client|
        client.set("scan:a", "1")
        client.set("scan:b", "2")
        found = [] of String
        client.scan_each(match: "scan:*") { |key| found << key }
        found.sort!.should eq(["scan:a", "scan:b"])
      end
    end
  end

  describe "pipeline" do
    it "executes multiple commands in one round trip" do
      with_redis do |client|
        results = client.pipeline do |pipe|
          pipe.set("p:a", "hello")
          pipe.incr("p:counter")
          pipe.get("p:a")
        end
        results.size.should eq(3)
      end
    end
  end

  describe "transactions" do
    it "runs commands atomically via MULTI/EXEC" do
      with_redis do |client|
        results = client.multi do |txn|
          txn.set("tx:key", "value")
          txn.incr("tx:counter")
        end
        results.should_not be_nil
        results.not_nil!.size.should eq(2)
        client.get("tx:key").should eq("value")
      end
    end
  end

  describe "pub/sub" do
    it "delivers published messages to subscribers on the same channel" do
      with_redis do |client|
        received = Channel(String).new

        spawn(name: "subscriber") do
          client.subscribe("test-ch") do |sub|
            sub.on_message do |channel, message|
              received.send(message) if channel == "test-ch"
            end
            sub.run
          end
        end

        sleep 100.milliseconds # let subscriber connect

        subscribers = client.publish("test-ch", "live-message")
        subscribers.should be > 0

        select
        when msg = received.receive
          msg.should eq("live-message")
        when timeout(3.seconds)
          fail "did not receive pub/sub message within timeout"
        end
      end
    end
  end
end
