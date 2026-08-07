# Altair — the batteries-included web framework for Crystal.
#
# End-to-end specs for CSRF protection: a protected application rejects
# state-changing requests without a matching authenticity token and
# accepts them with one, from the hidden `_csrf` field or the
# `X-CSRF-Token` header; `form_for` and `button_to` embed the field
# automatically; and an unprotected controller answers the same POST
# untouched.
require "../spec_helper"
require "http/server"

class CsrfApp < Altair::Application
  routes do
    get "/form", to: "csrf#form"
    post "/submit", to: "csrf#submit"
    get "/button", to: "csrf#button"
    get "/plain_page", to: "plain_csrf#plain_page"
    post "/plain_submit", to: "plain_csrf#plain_submit"
    post "/skipping_submit", to: "skipping_csrf#skipping_submit"
    post "/public_submit", to: "selective_csrf#public_submit"
    post "/protected_submit", to: "selective_csrf#protected_submit"
  end
end

class CsrfController < Altair::Controller
  protect_from_forgery

  def form : Nil
    io = IO::Memory.new
    form_for(io, "/submit", method: :post) { |form_f| form_f.submit("Save") }
    render html: io.to_s
  end

  def submit : Nil
    render html: "accepted"
  end

  def button : Nil
    render html: button_to("Delete", "/submit", method: :delete)
  end
end

class PlainCsrfController < Altair::Controller
  def plain_page : Nil
    render html: "plain"
  end

  def plain_submit : Nil
    render html: "plain accepted"
  end
end

class SkippingCsrfController < Altair::Controller
  protect_from_forgery
  skip_before_action :verify_authenticity_token

  def skipping_submit : Nil
    render html: "skipped accepted"
  end
end

class SelectiveCsrfController < Altair::Controller
  protect_from_forgery except: [:public_submit]

  def public_submit : Nil
    render html: "public accepted"
  end

  def protected_submit : Nil
    render html: "protected accepted"
  end
end

private def with_csrf_server(&)
  original = Altair.application_instance
  Altair.application_instance = nil
  begin
    app = CsrfApp.instance
    app.config.secret_key_base = "spec-csrf-secret"
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

private def authenticity_token_page(base : String) : Tuple(String, String)
  client = HTTP::Client.new(URI.parse(base))
  page = client.get("/form")
  cookie = page.headers["Set-Cookie"]?.try(&.split(';').first).to_s
  token = page.body.match!(/name="_csrf" value="([^"]+)"/)[1]
  client.close
  {cookie, token}
end

describe "CSRF protection" do
  it "embeds the authenticality token into form_for on a protected controller" do
    with_csrf_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      page = client.get("/form")
      page.body.should contain("name=\"_csrf\"")
      page.body.should contain("<form")
      client.close
    end
  end

  it "embeds the token in button_to on a protected controller" do
    with_csrf_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      page = client.get("/button")
      page.body.should contain("name=\"_csrf\"")
      client.close
    end
  end

  it "rejects a POST without a token" do
    with_csrf_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      response = client.post("/submit", headers: HTTP::Headers{"Cookie" => "some_cookie"})
      response.status.should eq(::HTTP::Status::UNPROCESSABLE_ENTITY)
      client.close
    end
  end

  it "accepts a POST with the hidden _csrf field" do
    with_csrf_server do |base|
      cookie, token = authenticity_token_page(base)
      client = HTTP::Client.new(URI.parse(base))
      response = client.post(
        "/submit",
        headers: HTTP::Headers{"Cookie" => cookie},
        form: "_csrf=#{token}"
      )
      response.status.should eq(::HTTP::Status::OK)
      response.body.should eq("accepted")
      client.close
    end
  end

  it "accepts a POST with the X-CSRF-Token header" do
    with_csrf_server do |base|
      cookie, token = authenticity_token_page(base)
      client = HTTP::Client.new(URI.parse(base))
      response = client.post(
        "/submit",
        headers: HTTP::Headers{"Cookie" => cookie, "X-CSRF-Token" => token}
      )
      response.status.should eq(::HTTP::Status::OK)
      client.close
    end
  end

  it "rejects a POST with a wrong token" do
    with_csrf_server do |base|
      cookie, _ = authenticity_token_page(base)
      client = HTTP::Client.new(URI.parse(base))
      response = client.post(
        "/submit",
        headers: HTTP::Headers{"Cookie" => cookie},
        form: "_csrf=wrong-token"
      )
      response.status.should eq(::HTTP::Status::UNPROCESSABLE_ENTITY)
      client.close
    end
  end

  it "leaves GET and unprotected routes alone" do
    with_csrf_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      client.get("/form")
      response = client.post("/plain_submit")
      response.status.should eq(::HTTP::Status::OK)
      response.body.should eq("plain accepted")
      client.close
    end
  end

  it "honors skip_before_action :verify_authenticity_token" do
    with_csrf_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      response = client.post("/skipping_submit")
      response.status.should eq(::HTTP::Status::OK)
      response.body.should eq("skipped accepted")
      client.close
    end
  end

  it "honors the except: list of protect_from_forgery" do
    with_csrf_server do |base|
      client = HTTP::Client.new(URI.parse(base))
      public_response = client.post("/public_submit")
      public_response.status.should eq(::HTTP::Status::OK)

      protected_response = client.post("/protected_submit")
      protected_response.status.should eq(::HTTP::Status::UNPROCESSABLE_ENTITY)
      client.close
    end
  end
end
