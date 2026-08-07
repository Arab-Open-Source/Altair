# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Session::Flash`, the one-request message store.
# Values written through `flash` appear on the *next* request and are then
# gone; `flash.now` writes values visible only on the current request. Both
# are read through the same `[]`/`[]?` accessors, which prefer the current
# request's values.
#
# ```
# def create : Nil
#   Post.create(...)
#   flash[:notice] = "Post created"
#   redirect_to posts_path
# end
#
# def index : Nil
#   if post.errors.any?
#     flash.now[:alert] = "Post could not be saved"
#   end
#   render :index
# end
# ```
#
# The flash is stored inside the session under a reserved key, so it rides
# the same signed cookie, survives across requests, and never leaks into
# user-facing session state (`session.to_h` hides it).
module Altair
  class Session
    class Flash
      # A view of a `Flash` that only ever writes to the current request,
      # returned by `Flash#now`.
      class Now
        def initialize(@flash : Flash)
        end

        def []=(key : String, value : String) : String
          @flash.current[key] = value
        end

        def [](key : String) : String
          @flash[key]
        end

        def []?(key : String) : String?
          @flash[key]?
        end
      end

      # The session this flash persists into.
      getter session : Session

      # Values for the current request.
      getter current : Hash(String, String)

      # Values to carry over to the next request.
      getter future : Hash(String, String)

      def initialize(@session : Session)
        stored = @session["_flash"]?
        @current = stored.nil? ? {} of String => String : parse(stored)
        @future = {} of String => String
        @session.delete("_flash")
      end

      # Returns the value for `key`, preferring the current values over the
      # carried-over ones. Raises `KeyError` when neither holds it.
      def [](key : String) : String
        @current[key]? || @future[key]? || raise KeyError.new("Flash has no key #{key.inspect}")
      end

      # Returns the value for `key`, or `nil` when neither the current nor
      # the carried-over values hold it.
      def []?(key : String) : String?
        @current[key]? || @future[key]?
      end

      # Sets `key` for the next request (and the current one too, so an
      # immediate template render can read it).
      def []=(key : String, value : String) : String
        @current[key] = value
        @future[key] = value
        persist
        value
      end

      # The view that writes only to the current request — values set
      # through it never reach the next request.
      def now : Now
        Now.new(self)
      end

      # The existing flash is carried over for one more request, so values
      # set by the previous request are not forgotten after a missing read.
      def keep : self
        @current.each do |key, value|
          @future[key] = value
        end
        persist
        self
      end

      # Discards the flash so it is not persisted for the next request. The
      # current request keeps reading its values.
      def discard : self
        @future.clear
        persist
        self
      end

      # True when there are flash values to display (current or carried).
      def any? : Bool
        !@current.empty? || !@future.empty?
      end

      # Serializes the carried-over values into the session.
      private def persist : Nil
        @session["_flash"] = @future.to_json
      end

      private def parse(raw : String) : Hash(String, String)
        JSON.parse(raw).as_h.each_with_object({} of String => String) do |(key, value), result|
          result[key] = value.as_s
        end
      rescue JSON::ParseException
        {} of String => String
      end
    end
  end
end
