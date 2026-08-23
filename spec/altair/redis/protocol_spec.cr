# Altair — specs for the RESP2 protocol encoder and decoder.
require "../../spec_helper"
require "../../../src/altair/redis/protocol"

private def resp_decode(data : String) : Altair::Redis::Protocol::Reply
  io = IO::Memory.new(data)
  Altair::Redis::Protocol.decode(io)
end

describe Altair::Redis::Protocol do
  describe ".encode" do
    it "encodes a simple command" do
      bytes = Altair::Redis::Protocol.encode(["PING"])
      String.new(bytes).should eq("*1\r\n$4\r\nPING\r\n")
    end

    it "encodes multi-argument commands" do
      bytes = Altair::Redis::Protocol.encode(["SET", "key", "value"])
      String.new(bytes).should eq("*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n")
    end
  end

  describe ".decode" do
    it "decodes a simple string" do
      resp_decode("+OK\r\n").should eq("OK")
    end

    it "decodes an error and raises CommandError" do
      expect_raises(Altair::Redis::CommandError, /unknown/) do
        resp_decode("-ERR unknown command 'foo'\r\n")
      end
    end

    it "decodes an integer" do
      resp_decode(":42\r\n").should eq(42_i64)
    end

    it "decodes a bulk string" do
      resp_decode("$5\r\nhello\r\n").should eq("hello")
    end

    it "decodes a null bulk string as nil" do
      resp_decode("$-1\r\n").should be_nil
    end

    it "decodes an array of mixed types" do
      result = resp_decode("*3\r\n$3\r\nfoo\r\n:42\r\n$-1\r\n").as(Array)
      result.size.should eq(3)
      result[0].should eq("foo")
      result[1].should eq(42_i64)
      result[2].should be_nil
    end
  end
end
