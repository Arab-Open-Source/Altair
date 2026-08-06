# Specs for `Altair::CLI::Update`, the `altair update` command.

require "../spec_helper"
require "digest/sha256"
require "http/server"

module Altair::CLI
  describe Update do
    describe ".download" do
      it "follows redirects" do
        body = "redirected-body"
        server = ::HTTP::Server.new do |ctx|
          case ctx.request.path
          when "/start"
            ctx.response.status = ::HTTP::Status::FOUND
            ctx.response.headers["Location"] = "/final"
          when "/final"
            ctx.response.print(body)
          end
        end
        with_redirect_server(server) do |port|
          Update.download("http://127.0.0.1:#{port}/start").should eq(body)
        end
      end

      it "caps the redirect chain" do
        server = ::HTTP::Server.new do |ctx|
          ctx.response.status = ::HTTP::Status::FOUND
          ctx.response.headers["Location"] = ctx.request.path
        end
        with_redirect_server(server) do |port|
          expect_raises(Altair::Error, "Too many redirects") do
            Update.download("http://127.0.0.1:#{port}/loop")
          end
        end
      end
    end

    describe ".platform_asset_name" do
      it "returns an asset name for the current platform" do
        name = Update.platform_asset_name
        name.should_not be_nil
        name.should match(/\Aaltair-(linux|macos|windows)-(amd64|arm64)(\.exe)?\z/)
      end
    end

    describe ".expected_digest" do
      it "extracts the digest for a named asset from SHA256SUMS" do
        sums = <<-SUMS
          1111111111111111111111111111111111111111111111111111111111111111  altair-linux-amd64
          2222222222222222222222222222222222222222222222222222222222222222  altair-linux-arm64
          SUMS
        Update.expected_digest(sums, "altair-linux-amd64").should eq("1" * 64)
        Update.expected_digest(sums, "altair-linux-arm64").should eq("2" * 64)
      end

      it "returns nil for an absent asset" do
        Update.expected_digest("a" * 64 + "  altair-linux-amd64\n", "altair-macos-arm64").should be_nil
      end

      it "handles single-space separators" do
        Update.expected_digest("abc123  altair-linux-amd64\n", "altair-linux-amd64").should eq("abc123")
      end
    end

    describe ".compare_versions" do
      it "orders versions numerically" do
        Update.compare_versions("v0.1.2", "v0.1.1").should eq(1)
        Update.compare_versions("v0.1.1", "v0.1.2").should eq(-1)
        Update.compare_versions("v0.1.2", "v0.1.2").should eq(0)
      end

      it "compares across component widths" do
        Update.compare_versions("v0.1.10", "v0.1.9").should eq(1)
        Update.compare_versions("v0.2.0", "v0.1.99").should eq(1)
      end
    end

    describe ".current_executable" do
      it "returns a non-empty path" do
        Update.current_executable.should_not be_nil
        Update.current_executable.try(&.should_not be_empty)
      end
    end
  end
end

private def with_redirect_server(server : ::HTTP::Server, &block : Int32 -> _)
  server.bind_tcp("127.0.0.1", 0)
  port = server.addresses.first.as(Socket::IPAddress).port
  spawn do
    server.listen
  rescue ex
    raise ex
  end
  begin
    block.call(port)
  ensure
    server.close
  end
end
