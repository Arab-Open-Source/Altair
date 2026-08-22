# Altair — the batteries-included web framework for Crystal.
#
# Specs for the `Altair::Test` helpers: boot an application on an
# ephemeral port with readiness polling, issue requests through the
# helpers, and restore the shared application instance afterwards —
# the integration-suite boilerplate, shipped as public API.
require "../spec_helper"

class BootProbeApp < Altair::Application
  routes do
    get "/ping", to: BootProbeController.ping
    post "/echo", to: BootProbeController.echo
  end
end

class BootProbeController < Altair::Controller
  def ping : Nil
    render text: "pong"
  end

  def echo : Nil
    render text: "echo:#{params["word"]?}"
  end
end

describe Altair::Test do
  it "boots an app on an ephemeral port and answers requests" do
    Altair::Test.boot(BootProbeApp) do |port|
      response = Altair::Test.get(port, "/ping")
      response.status_code.should eq(200)
      response.body.should eq("pong")

      echoed = Altair::Test.post(port, "/echo", form: "word=hi")
      echoed.status_code.should eq(200)
      echoed.body.should eq("echo:hi")
    end
  end

  it "restores the shared application instance after the block" do
    before = Altair.application_instance
    Altair::Test.boot(BootProbeApp) do
      Altair.application_instance.should_not eq(before)
    end
    Altair.application_instance.should eq(before)
  end

  it "frees the port so a second boot succeeds" do
    Altair::Test.boot(BootProbeApp) do |first_port|
      Altair::Test.get(first_port, "/ping").status_code.should eq(200)
    end
    Altair::Test.boot(BootProbeApp) do |second_port|
      Altair::Test.get(second_port, "/ping").status_code.should eq(200)
    end
  end
end
