# Altair — the batteries-included web framework for Crystal.
#
# Unit specs for the session store backends: the signed cookie store
# round-trips data through an HTTP request/response pair, rejects tampered
# cookies and honors the security defaults. Full request-lifecycle coverage
# lives in the controller integration specs.
require "../spec_helper"
require "http/server"

private def build_request(cookie : String? = nil) : Altair::HTTP::Request
  headers = HTTP::Headers.new
  headers["Cookie"] = "_altair_session=#{cookie}" if cookie
  Altair::HTTP::Request.new(HTTP::Request.new("GET", "/", headers))
end

private def build_response : Altair::HTTP::Response
  Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
end

def session_cookie(response : Altair::HTTP::Response) : HTTP::Cookie?
  response.cookies["_altair_session"]?
end

describe Altair::Session::SignedCookieStore do
  secret = "a-secret-for-signing"
  store = Altair::Session::SignedCookieStore.new(secret)

  it "loads an empty session from a bare request" do
    store.load(build_request).should eq({} of String => String)
  end

  it "round-trips data through a cookie" do
    response = build_response
    store.save(response, {"user_id" => "42", "name" => "Hana"})

    next_request = build_request(session_cookie(response).not_nil!.value)
    store.load(next_request).should eq({"user_id" => "42", "name" => "Hana"})
  end

  it "rejects a tampered cookie by returning an empty session" do
    response = build_response
    store.save(response, {"user_id" => "42"})

    cookie = session_cookie(response).not_nil!.value
    payload, _, signature = cookie.rpartition("--")
    tampered = "#{payload}--#{signature[0...-1]}#{signature[-1] == '0' ? '1' : '0'}"
    store.load(build_request(tampered)).should eq({} of String => String)
  end

  it "ignores a malformed cookie value" do
    store.load(build_request("not-a-signed-cookie")).should eq({} of String => String)
  end

  it "writes an HttpOnly, SameSite=Lax, /-path cookie" do
    response = build_response
    store.save(response, {"a" => "b"})

    cookie = session_cookie(response).not_nil!
    cookie.http_only.should be_true
    cookie.samesite.should eq(HTTP::Cookie::SameSite::Lax)
    cookie.path.should eq("/")
  end

  it "exposes the configured secure flag" do
    Altair::Session::SignedCookieStore.new(secret, secure: true).secure?.should be_true
    Altair::Session::SignedCookieStore.new(secret).secure?.should be_false
  end
end
