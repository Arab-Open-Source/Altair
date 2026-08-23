require "../spec_helper"

describe Altair::Cable do
  it "uses a stable default endpoint" do
    Altair::Config.new.cable_path.should eq("/cable")
  end

  it "tracks subscribers and cleans up empty channels" do
    ws_a = ::HTTP::WebSocket.new(::IO::Memory.new)
    ws_b = ::HTTP::WebSocket.new(::IO::Memory.new)
    Altair::Cable.subscriber_count("test-channel").should eq(0)

    Altair::Cable.subscribe("test-channel", ws_a)
    Altair::Cable.subscribe("test-channel", ws_b)
    Altair::Cable.subscriber_count("test-channel").should eq(2)

    Altair::Cable.unsubscribe("test-channel", ws_a)
    Altair::Cable.subscriber_count("test-channel").should eq(1)

    Altair::Cable.unsubscribe("test-channel", ws_b)
    Altair::Cable.subscriber_count("test-channel").should eq(0)
  end

  it "broadcasts to all subscribers on the same channel without error" do
    ws_a = ::HTTP::WebSocket.new(::IO::Memory.new)
    ws_b = ::HTTP::WebSocket.new(::IO::Memory.new)
    other = ::HTTP::WebSocket.new(::IO::Memory.new)
    Altair::Cable.subscribe("broadcast-test", ws_a)
    Altair::Cable.subscribe("broadcast-test", ws_b)
    Altair::Cable.subscribe("other-ch", other)

    Altair::Cable.broadcast("broadcast-test", "hello")
  end

  it "cleans up empty channels after last unsubscribe" do
    ws = ::HTTP::WebSocket.new(::IO::Memory.new)
    Altair::Cable.subscribe("cleanup-ch", ws)
    Altair::Cable.unsubscribe("cleanup-ch", ws)
    Altair::Cable.subscriber_count("cleanup-ch").should eq(0)
  end
end
