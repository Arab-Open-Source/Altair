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

  describe "#fetch" do
    it "fetches strings" do
      params = Altair::HTTP::Params.new(URI::Params.parse("title=Altair"))
      params.fetch("title", String).should eq("Altair")
    end

    it "fetches integers" do
      params = Altair::HTTP::Params.new(URI::Params.parse("count=42"))
      params.fetch("count", Int32).should eq(42)
    end

    it "fetches int64 and floats" do
      params = Altair::HTTP::Params.new(URI::Params.parse("big=9000000000&ratio=1.5"))
      params.fetch("big", Int64).should eq(9_000_000_000_i64)
      params.fetch("ratio", Float64).should eq(1.5)
    end

    it "fetches booleans" do
      params = Altair::HTTP::Params.new(URI::Params.parse("flag=on&off=0"))
      params.fetch("flag", Bool).should be_true
      params.fetch("off", Bool).should be_false
    end

    it "raises ParamsError for missing parameters" do
      params = Altair::HTTP::Params.new(URI::Params.new)
      expect_raises(Altair::HTTP::ParamsError, "Missing parameter: count") do
        params.fetch("count", Int32)
      end
    end

    it "raises ParamsError for malformed values" do
      params = Altair::HTTP::Params.new(URI::Params.parse("count=abc"))
      expect_raises(Altair::HTTP::ParamsError, /Expected Int32/) do
        params.fetch("count", Int32)
      end
    end

    it "returns nil through the nilable overloads" do
      params = Altair::HTTP::Params.new(URI::Params.parse("count=42&bad=abc"))
      params.fetch?("count", Int32).should eq(42)
      params.fetch?("count", String).should eq("42")
      params.fetch?("missing", Int32).should be_nil
      params.fetch?("bad", Int32).should be_nil
    end
  end

  it "collects repeated values with fetch_all" do
    params = Altair::HTTP::Params.new(URI::Params.parse("tags=a&tags=b"))
    params.fetch_all("tags").should eq(["a", "b"])
  end

  describe "#require / #permit" do
    it "passes through require when the key exists" do
      params = Altair::HTTP::Params.new(URI::Params.parse("title=Altair"))
      params.require("title").should be(params)
    end

    it "raises KeyError from require when the key is missing" do
      params = Altair::HTTP::Params.new(URI::Params.new)
      expect_raises(KeyError) { params.require("title") }
    end

    it "filters the bag with permit" do
      params = Altair::HTTP::Params.new(URI::Params.parse("title=Altair&body=Hello&admin=1"))
      params.permit("title", "body").should eq({"title" => "Altair", "body" => "Hello"})
    end

    it "raises KeyError from permit for missing keys" do
      params = Altair::HTTP::Params.new(URI::Params.parse("title=Altair"))
      expect_raises(KeyError) { params.permit("title", "nope") }
    end

    it "chains require with permit for the strong params pattern" do
      params = Altair::HTTP::Params.new(URI::Params.parse("post[title]=Altair&post[body]=Hi&admin=1"))
      filtered = params.require("post[title]").permit("post[title]", "post[body]")
      filtered.should eq({"post[title]" => "Altair", "post[body]" => "Hi"})
    end
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

  it "reads the body up to the configured limit" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.body = "x" * 100
    request = Altair::HTTP::Request.new(raw, max_body_size: 200_i64)
    request.body.should eq("x" * 100)
  end

  it "accepts a body exactly at the limit" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.body = "x" * 200
    request = Altair::HTTP::Request.new(raw, max_body_size: 200_i64)
    request.body.should eq("x" * 200)
  end

  it "raises PayloadTooLarge when the body exceeds the limit" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.body = "x" * 300
    expect_raises(Altair::HTTP::PayloadTooLarge) do
      Altair::HTTP::Request.new(raw, max_body_size: 200_i64)
    end
  end

  it "reads the body without bound when the limit is nil" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.body = "x" * 5000
    request = Altair::HTTP::Request.new(raw, max_body_size: nil)
    request.body.not_nil!.size.should eq(5000)
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
