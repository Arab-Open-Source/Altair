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

  it "delivers raw messages to subscribers without wrapping them" do
    mem = IO::Memory.new
    socket = ::HTTP::WebSocket.new(mem)
    begin
      Altair::Cable.subscribe("raw-ch", socket)
      Altair::Cable.broadcast("raw-ch", "live-update")
    ensure
      Altair::Cable.unsubscribe("raw-ch", socket)
    end
    read_text_frame(mem).should eq("live-update")
  end

  it "delivers JSON envelopes when broadcast carries an event and data" do
    mem = IO::Memory.new
    socket = ::HTTP::WebSocket.new(mem)
    begin
      Altair::Cable.subscribe("envelope-ch", socket)
      Altair::Cable.broadcast("envelope-ch", "created", JSON.parse(%({"id": 42})))
    ensure
      Altair::Cable.unsubscribe("envelope-ch", socket)
    end
    parsed = JSON.parse(read_text_frame(mem))
    parsed["channel"].as_s.should eq("envelope-ch")
    parsed["event"].as_s.should eq("created")
    parsed["data"]["id"].as_i.should eq(42)
  end

  it "treats a broadcast with no subscribers as a no-op" do
    Altair::Cable.broadcast("empty-ch", "nobody-listens")
    Altair::Cable.subscriber_count("empty-ch").should eq(0)
  end
end

private def read_text_frame(io : IO::Memory) : String
  io.rewind
  head = io.read_bytes(UInt16, ::IO::ByteFormat::NetworkEndian)
  ((head >> 8) & 0xf).should eq(1)
  io.read_string(head & 0x7f)
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
