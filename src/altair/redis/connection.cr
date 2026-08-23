# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Redis::Connection`, a single TCP (or TLS)
# connection to a Redis server. It handles AUTH, SELECT, and the raw
# command/reply cycle.
#
# Connections are not thread-safe by themselves — use `Client` (which
# wraps a pool) for concurrent access.
require "uri"
require "socket"
require "openssl"
require "digest/sha256"

module Altair
  module Redis
    class Connection
      getter uri : URI

      @tcp : ::TCPSocket?
      @tls : OpenSSL::SSL::Socket::Client?

      def initialize(@uri : URI, tls : Bool = false, password : String? = nil,
                     database : Int32 = 0, @connect_timeout : Int32 = 5)
        @use_tls = tls || @uri.scheme == "rediss"
        @pass = password || @uri.password
        db = @uri.path.lchop("/").to_i?
        @db = database != 0 ? database : (db || 0)
        connect!
      end

      # Sends a command and reads one reply.
      def send_command(args : Array(String)) : Protocol::Reply
        ensure_connected
        io.write(Protocol.encode(args))
        io.flush
        Protocol.decode(io)
      rescue ex : IO::Error | OpenSSL::SSL::Error
        close!
        raise ConnectionLost.new("connection lost: #{ex.message}")
      end

      # Sends a command without reading a reply.
      def write_only(args : Array(String)) : Nil
        ensure_connected
        io.write(Protocol.encode(args))
        io.flush
      rescue ex : IO::Error | OpenSSL::SSL::Error
        close!
        raise ConnectionLost.new("connection lost: #{ex.message}")
      end

      # Reads one reply from an already-written command (pipelining).
      def read_reply : Protocol::Reply
        ensure_connected
        Protocol.decode(io)
      rescue ex : IO::Error | OpenSSL::SSL::Error
        close!
        raise ConnectionLost.new("connection lost: #{ex.message}")
      end

      def connected? : Bool
        !@tcp.nil? || !@tls.nil?
      end

      # Writes multiple encoded commands without reading replies, then
      # reads `count` replies back. This is the building block for pipelining.
      def send_pipeline(commands : Array(Array(String)), count : Int32) : Array(Protocol::Reply)
        ensure_connected
        io.write(Protocol.encode_batch(commands))
        io.flush
        result = [] of Protocol::Reply
        count.times do
          result << Protocol.decode(io).as(Protocol::Reply)
        end
        result
      rescue ex : IO::Error | OpenSSL::SSL::Error
        close!
        raise ConnectionLost.new("connection lost during pipeline: #{ex.message}")
      end

      def close! : Nil
        @tls.try(&.close)
        @tcp.try(&.close)
        @tcp = nil
        @tls = nil
      end

      def io : ::IO
        @tls || @tcp.not_nil!.as(::IO)
      end

      private def connect! : Nil
        host = @uri.host.not_nil!
        port = @uri.port || 6379
        tcp = ::TCPSocket.new(host, port)
        tcp.tcp_nodelay = true
        tcp.keepalive = true
        tcp.read_timeout = @connect_timeout
        tcp.write_timeout = @connect_timeout

        if @use_tls
          ctx = OpenSSL::SSL::Context::Client.new
          tls_socket = OpenSSL::SSL::Socket::Client.new(tcp, ctx)
          tls_socket.sync_close = false
          @tls = tls_socket
        else
          @tcp = tcp
        end

        if pw = @pass
          handshake(["AUTH", pw])
        end

        if @db > 0
          handshake(["SELECT", @db.to_s])
        end
      end

      private def ensure_connected : Nil
        connect! unless connected?
      end

      private def handshake(args : Array(String)) : Nil
        io.write(Protocol.encode(args))
        io.flush
        reply = Protocol.decode(io)
        case reply
        when String then nil
        else             raise AuthenticationError.new("handshake failed")
        end
      end
    end
  end
end
