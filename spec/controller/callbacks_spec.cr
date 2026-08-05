# Altair — the batteries-included web framework for Crystal.
#
# End-to-end specs for controller callbacks: `before_action` /
# `after_action` declared in the controller class body, run by the router's
# dispatch wrapper around the action. Covers the halt behaviour (a before
# callback that writes a response stops the action), `only:` / `except:`
# filters, `skip_before_action` and after-action side effects.
require "../spec_helper"

class CallbacksApp < Altair::Application
  routes do
    get "/admin", to: "callbacks#admin"
    get "/protected", to: "callbacks#protected"
    get "/public", to: "callbacks#public_page"
    get "/sequential", to: "callbacks#sequential"
    get "/counted", to: "callbacks#counted"
    get "/inherited", to: "inherited_guarded#guarded"
    get "/sibling", to: "skips_guard#open"
    get "/skips-open", to: "inherited_guarded#open"
  end
end

class CallbacksController < Altair::Controller
  before_action :require_admin
  skip_before_action :require_admin, only: [:public_page]
  before_action :set_marker, only: [:sequential, :counted]
  after_action :append_counter, only: [:counted]

  def admin : Nil
    render text: "admin"
  end

  def protected : Nil
    render text: "protected"
  end

  def public_page : Nil
    render text: "public"
  end

  def sequential : Nil
    render text: "marker=#{@marker}"
  end

  def counted : Nil
    render text: "count=1"
  end

  def require_admin : Nil
    return if @request.headers["X-Admin"]? == "yes"
    @response.status = ::HTTP::Status::UNAUTHORIZED
    @response.text("unauthorized")
  end

  def set_marker : Nil
    @marker = "seen"
  end

  def append_counter : Nil
    @response.headers["X-After"] = "ran"
  end
end

class GuardedController < Altair::Controller
  def require_guard : Nil
    return if @request.headers["X-Guard"]? == "yes"
    @response.status = ::HTTP::Status::FORBIDDEN
    @response.text("forbidden")
  end

  def guarded : Nil
    render text: "guarded"
  end
end

class InheritedGuardedController < GuardedController
  before_action :require_guard

  def open : Nil
    render text: "open"
  end
end

class SkipsGuardController < GuardedController
  before_action :require_guard
  skip_before_action :require_guard, only: [:open]

  def open : Nil
    render text: "open"
  end
end

private def with_callbacks_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  app = CallbacksApp.instance
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

describe "controller callbacks" do
  it "halts the action when a before callback writes a response" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/admin")
      response.status_code.should eq(401)
      response.body.should eq("unauthorized")
    end
  end

  it "runs the action when the before callback passes" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/admin", headers: HTTP::Headers{"X-Admin" => "yes"})
      response.status_code.should eq(200)
      response.body.should eq("admin")
    end
  end

  it "skips the before callback for the listed action" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/public")
      response.status_code.should eq(200)
      response.body.should eq("public")
    end
  end

  it "runs an only-filtered callback before its actions" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/sequential", headers: HTTP::Headers{"X-Admin" => "yes"})
      response.status_code.should eq(200)
      response.body.should eq("marker=seen")
    end
  end

  it "runs after callbacks after the action" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/counted", headers: HTTP::Headers{"X-Admin" => "yes"})
      response.status_code.should eq(200)
      response.body.should eq("count=1")
      response.headers["X-After"]?.should eq("ran")
    end
  end

  it "does not run after callbacks when a before callback halted" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/protected")
      response.status_code.should eq(401)
      response.headers["X-After"]?.should be_nil
    end
  end

  it "runs a before callback inherited from a base controller" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/inherited")
      response.status_code.should eq(403)
      response.body.should eq("forbidden")
    end
  end

  it "lets a subclass skip an ancestor's callback" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/sibling")
      response.status_code.should eq(200)
      response.body.should eq("open")
    end
  end

  it "does not let a sibling's skip affect its own callbacks" do
    with_callbacks_server do |port|
      response = HTTP::Client.get("http://127.0.0.1:#{port}/skips-open")
      response.status_code.should eq(403)
    end
  end
end
