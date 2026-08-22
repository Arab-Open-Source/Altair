# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Test::Client`: the cookie jar carries the server's
# session across requests, redirects follow like a browser, and expired
# cookies (a destroyed session) leave the jar — so auth flows read as
# intent in application specs.
require "../spec_helper"

class ClientProbeController < Altair::Controller
  def login : Nil
    sign_in(params["user_id"])
    redirect_to("/me")
  end

  def logout : Nil
    session.destroy
    render text: "bye"
  end

  def me : Nil
    render text: "user:#{current_user_id || "anonymous"}"
  end

  def hop : Nil
    redirect_to("/me")
  end

  def target : Nil
    render text: "landed"
  end

  def echo_json : Nil
    render json: {"got" => params["word"]?}
  end
end

class ClientProbeApp < Altair::Application
  routes do
    post "/login", to: ClientProbeController.login
    get "/logout", to: ClientProbeController.logout
    get "/me", to: ClientProbeController.me
    get "/hop", to: ClientProbeController.hop
    get "/target", to: ClientProbeController.target
    post "/echo_json", to: ClientProbeController.echo_json
  end
end

private def with_client_app(& : Int32 -> Nil)
  Altair::Test.boot(ClientProbeApp, configure: ->(app : ClientProbeApp) {
    app.config.secret_key_base = "client-spec-secret"
  }) do |port|
    yield port
  end
end

describe Altair::Test::Client do
  it "starts with an empty jar and sends no Cookie header" do
    with_client_app do |port|
      client = Altair::Test::Client.new(port)
      client.cookies.empty?.should be_true

      response = client.get("/me")
      response.status_code.should eq(200)
      response.body.should eq("user:anonymous")
      client.cookies.empty?.should be_true
    end
  end

  it "keeps the session between requests through the jar" do
    with_client_app do |port|
      client = Altair::Test::Client.new(port)
      login = client.post("/login", form: "user_id=42")
      login.status_code.should eq(302)

      me = client.get("/me")
      me.status_code.should eq(200)
      me.body.should eq("user:42")
      client.cookies.empty?.should be_false
    end
  end

  it "isolates two clients from each other's sessions" do
    with_client_app do |port|
      signed_in = Altair::Test::Client.new(port)
      signed_in.post("/login", form: "user_id=7")

      fresh = Altair::Test::Client.new(port)
      fresh.get("/me").body.should eq("user:anonymous")
    end
  end

  it "drops the cookie when the session is destroyed" do
    with_client_app do |port|
      client = Altair::Test::Client.new(port)
      client.post("/login", form: "user_id=42")
      client.get("/me").body.should eq("user:42")

      client.get("/logout")
      client.get("/me").body.should eq("user:anonymous")
    end
  end

  it "does not follow redirects by default" do
    with_client_app do |port|
      client = Altair::Test::Client.new(port)
      response = client.get("/hop")
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/me")
    end
  end

  it "follows redirects downgrading to GET when asked" do
    with_client_app do |port|
      client = Altair::Test::Client.new(port, follow_redirects: true)
      response = client.get("/hop")
      response.status_code.should eq(200)
      response.body.should eq("user:anonymous")
    end
  end

  it "carries cookies along a followed redirect chain" do
    with_client_app do |port|
      client = Altair::Test::Client.new(port, follow_redirects: true)
      login = client.post("/login", form: "user_id=11")
      login.status_code.should eq(200)
      login.body.should eq("user:11")
    end
  end

  it "supports JSON posts" do
    with_client_app do |port|
      client = Altair::Test::Client.new(port)
      response = client.post_json("/echo_json", %({"word": "hi"}))
      response.status_code.should eq(200)
      response.body.should eq(%({"got":"hi"}))
    end
  end
end
