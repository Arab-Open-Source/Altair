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

  it "cleans up empty channels after last unsubscribe" do
    ws = ::HTTP::WebSocket.new(::IO::Memory.new)
    Altair::Cable.subscribe("cleanup-ch", ws)
    Altair::Cable.unsubscribe("cleanup-ch", ws)
    Altair::Cable.subscriber_count("cleanup-ch").should eq(0)
  end

  it "broadcasts JSON envelopes with channel and event" do
    envelope = Altair::Cable::Envelope.new("room:1", "message", JSON.parse(%({"text": "hi"})))
    json = envelope.to_json_string
    parsed = JSON.parse(json)
    parsed["channel"].as_s.should eq("room:1")
    parsed["event"].as_s.should eq("message")
    parsed["data"]["text"].as_s.should eq("hi")
  end
end

describe Altair::Cable::ConnectionContext do
  it "carries the request and channel" do
    request = Altair::HTTP::Request.new(::HTTP::Request.new("GET", "/cable?channel=room:1"))
    ctx = Altair::Cable::ConnectionContext.new(request, "room:1")
    ctx.channel.should eq("room:1")
    ctx.current_user_id.should be_nil
    ctx.current_user_id = "42"
    ctx.current_user_id.should eq("42")
  end
end
