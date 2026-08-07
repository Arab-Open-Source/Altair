# Altair — the batteries-included web framework for Crystal.
#
# End-to-end specs for sessions and flash over real HTTP: the login logout
# round trip, `session` and `flash` helpers in actions, and the signed
# cookie surviving between requests while the flash only shows once.
require "../spec_helper"
require "http/server"

class SessionsApp < Altair::Application
  routes do
    get "/login", to: "sessions#login"
    get "/show", to: "sessions#show"
    get "/notice", to: "sessions#notice"
    get "/reset", to: "sessions#reset"
  end
end

class SessionsController < Altair::Controller
  def login : Nil
    session["user_id"] = "7"
    flash["notice"] = "You are signed in"
    render html: "logged in"
  end

  def show : Nil
    render html: session["user_id"]?.to_s
  end

  def notice : Nil
    render html: flash["notice"]?.to_s
  end

  def reset : Nil
    reset_session
    render html: "reset"
  end
end

private def with_sessions_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  begin
    app = SessionsApp.instance
    app.config.secret_key_base = "spec-session-secret"
    app.config.session_expiry = 30.days
    server = Altair::Server.new(app, Altair::Core::RequestHandler.new(app))
    server.bind("127.0.0.1", 0)
    port = server.port

    done = Channel(Nil).new
    spawn { server.http_server.listen; done.send(nil) }
    wait_until_ready(port)

    begin
      yield "http://127.0.0.1:#{port}"
    ensure
      server.http_server.close
      done.receive?
    end
  ensure
    Altair.application_instance = original
  end
end

private def wait_until_ready(port : Int32) : Nil
  50.times do
    TCPSocket.new("127.0.0.1", port).close
    return
  rescue
    sleep 50.milliseconds
  end
  fail "server never came up on port #{port}"
end

describe "sessions and flash" do
  it "persists the session across requests and shows the flash once" do
    with_sessions_server do |base|
      client = HTTP::Client.new(URI.parse(base))

      first = client.get("/login")
      cookie = first.headers["Set-Cookie"]?.try(&.split(';').first).to_s
      session = HTTP::Headers{"Cookie" => cookie}

      notice = client.get("/notice", headers: session)

      first.body.should contain("logged in")
      notice.body.should eq("You are signed in")

      again = client.get("/notice", headers: HTTP::Headers{"Cookie" => notice.headers["Set-Cookie"]?.try(&.split(';').first).to_s})
      again.body.should eq("") # flash shows only once

      show = client.get("/show", headers: session)
      show.body.should eq("7") # session survived the round trip

      client.close
    end
  end

  it "logs the user out by resetting the session" do
    with_sessions_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      client.get("/login")
      client.get("/reset")
      show = client.get("/show")
      show.body.should eq("")
      client.close
    end
  end

  it "sets HttpOnly and SameSite on the session cookie" do
    with_sessions_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      response = client.get("/login")
      set_cookie = response.headers["Set-Cookie"]?
      set_cookie.should be_truthy
      if set_cookie
        set_cookie.should contain("HttpOnly")
        set_cookie.should contain("SameSite=Lax")
        set_cookie.should contain("path=/")
      end
      client.close
    end
  end
end
