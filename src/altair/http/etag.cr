# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::ETag`, the shared validator helpers used
# by the ConditionalGet middleware and the controller `fresh?`/`stale?`
# helpers: SHA-256 fingerprint generation and weak If-None-Match comparison.
require "digest"

module Altair
  module HTTP
    # HTTP conditional-request validators.
    module ETag
      # Returns a strong ETag header value — a quoted SHA-256 of *body*.
      def self.generate(body : String | Bytes) : String
        digest = Digest::SHA256.hexdigest(body)
        %("#{digest}")
      end

      # Whether *if_none_match* matches *etag* under the weak comparison the
      # spec assigns to If-None-Match: the `W/` strength marker is ignored,
      # list entries are compared individually, and `*` matches anything.
      def self.matches?(if_none_match : String?, etag : String) : Bool
        return false unless if_none_match
        return true if if_none_match.strip == "*"
        opaque = etag.lchop("W/")
        if_none_match.split(',').any? { |candidate| candidate.strip.lchop("W/") == opaque }
      end
    end
  end
end
