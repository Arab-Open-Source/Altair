# Altair — the batteries-included web framework for Crystal.
#
# End-to-end specs for the hardening-wave auth helpers: sign-in through the
# session, the `require_login` redirect for unauthenticated guests, the
# `authenticate!` 401 for JSON/API requests, and JWT signing/verification
# over real HTTP.
require "../spec_helper"
require "http/server"

class AuthApp < Altair::Application
  routes do
    get "/login", to: "auth#login"
    post "/login", to: "auth#signin"
    post "/logout", to: "auth#signout"
    get "/private", to: "auth#private"
    get "/api", to: "auth#api"
    post "/token", to: "auth#token"
  end
end

class AuthController < Altair::Controller
  before_action :require_login, only: [:private]
  before_action :authenticate!, only: [:api]

  def login : Nil
    render html: "login form"
  end

  def signin : Nil
    sign_in("7")
    redirect_to "/private"
  end

  def signout : Nil
    sign_out
    redirect_to "/login"
  end

  def private : Nil
    render html: "private page for #{current_user_id}"
  end

  def api : Nil
    render json: {sub: current_user_id}
  end

  def token : Nil
    if id = current_user_id
      secret = Altair.application_instance.not_nil!.config.secret_key_base.not_nil!
      render json: {token: Altair::Auth::JWT.sign({"sub" => id}, secret, expires_in: 1.hour)}
    else
      render json: {error: "no user"}, status: ::HTTP::Status::UNAUTHORIZED
    end
  end
end

private def with_auth_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  begin
    app = AuthApp.instance
    app.config.secret_key_base = "spec-auth-secret"
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

describe "auth helpers" do
  it "redirects unauthenticated guests to the login path" do
    with_auth_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      response = client.get("/private")
      response.status.should eq(::HTTP::Status::FOUND)
      response.headers["Location"]?.should eq("/login")
      client.close
    end
  end

  it "answers 401 for unauthenticated API requests" do
    with_auth_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      response = client.get("/api")
      response.status.should eq(::HTTP::Status::UNAUTHORIZED)
      client.close
    end
  end

  it "signs the user in and serves the private page" do
    with_auth_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      login = client.post("/login")
      cookie = login.headers["Set-Cookie"]?.try(&.split(';').first).to_s
      session = HTTP::Headers{"Cookie" => cookie}

      redirect = client.post("/login", headers: session)
      redirect.status.should eq(::HTTP::Status::FOUND)
      redirect.headers["Location"]?.should eq("/private")

      private_page = client.get("/private", headers: session)
      private_page.body.should eq("private page for 7")
      client.close
    end
  end

  it "issues a signed token for the signed-in user and rejects guests" do
    with_auth_server do |base|
      client = HTTP::Client.new(URI.parse(base))

      guest_token = client.post("/token")
      guest_token.status.should eq(::HTTP::Status::UNAUTHORIZED)

      login = client.post("/login")
      cookie = login.headers["Set-Cookie"]?.try(&.split(';').first).to_s
      session = HTTP::Headers{"Cookie" => cookie}
      client.post("/login", headers: session)

      response = client.post("/token", headers: session)
      response.status.should eq(::HTTP::Status::OK)
      token = JSON.parse(response.body).as_h["token"].as_s
      secret = "spec-auth-secret"
      claims = Altair::Auth::JWT.verify(token, secret).not_nil!
      claims["sub"].should eq("7")
      client.close
    end
  end

  it "signs the user out and serves the guest response again" do
    with_auth_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      login = client.post("/login")
      cookie = login.headers["Set-Cookie"]?.try(&.split(';').first).to_s
      session = HTTP::Headers{"Cookie" => cookie}
      client.post("/login", headers: session)

      logout = client.post("/logout", headers: session)
      guest_session = HTTP::Headers{"Cookie" => logout.headers["Set-Cookie"]?.try(&.split(';').first).to_s}
      private_page = client.get("/private", headers: guest_session)
      private_page.status.should eq(::HTTP::Status::FOUND)
      private_page.headers["Location"]?.should eq("/login")
      client.close
    end
  end
end
