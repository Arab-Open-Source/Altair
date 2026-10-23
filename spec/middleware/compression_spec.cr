# Specs for the Compression middleware: negotiation, passthrough when
# disabled or unaccepted, and gzip round-trip over real HTTP.
require "../spec_helper"

private class CompPages < Altair::Controller
  def hello : Nil
    response.text("hello compression " * 20)
  end
end

private class PlainApp < Altair::Application
  routes do
    get "/hello", to: CompPages.hello
  end
end

describe Altair::Middleware::Compression do
  it "compresses gzip-capable responses when enabled" do
    Altair::Test.boot(PlainApp, configure: ->(app : PlainApp) {
      app.config.compression.enabled = true
    }) do |port|
      response = Altair::Test.get(port, "/hello", headers: ::HTTP::Headers{"Accept-Encoding" => "gzip"})
      response.headers["Content-Encoding"].should eq("gzip")
      response.headers["Vary"].should eq("Accept-Encoding")
      body = Compress::Gzip::Reader.new(IO::Memory.new(response.body)).gets_to_end
      body.should start_with("hello compression")
    end
  end

  it "serves plain bytes when the client sends no Accept-Encoding" do
    Altair::Test.boot(PlainApp, configure: ->(app : PlainApp) {
      app.config.compression.enabled = true
    }) do |port|
      response = Altair::Test.get(port, "/hello")
      response.headers["Content-Encoding"]?.should be_nil
      response.body.should start_with("hello compression")
    end
  end

  it "is a pass-through while disabled" do
    Altair::Test.boot(PlainApp) do |port|
      response = Altair::Test.get(port, "/hello", headers: ::HTTP::Headers{"Accept-Encoding" => "gzip"})
      response.headers["Content-Encoding"]?.should be_nil
      response.body.should start_with("hello compression")
    end
  end

  it "skips compression when the client refuses gzip" do
    Altair::Test.boot(PlainApp, configure: ->(app : PlainApp) {
      app.config.compression.enabled = true
    }) do |port|
      response = Altair::Test.get(port, "/hello", headers: ::HTTP::Headers{"Accept-Encoding" => "identity"})
      response.headers["Content-Encoding"]?.should be_nil
      response.body.should start_with("hello compression")
    end
  end

  it "honors a configured level" do
    Altair::Test.boot(PlainApp, configure: ->(app : PlainApp) {
      app.config.compression.enabled = true
      app.config.compression.level = 1
    }) do |port|
      response = Altair::Test.get(port, "/hello", headers: ::HTTP::Headers{"Accept-Encoding" => "gzip"})
      response.headers["Content-Encoding"].should eq("gzip")
    end
  end
end
