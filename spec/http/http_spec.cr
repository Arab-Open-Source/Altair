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

    it "omits permitted keys that are absent instead of raising" do
      params = Altair::HTTP::Params.new(URI::Params.parse("title=Altair"))
      params.permit("title", "nope").should eq({"title" => "Altair"})
    end

    it "returns an empty hash when no permitted key is present" do
      params = Altair::HTTP::Params.new(URI::Params.new)
      params.permit("title").should eq({} of String => String)
    end

    it "chains require with permit for the strong params pattern" do
      params = Altair::HTTP::Params.new(URI::Params.parse("post[title]=Altair&post[body]=Hi&admin=1"))
      filtered = params.require("post[title]").permit("post[title]", "post[body]")
      filtered.should eq({"post[title]" => "Altair", "post[body]" => "Hi"})
    end

    it "permits an optional field next to a required one" do
      params = Altair::HTTP::Params.new(URI::Params.parse("title=Altair"))
      params.require("title").permit("title", "optional").should eq({"title" => "Altair"})
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

  it "defaults the format to html" do
    request = Altair::HTTP::Request.new(HTTP::Request.new("GET", "/posts"))
    request.format.should eq(:html)
  end

  it "derives the format from the Accept header" do
    raw = HTTP::Request.new("GET", "/posts")
    raw.headers["Accept"] = "application/json"
    Altair::HTTP::Request.new(raw).format.should eq(:json)
    raw.headers["Accept"] = "text/plain"
    Altair::HTTP::Request.new(raw).format.should eq(:text)
  end

  it "prefers the path format suffix over the Accept header" do
    raw = HTTP::Request.new("GET", "/posts.json")
    raw.headers["Accept"] = "text/html"
    request = Altair::HTTP::Request.new(raw)
    request.params.merge_route({"format" => "json"})
    request.format.should eq(:json)
  end

  it "parses a JSON body into the request's json accessor" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.headers["Content-Type"] = "application/json"
    raw.body = %({"title": "Hello", "count": 3})
    request = Altair::HTTP::Request.new(raw)
    request.json.not_nil!["title"].as_s.should eq("Hello")
    request.json.not_nil!["count"].as_i.should eq(3)
  end

  it "returns nil json for non-JSON requests" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.headers["Content-Type"] = "application/x-www-form-urlencoded"
    raw.body = "title=x"
    Altair::HTTP::Request.new(raw).json.should be_nil
  end

  it "exposes scalar JSON body values as params, skipping nested values" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.headers["Content-Type"] = "application/json"
    raw.body = %({"title": "Hello", "count": 3, "nested": {"a": 1}, "tags": ["x"]})
    params = Altair::HTTP::Request.new(raw).params
    params["title"].should eq("Hello")
    params["count"].should eq("3")
    params["nested"]?.should be_nil
    params["tags"]?.should be_nil
  end

  it "lets query params win over JSON body values" do
    raw = HTTP::Request.new("POST", "/posts?title=query")
    raw.headers["Content-Type"] = "application/json"
    raw.body = %({"title": "body"})
    Altair::HTTP::Request.new(raw).params["title"].should eq("query")
  end

  it "ignores a malformed JSON body without raising" do
    raw = HTTP::Request.new("POST", "/posts")
    raw.headers["Content-Type"] = "application/json"
    raw.body = "{not json"
    request = Altair::HTTP::Request.new(raw)
    request.json.should be_nil
    request.params["nope"]?.should be_nil
  end

  it "merges route params recorded before the bag is first built" do
    request = Altair::HTTP::Request.new(HTTP::Request.new("GET", "/posts/5"))
    request.route_params = {"id" => "5"}
    request.params["id"].should eq("5")
  end

  it "merges route params recorded after the bag was already built" do
    request = Altair::HTTP::Request.new(HTTP::Request.new("POST", "/posts/5?from=api"))
    request.params["from"].should eq("api")
    request.route_params = {"id" => "5"}
    request.params["id"].should eq("5")
  end

  it "keeps the unified bag lazy until it is first accessed" do
    raw = HTTP::Request.new("GET", "/posts?q=altair")
    request = Altair::HTTP::Request.new(raw)
    request.path.should eq("/posts")
    request.params["q"].should eq("altair")
    request.params["q"].should eq("altair")
  end

  describe "multipart form data" do
    it "reads scalar fields and uploaded files from the body" do
      boundary = "AaB03x"
      body = "--#{boundary}\r\n" \
             "Content-Disposition: form-data; name=\"title\"\r\n" \
             "\r\n" \
             "Hello World\r\n" \
             "--#{boundary}\r\n" \
             "Content-Disposition: form-data; name=\"avatar\"; filename=\"portrait.png\"\r\n" \
             "Content-Type: image/png\r\n" \
             "\r\n" \
             "\x89PNG\r\n" \
             "--#{boundary}--\r\n"
      raw = HTTP::Request.new("POST", "/posts")
      raw.headers["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      raw.body = body
      request = Altair::HTTP::Request.new(raw)

      request.params["title"].should eq("Hello World")
      upload = request.params.upload("avatar").not_nil!
      upload.original_filename.should eq("portrait.png")
      upload.content_type.should eq("image/png")
      upload.content.should eq("\x89PNG")
    end

    it "exposes an empty uploads bag for non-multipart requests" do
      raw = HTTP::Request.new("GET", "/")
      Altair::HTTP::Request.new(raw).uploads.should be_empty
    end

    it "reads a form-urlencoded upload-like field as a regular string" do
      raw = HTTP::Request.new("POST", "/posts")
      raw.headers["Content-Type"] = "application/x-www-form-urlencoded"
      raw.body = "title=Hello"
      request = Altair::HTTP::Request.new(raw)
      request.params["title"].should eq("Hello")
      request.uploads.should be_empty
    end

    it "survives a missing boundary" do
      raw = HTTP::Request.new("POST", "/posts")
      raw.headers["Content-Type"] = "multipart/form-data"
      raw.body = "anything"
      request = Altair::HTTP::Request.new(raw)
      request.params.to_h.should be_empty
      request.uploads.should be_empty
    end

    it "survives a malformed multipart body" do
      raw = HTTP::Request.new("POST", "/posts")
      raw.headers["Content-Type"] = "multipart/form-data; boundary=abc"
      raw.body = "--abc-- not really multipart"
      request = Altair::HTTP::Request.new(raw)
      request.uploads.should be_empty
    end

    it "exposes name, size, read and save on an uploaded file" do
      boundary = "AaB03x"
      body = "--#{boundary}\r\n" \
             "Content-Disposition: form-data; name=\"avatar\"; filename=\"portrait.png\"\r\n" \
             "Content-Type: image/png\r\n" \
             "\r\n" \
             "\x89PNG\r\n" \
             "--#{boundary}--\r\n"
      raw = HTTP::Request.new("POST", "/posts")
      raw.headers["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      raw.body = body
      request = Altair::HTTP::Request.new(raw)
      upload = request.uploads["avatar"]

      upload.name.should eq("avatar")
      upload.size.should eq(4)
      upload.read.should eq("\x89PNG")

      target = Path.new(Dir.tempdir, "altair_upload_#{Random.rand(100_000)}.png")
      begin
        upload.save(target).should eq(target)
        File.read(target).should eq("\x89PNG")
      ensure
        File.delete(target) if File.exists?(target)
      end
    end
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

  it "escapes the filename in the Content-Disposition header" do
    dir = File.tempname("altair-send-file")
    Dir.mkdir(dir)
    path = File.join(dir, %(we"ird name.txt))
    File.write(path, "x")
    io = IO::Memory.new
    raw = HTTP::Server::Response.new(io)
    response = Altair::HTTP::Response.new(raw)
    response.send_file(Path.new(path), inline: false)
    response.headers["Content-Disposition"].should eq("attachment; filename=\"we\\\"ird name.txt\"")
  ensure
    raw.try(&.close)
    File.delete(path) if path
    Dir.delete(dir) if dir && Dir.exists?(dir)
  end

  it "answers head with a status and no body" do
    io = IO::Memory.new
    raw = HTTP::Server::Response.new(io)
    response = Altair::HTTP::Response.new(raw)
    response.head(::HTTP::Status::NO_CONTENT)
    response.status.should eq(::HTTP::Status::NO_CONTENT)
    raw.close
    io.to_s.should end_with("\r\n\r\n")
  end

  it "ignores body writes after head" do
    io = IO::Memory.new
    raw = HTTP::Server::Response.new(io)
    response = Altair::HTTP::Response.new(raw)
    response.head(::HTTP::Status::CREATED)
    response.html("<p>late</p>")
    raw.close
    io.to_s.should end_with("\r\n\r\n")
  end
end
