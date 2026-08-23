# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Redis::Error` and its subclasses — the
# exception hierarchy raised by the Redis client. Every error carries a
# descriptive message so callers can distinguish protocol failures from
# connection failures from server-side rejections.
require "uri"
require "socket"
require "openssl"
require "digest/sha256"

module Altair
  module Redis
    # Base class for every Redis client error.
    class Error < ::Exception
    end

    # The TCP connection dropped or was never established.
    class ConnectionLost < Error
    end

    # The server replied with a RESP error (prefixed by `-`). These are
    # runtime rejections — unknown commands, wrong types, out-of-range
    # indices — and should be handled, not retried blindly.
    class CommandError < Error
    end

    # AUTH failed: wrong password or ACL restrictions.
    class AuthenticationError < Error
    end

    # The server closed the connection while we were reading a reply.
    class ProtocolError < Error
    end

    # WATCH detected a modification before EXEC — optimistic locking.
    class WatchAborted < Error
    end

    # A bulk string or array exceeded the configured maximum size.
    class ReplyTooLarge < Error
    end
  end
end
