# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Session`, the framework's session object: a
# hash-like view over the session data persisted by a
# `Altair::Session::Store`. Controllers read `session`, write keys and let
# the value class rewrite the cookie when the session changes.
#
# ```
# def login : Nil
#   session["user_id"] = user.id.to_s
#   flash[:notice] = "Welcome back"
#   redirect_to dashboard_path
# end
# ```
#
# A session is only ever persisted when it changes, so a request that just
# reads session state sends no new cookie.
module Altair
  class Session
    # The store that persists this session, e.g. the signed cookie store.
    getter store : Store
    getter request : HTTP::Request
    getter response : HTTP::Response

    @data : Hash(String, String)?
    @dirty = false

    def initialize(@request : HTTP::Request, @response : HTTP::Response, @store : Store)
    end

    # Returns the value for `key`, raising `KeyError` when absent.
    def [](key : String) : String
      data[key]
    end

    # Returns the value for `key`, or `nil` when absent.
    def []?(key : String) : String?
      data[key]?
    end

    # Sets `key` to `value` and persists the session.
    def []=(key : String, value : String) : String
      data[key] = value
      @dirty = true
      persist
      value
    end

    # Removes `key` and persists the session. Returns the removed value, or
    # `nil` when the key was absent. Silent deletes of absent keys do not
    # trigger a cookie write.
    def delete(key : String) : String?
      removed = data.delete(key)
      if removed
        @dirty = true
        persist
      end
      removed
    end

    # True when `key` is present in the session.
    def key?(key : String) : Bool
      data.has_key?(key)
    end

    # True when the session carries no data.
    def empty? : Bool
      data.empty?
    end

    # Yields each `key => value` pair in the session.
    def each(& : String, String ->) : Nil
      data.each { |key, value| yield key, value }
    end

    # Yields each key in the session.
    def each_key(& : String ->)
      data.each_key { |key| yield key }
    end

    # Clears all session data and persists the change.
    def clear : Nil
      @dirty = true
      @data = {} of String => String
      persist
    end

    # Ends the session: clears the data and asks the store to remove its
    # persisted representation (expiring the cookie).
    def destroy : Nil
      @data = {} of String => String
      @store.destroy(@response)
    end

    # The current data, loaded lazily from the store on first access.
    def data : Hash(String, String)
      @data ||= @store.load(@request)
    end

    # A plain copy of the session data with the framework's reserved keys
    # (the flash) excluded, safe to expose or iterate over.
    def to_h : Hash(String, String)
      data.reject { |key, _| key.starts_with?("_") }
    end

    # Resolves the configured session store for `config`: the custom store
    # when one is assigned, else the default `SignedCookieStore` built from
    # the `secret_key_base` and `session_*` settings. The default store
    # refuses to build without a secret — a signing key is what makes the
    # cookie unforgeable.
    def self.store_for(config : Altair::Config) : Altair::Session::Store
      if custom = config.session_store
        return custom
      end

      secret = config.secret_key_base
      if secret.nil?
        raise Altair::ConfigurationError.new(
          "sessions need a signing secret: set config.secret_key_base " \
          "(or the SECRET_KEY_BASE environment variable) before using `session`"
        )
      end

      secure = if override = config.session_cookie_secure
                 override
               else
                 Altair.env.production?
               end

      SignedCookieStore.new(
        secret,
        cookie_name: config.session_cookie_name,
        max_age: config.session_expiry,
        secure: secure
      )
    end

    # Persists the current data through the store. Only called when the
    # session was modified, so read-only requests negotiate no new cookie.
    private def persist : Nil
      return unless @dirty
      @store.save(@response, data)
    end
  end
end
