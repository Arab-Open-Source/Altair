# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Auth::PasswordHasher`, the password hashing
# used by generated authentication. Passwords run through PBKDF2-HMAC-SHA256
# (via OpenSSL) with a per-password random salt; the stored form is a
# self-describing string —
#
#     pbkdf2-sha256$<iterations>$<salt>$<digest>
#
# — so the iteration count can rise over time without rehashing every row:
# `verify` parses whatever is stored, and `stale?` flags digests hashed at
# an older count so applications can upgrade them on the next login.
require "openssl"
require "base64"
require "crypto/subtle"

module Altair
  module Auth
    # Hashes and verifies passwords for `password_auth` models. Never store
    # a plain password: hash on save, verify on login.
    #
    # ```
    # digest = Altair::Auth::PasswordHasher.hash("correct horse")
    # Altair::Auth::PasswordHasher.verify("correct horse", digest)  # => true
    # Altair::Auth::PasswordHasher.verify("battery staple", digest) # => false
    # ```
    module PasswordHasher
      # The format tag stored as the digest's first field.
      FORMAT = "pbkdf2-sha256"

      # The default PBKDF2 iteration count for new digests.
      DEFAULT_ITERATIONS = 100_000

      # The random salt size in bytes.
      SALT_BYTES = 16

      # The derived key size in bytes.
      KEY_BYTES = 32

      # Hashes `password` into the stored string form. Every call uses a
      # fresh random salt, so two hashes of the same password never match
      # byte-for-byte.
      def self.hash(password : String, iterations : Int32 = DEFAULT_ITERATIONS) : String
        raise ArgumentError.new("iterations must be positive") unless iterations > 0
        salt = Random::Secure.random_bytes(SALT_BYTES)
        digest = OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iterations, OpenSSL::Algorithm::SHA256, KEY_BYTES)
        "#{FORMAT}$#{iterations}$#{Base64.urlsafe_encode(salt, padding: false)}$" \
        "#{Base64.urlsafe_encode(digest, padding: false)}"
      end

      # Whether `password` matches `stored`. Malformed or foreign-format
      # digests verify as `false` rather than raising, so a corrupted row
      # behaves exactly like a wrong password.
      def self.verify(password : String, stored : String) : Bool
        parsed = parse(stored)
        return false unless parsed
        iterations, salt, digest = parsed
        candidate = OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iterations, OpenSSL::Algorithm::SHA256, digest.size)
        Crypto::Subtle.constant_time_compare(candidate, digest)
      end

      # Whether `stored` was hashed with fewer than `current_iterations`
      # iterations — a candidate for transparent rehash on the next
      # successful login. Unparseable digests are reported stale so they
      # get replaced rather than lingering forever.
      def self.stale?(stored : String, current_iterations : Int32 = DEFAULT_ITERATIONS) : Bool
        parsed = parse(stored)
        return true unless parsed
        parsed[0] != current_iterations
      end

      private def self.parse(stored : String) : {Int32, Bytes, Bytes}?
        parts = stored.split('$')
        return unless parts.size == 4 && parts[0] == FORMAT
        iterations = parts[1].to_i?
        return unless iterations && iterations > 0
        begin
          salt = Base64.decode(parts[2])
          digest = Base64.decode(parts[3])
          return unless salt.size >= 8 && digest.size >= 16
          {iterations, salt, digest}
        rescue Base64::Error
          nil
        end
      end
    end
  end
end
