# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Auth::JWT`, a minimal HS256 JSON Web Token
# implementation used for stateless authentication: issue a signed token
# to a client and verify it back without a server-side session. The token
# is the three-part `header.payload.signature` form; claims are ordinary
# JSON, `sub` carries the subject (typically the user id) and an optional
# `exp` bounds the token's life. Tokens are verified in constant time and
# a failed check returns `nil` rather than raising, so callers guard with
# a simple `unless`.
require "json"
require "base64"
require "openssl"
require "openssl/hmac"
require "crypto/subtle"

module Altair
  module Auth
    module JWT
      # The algorithm written into the header. Only HS256 is supported.
      ALG = "HS256"

      # Issues a signed token for `claims`. An `exp` claim present in
      # `claims` is honored as-is; pass `expires_in:` to set the lifetime
      # from now when `claims` carries none.
      #
      # ```
      # token = Altair::Auth::JWT.sign({"sub" => user.id}, secret, expires_in: 1.hour)
      # ```
      def self.sign(claims : Hash(String, String), secret : String, *, expires_in : Time::Span? = nil) : String
        payload = claims.dup
        if expires_in && !payload.has_key?("exp")
          payload["exp"] = (Time.utc + expires_in).to_unix.to_s
        end
        header = encode_segment("{\"alg\":\"#{ALG}\",\"typ\":\"JWT\"}")
        body = encode_segment(payload.to_json)
        signed = "#{header}.#{body}"
        "#{signed}.#{signature(secret, signed)}"
      end

      # Verifies `token` against `secret`, returning the claims hash on
      # success or `nil` when the token is malformed, tampered, signed with
      # another secret or past its `exp`.
      def self.verify(token : String, secret : String) : Hash(String, String)?
        return if token.empty?
        segments = token.split('.')
        return unless segments.size == 3

        signed = "#{segments[0]}.#{segments[1]}"
        expected = signature(secret, signed)
        return unless Crypto::Subtle.constant_time_compare(expected, segments[2])

        claims = decode_segment(segments[1])
        return unless claims

        if exp = claims["exp"]?
          if seconds = exp.to_i64?
            return if Time.utc >= Time.unix(seconds)
          end
        end
        claims
      end

      # The HMAC-SHA256 signature of `data`.
      private def self.signature(secret : String, data : String) : String
        OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, secret, data)
      end

      # Base64url-encodes `value` without padding.
      private def self.encode_segment(value : String) : String
        Base64.urlsafe_encode(value, padding: false)
      end

      # Base64url-decodes `value` and parses it as a JSON object, or `nil`
      # for a malformed segment.
      private def self.decode_segment(value : String) : Hash(String, String)?
        json = JSON.parse(Base64.decode_string(value))
        json.as_h?.try { |object| Hash(String, String).from_json(object.to_json) }
      rescue JSON::ParseException
        nil
      rescue Base64::Error
        nil
      end
    end
  end
end
