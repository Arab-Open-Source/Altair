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
    # until it accepts requests, then yields the port. An optional
    # `configure` proc runs on the fresh instance before the server is
    # built — where per-spec settings such as `secret_key_base` belong.
    # When the block returns (or raises) the server closes and the shared
    # application instance is restored to whatever it was before the boot:
    #
    # ```
    # Altair::Test.boot(MyApp) do |port|
    #   Altair::Test.get(port, "/ping").status_code.should eq(200)
    # end
    #
    # Altair::Test.boot(SessionApp, configure: ->(app : SessionApp) {
    #   app.config.secret_key_base = "test-secret"
    # }) do |port|
    #   Altair::Test.post(port, "/login").status_code.should eq(302)
    # end
    # ```
    #
    # Raises `Altair::Error` if the server never becomes ready within
    # `ready_timeout`.
    def self.boot(app_class : A.class, ready_timeout : Time::Span = 2.seconds,
                  configure : Proc(A, Nil)? = nil, & : Int32 -> Nil) : Nil forall A
      original = Altair.application_instance
      Altair.application_instance = nil
      app = app_class.instance
      configure.try(&.call(app))
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

    # Applies every pending migration of the project against the
    # application's configured database and regenerates `db/schema.cr`,
    # returning the number applied. The same engine `bin/altair db:migrate`
    # runs, exposed so application specs can prepare their schema:
    #
    # ```
    # Altair::Test.migrate!(MyApp)
    # ```
    def self.migrate!(app_class : A.class, migrations_dir : Path = Path.new("db/migrations"),
                      schema_path : Path = Path.new("db/schema.cr")) : Int32 forall A
      conn = Altair::Record::Connection.for(app_class.instance)
      runner = Altair::Record::Migrations::Runner.new(conn, migrations_dir, schema_path, conn.adapter)
      count = runner.migrate
      conn.close
      count
    end

    # Runs the block inside a database transaction that is always rolled
    # back — a raise rolls back through the normal error path, and success
    # rolls back explicitly. Nested calls join the outer transaction (their
    # writes persist until the outermost rollback), so wrapping helpers in
    # layers stays safe. Every example starts from the same data:
    #
    # ```
    # Altair::Test.transactional do
    #   Post.create(title: "only this example sees me")
    # end
    # ```
    def self.transactional(&block : Proc(Nil)) : Nil
      nested = Altair::Record.connection.in_transaction?
      Altair::Record.connection.transaction do
        block.call
        raise DB::Rollback.new("Altair::Test.transactional rollback") unless nested
      end
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
