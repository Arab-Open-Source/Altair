# Specs for the ConditionalGet middleware: automatic ETag generation,
# 304 answers for matching If-None-Match, passthrough for oversized and
# non-200 responses, and the controller fresh?/stale? helpers.
require "../spec_helper"

private class EtagPages < Altair::Controller
  def body : Nil
    response.text("etag me " * 10)
  end

  def big : Nil
    response.text("x" * 2_000_000)
  end

  def missing : Nil
    response.status = ::HTTP::Status::NOT_FOUND
    response.text("not found")
  end

  def manual : Nil
    unless fresh?(etag: %("fixed"))
      response.text("manual body")
    end
  end

  def stale : Nil
    if stale?(etag: %("fixed"))
      response.text("stale body")
    end
  end
end

private class EtagApp < Altair::Application
  routes do
    get "/body", to: EtagPages.body
    get "/big", to: EtagPages.big
    get "/missing", to: EtagPages.missing
    get "/manual", to: EtagPages.manual
    get "/stale", to: EtagPages.stale
  end
end

describe Altair::Middleware::ConditionalGet do
  it "stamps a strong ETag on success responses when enabled" do
    Altair::Test.boot(EtagApp, configure: ->(app : EtagApp) {
      app.config.conditional_get.enabled = true
    }) do |port|
      response = Altair::Test.get(port, "/body")
      response.headers["ETag"]?.should_not be_nil
      response.headers["ETag"].should contain("\"")
      response.body.should eq("etag me " * 10)
    end
  end

  it "answers 304 with no body when If-None-Match matches" do
    Altair::Test.boot(EtagApp, configure: ->(app : EtagApp) {
      app.config.conditional_get.enabled = true
    }) do |port|
      first = Altair::Test.get(port, "/body")
      etag = first.headers["ETag"]
      second = Altair::Test.get(port, "/body", headers: ::HTTP::Headers{"If-None-Match" => etag})
      second.status_code.should eq(304)
      second.body.should be_empty
    end
  end

  it "matches weak validators and lists" do
    Altair::HTTP::ETag.matches?(%(W/"abc", "def"), %("abc")).should be_true
    Altair::HTTP::ETag.matches?(%("abc"), %("xyz")).should be_false
    Altair::HTTP::ETag.matches?("*", %("anything")).should be_true
    Altair::HTTP::ETag.matches?(nil, %("abc")).should be_false
  end

  it "serves the body unchanged when validators differ" do
    Altair::Test.boot(EtagApp, configure: ->(app : EtagApp) {
      app.config.conditional_get.enabled = true
    }) do |port|
      response = Altair::Test.get(port, "/body", headers: ::HTTP::Headers{"If-None-Match" => %("stale")})
      response.status_code.should eq(200)
      response.body.should eq("etag me " * 10)
    end
  end

  it "passes oversized bodies through without an ETag" do
    Altair::Test.boot(EtagApp, configure: ->(app : EtagApp) {
      app.config.conditional_get.enabled = true
    }) do |port|
      response = Altair::Test.get(port, "/big")
      response.headers["ETag"]?.should be_nil
      response.body.size.should eq(2_000_000)
    end
  end

  it "leaves non-200 responses untagged" do
    Altair::Test.boot(EtagApp, configure: ->(app : EtagApp) {
      app.config.conditional_get.enabled = true
    }) do |port|
      response = Altair::Test.get(port, "/missing")
      response.status_code.should eq(404)
      response.headers["ETag"]?.should be_nil
      response.body.should eq("not found")
    end
  end

  it "is a pass-through while disabled" do
    Altair::Test.boot(EtagApp) do |port|
      response = Altair::Test.get(port, "/body")
      response.headers["ETag"]?.should be_nil
    end
  end

  it "short-circuits through the controller fresh? helper" do
    Altair::Test.boot(EtagApp) do |port|
      fresh = Altair::Test.get(port, "/manual", headers: ::HTTP::Headers{"If-None-Match" => %("fixed")})
      fresh.status_code.should eq(304)
      fresh.body.should be_empty
      stale = Altair::Test.get(port, "/manual", headers: ::HTTP::Headers{"If-None-Match" => %("other")})
      stale.status_code.should eq(200)
      stale.body.should eq("manual body")
    end
  end

  it "supports the stale? helper shape" do
    Altair::Test.boot(EtagApp) do |port|
      response = Altair::Test.get(port, "/stale", headers: ::HTTP::Headers{"If-None-Match" => %("fixed")})
      response.status_code.should eq(304)
      response.body.should be_empty
      response2 = Altair::Test.get(port, "/stale")
      response2.body.should eq("stale body")
    end
  end
end
