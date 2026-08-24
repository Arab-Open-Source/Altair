# Altair — RedisStore contract specs.
#
# The shared rate-limit store contract executed against a real Redis
# through the framework's own client. Gated on `ALTAIR_REDIS_URL`, like
# the cache and redis-client suites.
require "../spec_helper"
require "./memory_store_spec"

describe Altair::RateLimit::RedisStore do
  run_store_contract(-> {
    url = ENV["ALTAIR_REDIS_URL"]?
    pending! "set ALTAIR_REDIS_URL to run the Redis rate-limit store contract" unless url
    Altair::RateLimit::RedisStore.new(URI.parse(url.not_nil!))
  })

  it "namespaces keys under a prefix" do
    url = ENV.fetch("ALTAIR_REDIS_URL", nil)
    pending! "set ALTAIR_REDIS_URL" unless url
    store = Altair::RateLimit::RedisStore.new(URI.parse(url), prefix: "rlspec")
    other = Altair::RateLimit::RedisStore.new(URI.parse(url), prefix: "rlother")
    begin
      t = 90_000.0
      2.times { |i| store.hit("ns", 2, 1.minute, now: t + i * 0.01) }
      fresh = other.hit("ns", 2, 1.minute, now: t + 0.02)
      fresh.allowed.should be_true
      fresh.remaining.should eq(1)
    ensure
      store.clear
      other.clear
      store.close
      other.close
    end
  end
end
