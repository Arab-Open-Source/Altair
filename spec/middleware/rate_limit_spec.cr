# Altair — the rate-limit middleware over real HTTP.
#
# Boots an application with scoped rules and exercises the 429 path, the
# standard rate-limit headers, scope independence and key extraction —
# the way a client actually experiences them.
require "../spec_helper"

class RlPages < Altair::Controller
  def login : Nil
    response.text("login")
  end

  def items : Nil
    response.text("items")
  end

  def free : Nil
    response.text("free")
  end
end

private class RlApp < Altair::Application
  routes do
    get "/login", to: RlPages.login
    get "/api/items", to: RlPages.items
    get "/free", to: RlPages.free
  end
end

private def with_rl_app(& : Int32 -> Nil)
  Altair::Test.boot(RlApp, configure: ->(app : RlApp) {
    app.config.rate_limit.configure do |rl|
      rl.store :memory
      rl.limit 3, per: 1.minute
      rl.limit 1, per: 1.minute, only: ["/login"]
    end
  }) do |port|
    yield port
  end
end

describe "rate limit middleware" do
  it "allows up to the limit then answers 429 with Retry-After" do
    with_rl_app do |port|
      codes = 4.times.map { Altair::Test.get(port, "/api/items").status_code }.to_a
      codes.should eq([200, 200, 200, 429])
    end
  end

  it "stamps the standard rate-limit headers on allowed responses" do
    with_rl_app do |port|
      response = Altair::Test.get(port, "/api/items")
      response.headers["X-RateLimit-Limit"].should eq("3")
      response.headers["X-RateLimit-Remaining"].should eq("2")
      response.headers["X-RateLimit-Reset"].should_not be_nil
    end
  end

  it "includes Retry-After on denied responses" do
    with_rl_app do |port|
      4.times { Altair::Test.get(port, "/login") }
      denied = Altair::Test.get(port, "/login")
      denied.status_code.should eq(429)
      retry_after = denied.headers["Retry-After"].to_i
      retry_after.should be > 0
      retry_after.should be <= 60
    end
  end

  it "applies the most restrictive matching rule" do
    with_rl_app do |port|
      # /login matches both rules; the tighter one (1/minute) governs.
      first = Altair::Test.get(port, "/login")
      first.headers["X-RateLimit-Limit"].should eq("1")
      second = Altair::Test.get(port, "/login")
      second.status_code.should eq(429)
    end
  end

  it "leaves paths outside every rule untouched" do
    Altair::Test.boot(RlApp, configure: ->(app : RlApp) {
      app.config.rate_limit.configure do |rl|
        rl.store :memory
        rl.limit 1, per: 1.minute, only: ["/login"]
      end
    }) do |port|
      5.times do
        response = Altair::Test.get(port, "/free")
        response.status_code.should eq(200)
        response.headers.has_key?("X-RateLimit-Limit").should be_false
      end
    end
  end

  it "keys counters per client via X-Forwarded-For when trusted" do
    Altair::Test.boot(RlApp, configure: ->(app : RlApp) {
      app.config.rate_limit.configure do |rl|
        rl.store :memory
        rl.trusted_headers = true
        rl.limit 1, per: 1.minute
      end
    }) do |port|
      a1 = ::HTTP::Headers{"X-Forwarded-For" => "203.0.113.10"}
      b1 = ::HTTP::Headers{"X-Forwarded-For" => "203.0.113.11"}
      Altair::Test.get(port, "/api/items", headers: a1).status_code.should eq(200)
      Altair::Test.get(port, "/api/items", headers: a1).status_code.should eq(429)
      Altair::Test.get(port, "/api/items", headers: b1).status_code.should eq(200)
    end
  end

  it "ignores X-Forwarded-For unless trusted_headers is set" do
    Altair::Test.boot(RlApp, configure: ->(app : RlApp) {
      app.config.rate_limit.configure do |rl|
        rl.store :memory
        rl.limit 1, per: 1.minute
      end
    }) do |port|
      spoof = ::HTTP::Headers{"X-Forwarded-For" => "198.51.100.99"}
      Altair::Test.get(port, "/api/items", headers: spoof).status_code.should eq(200)
      # Same real client — the header must not have minted a new bucket.
      Altair::Test.get(port, "/api/items", headers: spoof).status_code.should eq(429)
    end
  end

  it "is a pass-through when no rules are configured" do
    Altair::Test.boot(RlApp) do |port|
      3.times do
        response = Altair::Test.get(port, "/login")
        response.status_code.should eq(200)
      end
    end
  end

  it "runs the same rules through the Redis store when selected" do
    url = ENV.fetch("ALTAIR_REDIS_URL", nil)
    pending! "set ALTAIR_REDIS_URL to run the Redis-backed middleware spec" unless url
    Altair::Test.boot(RlApp, configure: ->(app : RlApp) {
      app.config.rate_limit.configure do |rl|
        rl.store :redis
        rl.redis_url = url
        rl.limit 2, per: 1.minute
      end
    }) do |port|
      codes = 3.times.map { Altair::Test.get(port, "/api/items").status_code }.to_a
      codes.should eq([200, 200, 429])
    end
  end
end
