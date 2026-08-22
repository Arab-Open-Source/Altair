# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::Test::Client`, a stateful HTTP client for
# application specs: it keeps the server's cookies in a jar between
# requests, so a login (or any session write) carries into the next
# request without manual header plumbing, and it optionally follows
# redirects the way a browser would.
module Altair
  module Test
    # A cookie-jar HTTP client bound to one booted application port.
    #
    # ```
    # Altair::Test.boot(App) do |port|
    #   client = Altair::Test::Client.new(port)
    #   client.post("/login", form: "user_id=42")
    #   client.get("/me").body.should contain("42")
    # end
    # ```
    class Client
      # The most redirects followed for one request before giving up.
      MAX_REDIRECTS = 5

      # The cookie jar carried between requests.
      getter cookies : ::HTTP::Cookies

      # Whether 3xx responses are followed automatically.
      getter? follow_redirects : Bool

      def initialize(@port : Int32, @follow_redirects : Bool = false)
        @cookies = ::HTTP::Cookies.new
      end

      # Sends GET and returns the final response.
      def get(path : String, headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
        request("GET", path, headers)
      end

      # Sends POST with a urlencoded form body.
      def post(path : String, form : String? = nil, headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
        request("POST", path, headers, form: form)
      end

      # Sends POST with a JSON body.
      def post_json(path : String, body : String, headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
        merged = merge_content_type(headers, "application/json")
        request("POST", path, merged, body: body)
      end

      # Sends PUT with a urlencoded form body.
      def put(path : String, form : String? = nil, headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
        request("PUT", path, headers, form: form)
      end

      # Sends PATCH with a urlencoded form body.
      def patch(path : String, form : String? = nil, headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
        request("PATCH", path, headers, form: form)
      end

      # Sends DELETE.
      def delete(path : String, headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
        request("DELETE", path, headers)
      end

      private def request(method : String, path : String, headers : ::HTTP::Headers?, form : String? = nil, body : String? = nil) : ::HTTP::Client::Response
        response = send(method, path, headers, form, body)
        store_cookies(response)
        return response unless follow_redirects?
        follow(response, method, headers, MAX_REDIRECTS)
      end

      private def send(method : String, path : String, headers : ::HTTP::Headers?, form : String?, body : String?) : ::HTTP::Client::Response
        full = build_headers(headers)
        case method
        when "GET"    then ::HTTP::Client.get(url(path), headers: full)
        when "DELETE" then ::HTTP::Client.delete(url(path), headers: full)
        when "POST"
          if form
            ::HTTP::Client.post(url(path), headers: full, form: form)
          else
            ::HTTP::Client.post(url(path), headers: full, body: body)
          end
        when "PUT"
          if form
            ::HTTP::Client.put(url(path), headers: full, form: form)
          else
            ::HTTP::Client.put(url(path), headers: full, body: body)
          end
        when "PATCH"
          if form
            ::HTTP::Client.patch(url(path), headers: full, form: form)
          else
            ::HTTP::Client.patch(url(path), headers: full, body: body)
          end
        else raise ArgumentError.new("Unsupported method #{method}")
        end
      end

      # Follows a redirect chain: 301/302/303 downgrade to GET (the browser
      # behavior that makes a POST-then-redirect flow land on the page),
      # 307/308 keep the method. Cookies collected on the way are stored,
      # and every hop re-sends the jar.
      private def follow(response : ::HTTP::Client::Response, method : String, headers : ::HTTP::Headers?, remaining : Int32) : ::HTTP::Client::Response
        location = response.headers["Location"]?
        if remaining.zero? || !redirect?(response.status_code) || location.nil?
          return response
        end
        next_method = response.status_code.in?(307, 308) ? method : "GET"
        redirected = send(next_method, location, headers, nil, nil)
        store_cookies(redirected)
        follow(redirected, next_method, headers, remaining - 1)
      end

      private def redirect?(status : Int32) : Bool
        status.in?(301, 302, 303, 307, 308)
      end

      private def store_cookies(response : ::HTTP::Client::Response) : Nil
        response.cookies.each do |cookie|
          if cookie.expired?
            @cookies.delete(cookie.name)
          else
            @cookies.delete(cookie.name)
            @cookies << cookie
          end
        end
      end

      private def build_headers(headers : ::HTTP::Headers?) : ::HTTP::Headers
        full = headers || ::HTTP::Headers.new
        unless @cookies.empty?
          pairs = @cookies.map { |cookie| "#{cookie.name}=#{cookie.value}" }
          existing = full["Cookie"]?
          full["Cookie"] = existing ? "#{existing}; #{pairs.join("; ")}" : pairs.join("; ")
        end
        full
      end

      private def url(path : String) : String
        "http://127.0.0.1:#{@port}#{path}"
      end

      private def merge_content_type(headers : ::HTTP::Headers?, value : String) : ::HTTP::Headers
        merged = headers || ::HTTP::Headers.new
        merged["Content-Type"] = value unless merged.has_key?("Content-Type")
        merged
      end
    end
  end
end
