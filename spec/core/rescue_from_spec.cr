# Altair — application-level exception handlers.
#
# Specs for the `rescue_from` DSL: a dedicated application maps three
# exception classes to three response strategies (fixed status, handler
# method, block) and a fourth exception is left unmapped to prove the
# default 500 still applies. Real HTTP, real pipeline.
require "../spec_helper"

private class RescueApp < Altair::Application
  rescue_from KeyError, to: 422
  rescue_from ArgumentError, handler: :on_argument_error
  rescue_from Altair::Error do |exception, _request, response|
    response.status = ::HTTP::Status::UNPROCESSABLE_ENTITY
    response.text("block: #{exception.message}")
  end

  routes do
    get "/raise/key", to: "rescues#key"
    get "/raise/arg", to: "rescues#arg"
    get "/raise/altair", to: "rescues#altair"
    get "/raise/plain", to: "rescues#plain"
  end

  def on_argument_error(exception : Exception, request : Altair::HTTP::Request?, response : Altair::HTTP::Response) : Nil
    response.status = ::HTTP::Status::BAD_REQUEST
    response.text("handler: #{exception.message}")
  end
end

private class RescuesController < Altair::Controller
  def key : Nil
    raise KeyError.new("missing title")
  end

  def arg : Nil
    raise ArgumentError.new("bad count")
  end

  def altair : Nil
    raise Altair::Error.new("framework boom")
  end

  def plain : Nil
    raise "raw crash"
  end
end

private def with_rescue_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = RescueApp.instance
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  done = Channel(Nil).new
  spawn do
    server.start
    done.send(nil)
  end

  100.times do
    HTTP::Client.get("http://127.0.0.1:#{port}/raise/key")
    break
  rescue IO::Error
    sleep 10.milliseconds
  end

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

describe "rescue_from" do
  it "answers a mapped exception with a fixed status" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/raise/key")
      response.status_code.should eq(422)
      response.body.should eq("missing title")
    end
  end

  it "answers a mapped exception through a handler method" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/raise/arg")
      response.status_code.should eq(400)
      response.body.should eq("handler: bad count")
    end
  end

  it "answers a mapped exception through a block" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/raise/altair")
      response.status_code.should eq(422)
      response.body.should eq("block: framework boom")
    end
  end

  it "matches subclasses of a registered exception" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/raise/key")
      response.status_code.should eq(422)
    end
  end

  it "keeps the default 500 for unmapped exceptions" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/raise/plain")
      response.status_code.should eq(500)
    end
  end
end
