# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::Request`, the framework's request object.
# It wraps the raw `HTTP::Request` from the standard library and exposes a
# stable, framework-owned API: method, path, headers, body and an
# `Altair::HTTP::Params` bag holding query-string parameters merged with
# form-body parameters (and, once the router has matched, route
# parameters). Controllers and views in later phases will only ever see
# this wrapper, never the underlying stdlib object, which keeps the
# framework free to evolve its request model without breaking applications.
module Altair
  module HTTP
    class Request
      # The HTTP method of the request, uppercased (`"GET"`, `"POST"`, ...).
      getter method : String

      # The path component of the request URL, without the query string.
      getter path : String

      # The path component including the query string.
      getter full_path : String

      # The request headers.
      getter headers : ::HTTP::Headers

      # The cookies sent by the client, parsed lazily.
      def cookies : ::HTTP::Cookies
        @request.cookies
      end

      # The peer address the server saw, when the socket reported one —
      # the rate limiter's default client key.
      def remote_address : ::Socket::Address?
        @request.remote_address
      end

      # The request body as a `String`, or `nil` when the request has none.
      getter body : String?

      # The request identifier assigned by the `RequestId` middleware: the
      # client's `X-Request-Id` when present, else a generated UUID. `nil`
      # until the middleware runs, so controller code may rely on it being
      # set.
      property request_id : String? = nil

      @query_done = false
      @query_memo : URI::Params? = nil
      @json_done = false
      @json_memo : JSON::Any? = nil
      @route_params : Hash(String, String)? = nil
      @params_done = false
      @params_memo : Altair::HTTP::Params? = nil
      @multipart_done = false
      @multipart_memo : Hash(String, Altair::HTTP::UploadedFile)? = nil

      # The parsed JSON body, or `nil` when the request has no JSON body.
      # The body is parsed on first access, so a request that never reads its
      # JSON never pays for the parse.
      def json : JSON::Any?
        unless @json_done
          @json_done = true
          @json_memo = parse_json_body
        end
        @json_memo
      end

      # The raw query-string parameters, parsed on first access.
      def query_params : URI::Params
        unless @query_done
          @query_done = true
          @query_memo = @request.query_params
        end
        @query_memo.not_nil!
      end

      # The unified parameter bag: query parameters merged with form-body
      # parameters and, once the router has matched, route parameters. The
      # bag and its sources are built on first access — a request whose
      # handler never reads parameters parses nothing.
      def params : Altair::HTTP::Params
        unless @params_done
          @params_done = true
          @params_memo = Altair::HTTP::Params.new(query_params, form_params, json_params, uploads)
          if route_params = @route_params
            @params_memo.not_nil!.merge_route(route_params)
          end
        end
        @params_memo.not_nil!
      end

      # The uploaded files of a `multipart/form-data` body, parsed on first
      # access. A request without a multipart body yields an empty hash.
      def uploads : Hash(String, Altair::HTTP::UploadedFile)
        unless @multipart_done
          @multipart_done = true
          @multipart_memo = parse_multipart
        end
        @multipart_memo.not_nil!
      end

      # The route that matched this request, assigned by the router just
      # before the route's handler runs; `nil` until then. The debug error
      # pages use it to report which route was handling a failing request.
      property route : Altair::Routing::Route?

      # True when the request was issued by htmx (the `HX-Request` header
      # is present), letting actions answer with a fragment instead of a
      # full page:
      #
      # ```
      # def index : Nil
      #   render :index, layout: !request.hx_request?
      # end
      # ```
      def hx_request? : Bool
        @headers["HX-Request"]? == "true"
      end

      def initialize(@request : ::HTTP::Request, max_body_size : Int64? = nil)
        @method = @request.method.to_s
        @path = @request.uri.path
        @full_path = @request.resource
        @headers = @request.headers
        @body = read_body(@request.body, max_body_size)
        @query_done = false
        @query_memo = nil
        @json_done = false
        @json_memo = nil
        @route_params = nil
        @params_done = false
        @params_memo = nil
        @multipart_done = false
        @multipart_memo = nil
      end

      # Registers the route parameters as the unified bag's highest-precedence
      # source. Called by the router once a route matches. When the bag has
      # already been built (a form-`_method` lookup during routing), the
      # parameters merge in immediately; otherwise they are recorded and
      # merged when the bag is first built, keeping a request whose handler
      # never reads parameters free of the merge.
      def route_params=(route_params : Hash(String, String)) : self
        if @params_done
          @params_memo.not_nil!.merge_route(route_params)
        else
          @route_params = route_params
        end
        self
      end

      # The format the client asked for, as a `Symbol`: the path's format
      # suffix (`/posts.json`) when present, else the `Accept` header, else
      # `:html`.
      def format : Symbol
        case params["format"]?
        when "json"        then :json
        when "text", "txt" then :text
        when "html"        then :html
        else
          accept_format || :html
        end
      end

      # Reads the request body up to `limit` bytes, raising
      # `Altair::HTTP::PayloadTooLarge` when the body exceeds it. A `nil`
      # limit reads the body without any bound. The check applies to
      # chunked requests too — the body is read through a `IO::Sized`
      # wrapper, never trusting the `Content-Length` header.
      private def read_body(io : IO?, limit : Int64?) : String?
        return unless io
        return io.gets_to_end unless limit
        body = IO::Sized.new(io, limit + 1).gets_to_end
        raise Altair::HTTP::PayloadTooLarge.new if body.size > limit
        body
      end

      # Parses the body as form parameters when the request is a
      # `application/x-www-form-urlencoded` submission.
      private def form_params : URI::Params
        return URI::Params.new unless body = @body
        content_type = @headers["Content-Type"]?
        return multipart_scalar_fields if content_type.try(&.starts_with?("multipart/form-data"))
        return URI::Params.new unless content_type.try(&.starts_with?("application/x-www-form-urlencoded"))
        URI::Params.parse(body)
      rescue URI::Error
        URI::Params.new
      end

      # The scalar (non-file) fields of a multipart body — submitted as
      # `multipart/form-data`, a plain text input arrives in its own part.
      private def multipart_scalar_fields : URI::Params
        fields = URI::Params.new
        begin
          parse_parts do |part|
            next if part.filename
            fields[part.name] = part.body.gets_to_end
          end
        rescue ::MIME::Multipart::Error
        end
        fields
      end

      # The uploaded files of a multipart body, keyed by field name. An
      # invalid boundary or malformed body silently yields nothing — an
      # upload that cannot be parsed becomes an empty file bag the same way
      # an unscannable JSON body stays `nil`.
      def parse_multipart : Hash(String, Altair::HTTP::UploadedFile)
        parsed = {} of String => Altair::HTTP::UploadedFile
        return parsed unless @body
        content_type = @headers["Content-Type"]?
        return parsed unless content_type.try(&.starts_with?("multipart/form-data"))
        begin
          parse_parts do |part|
            next unless filename = part.filename
            content = part.body.gets_to_end
            parsed[part.name] = Altair::HTTP::UploadedFile.new(
              part.name,
              filename,
              part.headers["Content-Type"]?,
              content.size.to_i64,
              content
            )
          end
        rescue ::MIME::Multipart::Error
        end
        parsed
      end

      # Parses each part of a `multipart/form-data` body, yielding it to the
      # block. The body buffers the request payload, so the part IO is
      # safe to read inside the block only; parse the content before using
      # it after.
      private def parse_parts(&block : ::HTTP::FormData::Part ->) : Nil
        return unless body = @body
        content_type = @headers["Content-Type"]?
        return unless content_type
        return unless boundary = ::MIME::Multipart.parse_boundary(content_type)
        ::HTTP::FormData.parse(IO::Memory.new(body), boundary, &block)
      end

      # Parses the body as JSON when the request carries an
      # `application/json` content type. A malformed JSON body is ignored,
      # leaving `json` `nil` rather than crashing the request.
      private def parse_json_body : JSON::Any?
        return unless body = @body
        content_type = @headers["Content-Type"]?
        return unless content_type.try(&.starts_with?("application/json"))
        JSON.parse(body)
      rescue JSON::ParseException
        nil
      end

      # The top-level scalar values of the JSON body, stringified so they
      # sit alongside form parameters; nested objects and arrays are left
      # out — use `request.json` for those.
      private def json_params : Hash(String, String)
        return {} of String => String unless payload = json
        object = payload.as_h?
        return {} of String => String unless object
        params = {} of String => String
        object.each do |key, value|
          next if value.as_h? || value.as_a?
          raw = value.raw
          next if raw.nil?
          params[key] = raw.to_s
        end
        params
      end

      # The format implied by the `Accept` header, or `nil` when it names
      # no specific Altair content type.
      private def accept_format : Symbol?
        accept = @headers["Accept"]?
        return unless accept
        if accept.includes?("application/json")
          :json
        elsif accept.includes?("text/plain")
          :text
        end
      end
    end
  end
end
