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

  it "renders a boxed boot banner with the environment and address" do
    app = SpecApp.instance
    server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
    server.bind("127.0.0.1", 0)

    banner = server.banner
    banner.should contain("╭")
    banner.should contain("╰")
    banner.should contain("Altair #{Altair::VERSION} — #{Altair.env} mode")
    banner.should contain("Listening on http://localhost:#{server.port}")
    banner.should contain("#{app.config.name} ·")
    banner.lines.first.ends_with?("╮").should be_true
    banner.lines.last.ends_with?("╯").should be_true
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

  it "resizes the execution context to CRYSTAL_WORKERS on boot" do
    prior_workers = ENV["CRYSTAL_WORKERS"]?
    app = SpecApp.instance
    app.config.parallel_execution = true
    server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
    server.bind("127.0.0.1", 0)
    begin
      ENV["CRYSTAL_WORKERS"] = "4"
      done = Channel(Nil).new
      spawn do
        server.start
        done.send(nil)
      end

      wait_until_ready(server.port)
      Fiber::ExecutionContext.default.capacity.should eq(4)
      server.http_server.close
      done.receive
    ensure
      if prior_workers
        ENV["CRYSTAL_WORKERS"] = prior_workers
      else
        ENV.delete("CRYSTAL_WORKERS")
      end
      app.config.parallel_execution = true
    end
  end

  it "leaves the execution context untouched when parallel execution is disabled" do
    app = SpecApp.instance
    app.config.parallel_execution = false
    server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
    server.bind("127.0.0.1", 0)
    before_capacity = Fiber::ExecutionContext.default.capacity
    begin
      done = Channel(Nil).new
      spawn do
        server.start
        done.send(nil)
      end

      wait_until_ready(server.port)
      Fiber::ExecutionContext.default.capacity.should eq(before_capacity)
      server.http_server.close
      done.receive
    ensure
      app.config.parallel_execution = true
    end
  end
end
