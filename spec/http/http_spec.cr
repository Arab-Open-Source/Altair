# Altair — the batteries-included web framework for Crystal.
#
# Specs for the HTTP abstractions: parameter bags, request wrappers and
# response helpers.
require "../spec_helper"

describe Altair::HTTP::Params do
  it "merges query and body parameters, query taking precedence" do
    params = Altair::HTTP::Params.new(
      URI::Params.parse("a=1&b=2"),
      URI::Params.parse("b=3&c=4")
    )
    params["a"].should eq("1")
    params["b"].should eq("2")
    params["c"].should eq("4")
  end

  it "gives route parameters the highest precedence" do
    params = Altair::HTTP::Params.new(URI::Params.parse("id=9")).merge_route({"id" => "7"})
    params["id"].should eq("7")
  end

  it "returns nil for missing parameters with []?" do
    params = Altair::HTTP::Params.new(URI::Params.new)
    params["missing"]?.should be_nil
  end

  it "raises KeyError for missing parameters with []" do
    params = Altair::HTTP::Params.new(URI::Params.new)
    expect_raises(KeyError) { params["missing"] }
  end

  it "answers existence checks" do
    params = Altair::HTTP::Params.new(URI::Params.parse("a=1"))
    params.has_key?("a").should be_true
    params.has_key?("b").should be_false
  end

  it "merges everything into a plain hash" do
    params = Altair::HTTP::Params.new(URI::Params.parse("a=1")).merge_route({"b" => "2"})
    params.to_h.should eq({"a" => "1", "b" => "2"})
  end
end

describe Altair::HTTP::Request do
  it "exposes method, path and full path" do
    request = Altair::HTTP::Request.new(HTTP::Request.new("GET", "/posts?page=2"))
    request.method.should eq("GET")
    request.path.should eq("/posts")
    request.full_path.should eq("/posts?page=2")
  end

  it "exposes headers and parameters" do
    raw = HTTP::Request.new("POST", "/posts?ref=api")
    raw.headers["Content-Type"] = "application/json"
    request = Altair::HTTP::Request.new(raw)
    request.headers["Content-Type"].should eq("application/json")
    request.params["ref"].should eq("api")
  end

  it "exposes the body when present" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.body = "payload"
    Altair::HTTP::Request.new(raw).body.should eq("payload")
  end

  it "returns nil for a missing body" do
    request = Altair::HTTP::Request.new(HTTP::Request.new("GET", "/"))
    request.body.should be_nil
  end
end

describe Altair::HTTP::Response do
  it "sends JSON with the proper content type" do
    io = IO::Memory.new
    raw = HTTP::Server::Response.new(io)
    response = Altair::HTTP::Response.new(raw)
    response.json(%({"ok":true}))
    raw.close
    response.headers["Content-Type"].should eq("application/json; charset=utf-8")
    io.to_s.should contain(%({"ok":true}))
  end

  it "sends HTML with the proper content type" do
    io = IO::Memory.new
    raw = HTTP::Server::Response.new(io)
    response = Altair::HTTP::Response.new(raw)
    response.html("<h1>Hi</h1>")
    raw.close
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    io.to_s.should contain("<h1>Hi</h1>")
  end

  it "redirects with a 302 status and Location header" do
    io = IO::Memory.new
    response = Altair::HTTP::Response.new(HTTP::Server::Response.new(io))
    response.redirect("/posts")
    io.to_s.should contain("HTTP/1.1 302")
    io.to_s.should contain("Location: /posts")
  end

  it "writes raw output" do
    io = IO::Memory.new
    raw = HTTP::Server::Response.new(io)
    response = Altair::HTTP::Response.new(raw)
    response.print("raw")
    raw.close
    io.to_s.should contain("raw")
  end
end
