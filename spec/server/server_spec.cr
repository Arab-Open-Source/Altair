# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Server`: booting a real server on an ephemeral port,
# responding over real HTTP, returning 404 for unknown paths and shutting
# down gracefully — including repeated boot/shutdown cycles to prove the
# server lifecycle is leak-free.
require "../spec_helper"

private def wait_until_ready(port : Int32) : Nil
  100.times do
    HTTP::Client.get("http://127.0.0.1:#{port}/")
    return
  rescue IO::Error
    sleep 10.milliseconds
  end
  raise "server did not become ready"
end

describe Altair::Server do
  it "boots, responds and shuts down gracefully" do
    app = SpecApp.instance
    server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
    server.bind("127.0.0.1", 0)
    port = server.port

    done = Channel(Nil).new
    spawn do
      server.start
      done.send(nil)
    end

    wait_until_ready(port)

    response = HTTP::Client.get("http://127.0.0.1:#{port}/")
    response.status_code.should eq(200)
    response.body.should contain("Welcome to SpecApp")
    response.body.should contain(Altair::VERSION)

    missing = HTTP::Client.get("http://127.0.0.1:#{port}/missing")
    missing.status_code.should eq(404)

    server.http_server.close
    done.receive
    server.http_server.closed?.should be_true
  end

  it "survives ten boot/shutdown cycles" do
    app = SpecApp.instance
    handler = Altair::Core::RequestHandler.new(app)

    10.times do
      server = Altair::Server.new(app, handler)
      server.bind("127.0.0.1", 0)
      port = server.port

      done = Channel(Nil).new
      spawn do
        server.start
        done.send(nil)
      end

      wait_until_ready(port)
      HTTP::Client.get("http://127.0.0.1:#{port}/anything").status_code.should eq(404)

      server.http_server.close
      done.receive
      server.http_server.closed?.should be_true
    end
  end
end
