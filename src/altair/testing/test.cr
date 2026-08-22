# Altair — the batteries-included web framework for Crystal.
#
# `Altair::Test` ships the integration-suite boilerplate as public API:
# boot an application class on an ephemeral port, wait until it answers,
# issue requests through small helpers, and restore the shared
# application instance when done — so application specs read as intent
# instead of socket plumbing.
module Altair
  # Test helpers for applications and the framework's own suite.
  module Test
    # The number of readiness probes before `boot` gives up.
    READY_PROBES = 200

    # The pause between readiness probes.
    READY_PAUSE = 10.milliseconds

    # Boots an application on `127.0.0.1` with an ephemeral port, waits
    # until it accepts requests, then yields the port. When the block
    # returns (or raises) the server closes and the shared application
    # instance is restored to whatever it was before the boot:
    #
    # ```
    # Altair::Test.boot(MyApp) do |port|
    #   Altair::Test.get(port, "/ping").status_code.should eq(200)
    # end
    # ```
    #
    # Raises `Altair::Error` if the server never becomes ready within
    # `ready_timeout`.
    def self.boot(app_class : A.class, ready_timeout : Time::Span = 2.seconds,
                  & : Int32 -> Nil) : Nil forall A
      original = Altair.application_instance
      Altair.application_instance = nil
      app = app_class.instance
      server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
      server.bind("127.0.0.1", 0)
      port = server.port
      spawn { server.start }
      wait_until_ready(port, ready_timeout)
      yield port
    ensure
      server.try(&.http_server.close)
      Altair.application_instance = original
    end

    # Sends a GET to the booted app.
    def self.get(port : Int32, path : String, headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
      ::HTTP::Client.get(url(port, path), headers: headers)
    end

    # Sends a POST with a urlencoded form body.
    def self.post(port : Int32, path : String, form : String? = nil,
                  headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
      ::HTTP::Client.post(url(port, path), form: form, headers: headers)
    end

    # Sends a POST with a JSON body.
    def self.post_json(port : Int32, path : String, body : String,
                       headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
      ::HTTP::Client.post(url(port, path), body: body,
        headers: merge_content_type(headers, "application/json"))
    end

    # Sends a PUT with a urlencoded form body.
    def self.put(port : Int32, path : String, form : String? = nil,
                 headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
      ::HTTP::Client.put(url(port, path), form: form, headers: headers)
    end

    # Sends a PATCH with a urlencoded form body.
    def self.patch(port : Int32, path : String, form : String? = nil,
                   headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
      ::HTTP::Client.patch(url(port, path), form: form, headers: headers)
    end

    # Sends a DELETE.
    def self.delete(port : Int32, path : String, headers : ::HTTP::Headers? = nil) : ::HTTP::Client::Response
      ::HTTP::Client.delete(url(port, path), headers: headers)
    end

    # Polls the port until it answers, or raises after `timeout`.
    private def self.wait_until_ready(port : Int32, timeout : Time::Span) : Nil
      deadline = Time.instant + timeout
      READY_PROBES.times do
        socket = TCPSocket.new("127.0.0.1", port)
        socket.close
        return
      rescue IO::Error
        raise Altair::Error.new("Test app never became ready on port #{port}") if Time.instant > deadline
        sleep READY_PAUSE
      end
      raise Altair::Error.new("Test app never became ready on port #{port}")
    end

    private def self.url(port : Int32, path : String) : String
      "http://127.0.0.1:#{port}#{path}"
    end

    private def self.merge_content_type(headers : ::HTTP::Headers?, value : String) : ::HTTP::Headers
      merged = headers || ::HTTP::Headers.new
      merged["Content-Type"] = value unless merged.has_key?("Content-Type")
      merged
    end
  end
end
