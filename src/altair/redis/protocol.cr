# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Redis::Protocol`, the RESP2 wire-format
# encoder and decoder. Redis speaks a simple line-oriented protocol with
# six reply types, each identified by a single-byte prefix:
#
# | Prefix | Type          | Example                |
# |--------|---------------|------------------------|
# | `+`    | Simple String | `+OK\r\n`              |
# | `-`    | Error         | `-ERR unknown cmd\r\n` |
# | `:`    | Integer       | `:42\r\n`              |
# | `$`    | Bulk String   | `$5\r\nhello\r\n`      |
# | `*`    | Array         | `*2\r\n...`            |
# | `$-1`  | Null Bulk     |                        |
require "uri"
require "socket"
require "openssl"
require "digest/sha256"

module Altair
  module Redis
    module Protocol
      CRLF     = "\r\n"
      MAX_BULK = 512 * 1024 * 1024 # 512 MB — Redis's own default

      # The decoded value of a RESP reply: String for simple/bulk strings,
      # Int64 for integers, Nil for null bulk strings, or an Array for
      # nested replies (used by MULTI/EXEC and pub/sub notifications).
      alias Reply = String? | Int64 | Array(Reply)

      # Encodes an array of command arguments into the RESP wire format.
      # Every argument becomes a bulk string; the array itself is wrapped
      # as a RESP array header.
      #
      # ```
      # Protocol.encode(["SET", "key", "value"])
      # # => "*3\\r\\n$3\\r\\nSET\\r\\n$3\\r\\nkey\\r\\n$5\\r\\nvalue\\r\\n"
      # ```
      def self.encode(args : Array(String)) : Bytes
        io = IO::Memory.new
        io << "*#{args.size}" << CRLF
        args.each do |arg|
          bytes = arg.to_slice
          io << "$#{bytes.size}" << CRLF
          io.write(bytes)
          io << CRLF
        end
        io.to_slice
      end

      # Encodes multiple commands into a single byte buffer for pipelining.
      def self.encode_batch(commands : Array(Array(String))) : Bytes
        io = IO::Memory.new
        commands.each do |args|
          io.write(encode(args))
        end
        io.to_slice
      end

      # Reads one complete RESP reply from `io` and returns it as a
      # `Reply`. Raises `ProtocolError` on malformed input or unexpected
      # EOF.
      def self.decode(io : IO) : Reply
        prefix = read_line(io)
        return if prefix.empty?

        case prefix[0]
        when '+'
          prefix[1..]
        when '-'
          raise CommandError.new(prefix[1..])
        when ':'
          prefix[1..].to_i64
        when '$'
          length = prefix[1..].to_i
          return if length == -1
          raise ReplyTooLarge.new("bulk string of #{length} bytes exceeds #{MAX_BULK}") if length > MAX_BULK
          data = Bytes.new(length)
          io.read_fully(data)
          skip_crlf(io)
          String.new(data)
        when '*'
          count = prefix[1..].to_i
          return if count == -1
          Array(Reply).build(count) do |buffer|
            count.times do |index|
              buffer[index] = decode(io)
            end
            count
          end
        else
          raise ProtocolError.new("unknown RESP type byte '#{prefix[0]}'")
        end
      end

      private def self.read_line(io : IO) : String
        line = io.gets('\n', chomp: false)
        raise ConnectionLost.new("connection closed while reading reply") if line.nil?
        line.chomp(CRLF)
      end

      private def self.skip_crlf(io : IO) : Nil
        cr = io.read_char
        lf = io.read_char
        unless cr == '\r' && lf == '\n'
          raise ProtocolError.new("expected CRLF after bulk string payload")
        end
      end
    end
  end
end
