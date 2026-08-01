# Altair — htmx response-header helpers.
#
# The helpers set htmx response headers on the framework response. Each
# spec builds a probe controller around an in-memory server response and
# asserts the exact header value.
require "../spec_helper"

private class HtmxProbe
  include Altair::Htmx::Headers

  getter response : Altair::HTTP::Response

  def initialize(@response : Altair::HTTP::Response)
  end
end

private def probe : HtmxProbe
  raw = HTTP::Server::Response.new(IO::Memory.new)
  HtmxProbe.new(Altair::HTTP::Response.new(raw))
end

describe Altair::Htmx::Headers do
  it "sets HX-Trigger" do
    p = probe
    p.hx_trigger(:post_created)
    p.response.headers["HX-Trigger"].should eq("post_created")
  end

  it "sets HX-Trigger with multiple events" do
    p = probe
    p.hx_trigger(:a, :b)
    p.response.headers["HX-Trigger"].should eq("a,b")
  end

  it "sets HX-Trigger-After-Settle" do
    p = probe
    p.hx_trigger_after_settle(:list_updated)
    p.response.headers["HX-Trigger-After-Settle"].should eq("list_updated")
  end

  it "sets HX-Trigger-After-Swap" do
    p = probe
    p.hx_trigger_after_swap(:list_updated)
    p.response.headers["HX-Trigger-After-Swap"].should eq("list_updated")
  end

  it "sets HX-Retarget" do
    p = probe
    p.hx_retarget("#sidebar")
    p.response.headers["HX-Retarget"].should eq("#sidebar")
  end

  it "sets HX-Reselect" do
    p = probe
    p.hx_reselect(".task")
    p.response.headers["HX-Reselect"].should eq(".task")
  end

  it "sets HX-Stop-Polling" do
    p = probe
    p.hx_stop_polling
    p.response.headers["HX-Stop-Polling"].should eq("true")
  end

  it "sets HX-Redirect" do
    p = probe
    p.hx_redirect("/tasks")
    p.response.headers["HX-Redirect"].should eq("/tasks")
  end

  it "sets HX-Location" do
    p = probe
    p.hx_location("/tasks/1")
    p.response.headers["HX-Location"].should eq("/tasks/1")
  end

  it "sets HX-Refresh" do
    p = probe
    p.hx_refresh
    p.response.headers["HX-Refresh"].should eq("true")
  end

  it "sets HX-Push-Url" do
    p = probe
    p.hx_push_url("/tasks")
    p.response.headers["HX-Push-Url"].should eq("/tasks")
  end
end
