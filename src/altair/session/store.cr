# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Session::Store`, the seam session backends plug
# into, and `Altair::Session::SignedCookieStore`, the default backend that
# keeps the session payload in a signed cookie. A later release may add a
# server-side store (for example one backed by Redis or the database)
# behind the same `Store` interface; controllers never see which backend is
# active.
#
# The signed cookie packs the session hash as JSON whose payload is
# HMAC-SHA256 signed with `Config#secret_key_base`, so a client-edited
# cookie fails to verify and the session falls back to empty. The signature
# covers the whole payload, so tampering with any field is caught.
require "openssl"
require "openssl/hmac"
require "crypto/subtle"
require "base64"
require "json"
require "http/cookie"

module Altair
  class Session
    # A session persistence backend. Reads the session for a request and
    # writes it back into the response.
    abstract class Store
      # Loads the session data carried by `request`, or an empty hash when
      # there is none.
      abstract def load(request : Altair::HTTP::Request) : Hash(String, String)

      # Persists `data` into `response` (a cookie, a record in a backing
      # store, ...). Called with the full current hash whenever the session
      # changes; backends replace their representation wholesale.
      abstract def save(response : Altair::HTTP::Response, data : Hash(String, String)) : Nil

      # Clears any state the store kept for the client, such as a persisted
      # cookie, so the session ends.
      abstract def destroy(response : Altair::HTTP::Response) : Nil
    end

    # The default `Store`: the whole session lives inside one signed cookie.
    # Cookie settings follow the framework's security defaults — `HttpOnly`,
    # `SameSite=Lax` and a `/` path — and the expiry follows
    # `Config#session_expiry` (a browser session by default).
    class SignedCookieStore < Store
      # The cookie that carries the session payload. The default name is
      # configurable through `Config#session_cookie_name`.
      getter cookie_name : String

      # The lifetime of the session cookie, or `nil` for a browser-session
      # cookie that expires when the client closes.
      getter max_age : Time::Span?

      # Whether the session cookie carries the `Secure` attribute. On by
      # default in the production environment.
      getter? secure : Bool

      def initialize(@secret : String, @cookie_name : String = "_altair_session", @max_age : Time::Span? = nil, @secure : Bool = false)
      end

      # Loads the session from the signed cookie value. A missing,
      # malformed or tampered cookie yields an empty session rather than an
      # error, so an attacker cannot force a crash by corrupting their own
      # cookie.
      def load(request : Altair::HTTP::Request) : Hash(String, String)
        value = request.cookies[cookie_name]?.try(&.value)
        return {} of String => String unless value

        payload, separator, signature = value.rpartition(SEPARATOR)
        return {} of String => String if separator.empty?

        expected = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, @secret, payload)
        return {} of String => String unless Crypto::Subtle.constant_time_compare(expected, signature)

        decode(payload)
      end

      # Rewrites the session cookie with the current `data`. Only called
      # when the session actually changed, so a request that never touches
      # the session sends no new cookie.
      def save(response : Altair::HTTP::Response, data : Hash(String, String)) : Nil
        payload = encode(data)
        signature = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, @secret, payload)
        response.cookies[cookie_name] = ::HTTP::Cookie.new(
          cookie_name,
          "#{payload}#{SEPARATOR}#{signature}",
          path: "/",
          http_only: true,
          samesite: ::HTTP::Cookie::SameSite::Lax,
          secure: @secure,
          max_age: @max_age
        )
      end

      # Expires the stored session cookie so the browser drops it.
      def destroy(response : Altair::HTTP::Response) : Nil
        cookie = ::HTTP::Cookie.new(cookie_name, "")
        cookie.expire
        response.cookies[cookie_name] = cookie
      end

      # A single name is used for the separator in the signed cookie value.
      private SEPARATOR = "--"

      private def encode(data : Hash(String, String)) : String
        Base64.urlsafe_encode(data.to_json, padding: false)
      end

      private def decode(payload : String) : Hash(String, String)
        json = JSON.parse(Base64.decode_string(payload))
        Hash(String, String).from_json(json.to_json)
      rescue JSON::ParseException
        {} of String => String
      rescue Base64::Error
        {} of String => String
      rescue ArgumentError
        {} of String => String
      end
    end
  end
end
