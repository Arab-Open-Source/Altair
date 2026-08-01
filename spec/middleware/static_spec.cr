# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Middleware::Static`: files under `public/` are served
# with their content type, and every other request — missing files,
# non-GET methods and paths that try to escape the public directory — falls
# through to the chain.
require "../spec_helper"
require "file_utils"

private def with_public_dir(&)
  original_root = SpecApp.instance.root
  root = Path.new(Dir.tempdir) / "altair-static-spec-#{Random::Secure.hex(6)}"
  public_dir = root / "public"
  css_dir = public_dir / "css"
  Dir.mkdir_p(css_dir)
  File.write(css_dir / "app.css", "body { color: red; }")
  File.write(public_dir / "data.txt", "plain data")

  SpecApp.instance.root = root

  yield public_dir
ensure
  SpecApp.instance.root = original_root.as(Path)
  FileUtils.rm_rf(root) if root
end

private def static_middleware : Altair::Middleware::Static
  Altair::Middleware::Static.new(SpecApp.instance)
end

private def static_request(method : String = "GET", path : String = "/") : Altair::HTTP::Request
  Altair::HTTP::Request.new(HTTP::Request.new(method, path))
end

private def static_response : Altair::HTTP::Response
  Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
end

describe Altair::Middleware::Static do
  it "serves an existing file with its content type" do
    with_public_dir do
      response = static_response
      passed = false
      static_middleware.call(static_request(path: "/css/app.css"), response, -> { passed = true })
      response.status.should eq(::HTTP::Status::OK)
      response.headers["Content-Type"].should start_with("text/css")
      passed.should be_false
    end
  end

  it "serves nested files with a fallback content type" do
    with_public_dir do
      response = static_response
      static_middleware.call(static_request(path: "/data.txt"), response, -> { })
      response.headers["Content-Type"].should start_with("text/plain")
    end
  end

  it "passes missing files through to the chain" do
    with_public_dir do
      passed = false
      static_middleware.call(static_request(path: "/missing.css"), static_response, -> { passed = true })
      passed.should be_true
    end
  end

  it "passes non-GET methods through to the chain" do
    with_public_dir do
      passed = false
      static_middleware.call(static_request("POST", "/css/app.css"), static_response, -> { passed = true })
      passed.should be_true
    end
  end

  it "rejects parent-segment traversal attempts" do
    with_public_dir do |public_dir|
      passed = false
      static_middleware.call(static_request(path: "/../secret.txt"), static_response, -> { passed = true })
      passed.should be_true
      passed = false
      static_middleware.call(static_request(path: "/css/../../data.txt"), static_response, -> { passed = true })
      passed.should be_true
      File.exists?(public_dir / "data.txt").should be_true
    end
  end
end
