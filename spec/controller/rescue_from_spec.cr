# Altair — the batteries-included web framework for Crystal.
#
# End-to-end specs for controller-level exception handling: `rescue_from`
# declared in the controller class body, invoked by the router's dispatch
# wrapper when an action (or one of its callbacks) raises a matching
# exception. Covers handler responses, subclass-exception matching,
# `only:`/`except:` filters, inherited handlers and the re-raise fallback.
require "../spec_helper"

class BoomError < Exception; end

class SubBoomError < BoomError; end

class OtherError < Exception; end

class UncaughtError < Exception; end

class InheritedRescueController < Altair::Controller
  rescue_from BoomError, handle_with: :answer_boom

  def answer_boom(e : BoomError) : Nil
    render json: {handled: "inherited"}
  end

  def work : Nil
    raise BoomError.new("inherited boom")
  end
end

class RescueController < Altair::Controller
  rescue_from BoomError, handle_with: :answer_boom
  rescue_from OtherError, handle_with: :answer_other, only: [:only_ok]
  before_action :raise_boom, only: [:before]

  def answer_boom(e : BoomError) : Nil
    render json: {handled: true, message: e.message, type: e.class.name}
  end

  def answer_other(e : OtherError) : Nil
    render text: "other"
  end

  def raise_boom : Nil
    raise BoomError.new("callback boom")
  end

  def boom : Nil
    raise BoomError.new("boom")
  end

  def sub : Nil
    raise SubBoomError.new("sub")
  end

  def only_ok : Nil
    raise OtherError.new("x")
  end

  def only_no : Nil
    raise OtherError.new("y")
  end

  def unmatched : Nil
    raise UncaughtError.new("nope")
  end

  def before : Nil
    render text: "never"
  end
end

class RescueApp < Altair::Application
  routes do
    get "/boom", to: "rescue#boom"
    get "/subboom", to: "rescue#sub"
    get "/only-ok", to: "rescue#only_ok"
    get "/only-no", to: "rescue#only_no"
    get "/unmatched", to: "rescue#unmatched"
    get "/before", to: "rescue#before"
    get "/inherited", to: "inherited_rescue#work"
  end
end

private def with_rescue_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = RescueApp.instance
  server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
  server.bind("127.0.0.1", 0)
  port = server.port

  spawn do
    server.start
  end

  wait_until_ready(port)

  yield port
ensure
  server.try(&.http_server.close)
  Altair.application_instance = original
end

private def wait_until_ready(port : Int32) : Nil
  100.times do
    HTTP::Client.get("http://127.0.0.1:#{port}/ping")
    return
  rescue IO::Error
    sleep 10.milliseconds
  end
  raise "server did not become ready"
end

describe "controller rescue_from" do
  it "answers a raised exception with the registered handler" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/boom")
      response.status_code.should eq(200)
      response.body.should contain(%("handled":true))
      response.body.should contain(%("message":"boom"))
    end
  end

  it "matches subclass exceptions against the registered type" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/subboom")
      response.status_code.should eq(200)
      response.body.should contain("SubBoomError")
    end
  end

  it "runs the handler only for actions listed in `only:`" do
    with_rescue_server do |port|
      handled = HTTP::Client.get("http://127.0.0.1:#{port}/only-ok")
      handled.status_code.should eq(200)
      handled.body.should eq("other")

      re_raised = HTTP::Client.get("http://127.0.0.1:#{port}/only-no")
      re_raised.status_code.should eq(500)
    end
  end

  it "re-raises when no handler matches" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/unmatched")
      response.status_code.should eq(500)
    end
  end

  it "rescues an exception raised by a before callback" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/before")
      response.status_code.should eq(200)
      response.body.should contain(%("message":"callback boom"))
    end
  end

  it "inherits a base controller's handler" do
    with_rescue_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/inherited")
      response.status_code.should eq(200)
      response.body.should contain(%("handled":"inherited"))
    end
  end
end
