# Altair — the batteries-included web framework for Crystal.
#
# Unit specs for the `Altair::Session` object: the hash-like data API,
# lazy load from the store, and the persistence contract — a session that
# is only read sends no new cookie, while writes, deletes and clears do.
require "../spec_helper"
require "http/server"

private def session_request(cookie : String? = nil) : Altair::HTTP::Request
  headers = HTTP::Headers.new
  headers["Cookie"] = "_altair_session=#{cookie}" if cookie
  Altair::HTTP::Request.new(HTTP::Request.new("GET", "/", headers))
end

private def session_response : Altair::HTTP::Response
  Altair::HTTP::Response.new(HTTP::Server::Response.new(IO::Memory.new))
end

private def seed!(store : Altair::Session::Store, data : Hash(String, String)) : String
  response = session_response
  store.save(response, data)
  response.cookies["_altair_session"].not_nil!.value
end

private def cookie_of(response : Altair::HTTP::Response) : String
  response.cookies["_altair_session"].not_nil!.value
end

describe Altair::Session do
  secret = "unit-session-secret"
  store = Altair::Session::SignedCookieStore.new(secret)

  it "starts empty for a bare request" do
    session = Altair::Session.new(session_request, session_response, store)
    session.empty?.should be_true
    session["user_id"]?.should be_nil
  end

  it "reads and writes data like a hash" do
    session = Altair::Session.new(session_request, session_response, store)
    session["user_id"] = "42"
    session["user_id"].should eq("42")
    session.key?("user_id").should be_true
    session.empty?.should be_false
  end

  it "persists a fresh session into the response cookie" do
    response = session_response
    session = Altair::Session.new(session_request, response, store)
    session["user_id"] = "42"
    store.load(session_request(cookie_of(response))).should eq({"user_id" => "42"})
  end

  it "loads an existing session from the request cookie" do
    session = Altair::Session.new(session_request(seed!(store, {"user_id" => "42"})), session_response, store)
    session["user_id"].should eq("42")
  end

  it "does not rewrite the cookie for a read-only request" do
    response = session_response
    session = Altair::Session.new(session_request(seed!(store, {"user_id" => "42"})), response, store)
    session["user_id"].should eq("42")
    response.cookies["_altair_session"]?.should be_nil
  end

  it "drops a key through delete" do
    response = session_response
    session = Altair::Session.new(session_request(seed!(store, {"user_id" => "42", "name" => "Hana"})), response, store)
    session.delete("name").should eq("Hana")
    session.key?("name").should be_false
    store.load(session_request(cookie_of(response))).should eq({"user_id" => "42"})
  end

  it "leaves a silent delete alone" do
    response = session_response
    session = Altair::Session.new(session_request(seed!(store, {"user_id" => "42"})), response, store)
    session.delete("missing").should be_nil
    response.cookies["_altair_session"]?.should be_nil
  end

  it "clears all data through clear" do
    response = session_response
    session = Altair::Session.new(session_request(seed!(store, {"user_id" => "42"})), response, store)
    session.clear
    session.empty?.should be_true
    store.load(session_request(cookie_of(response))).should eq({} of String => String)
  end

  it "expires the cookie through destroy" do
    response = session_response
    session = Altair::Session.new(session_request(seed!(store, {"user_id" => "42"})), response, store)
    session.destroy
    response.cookies["_altair_session"].not_nil!.expired?.should be_true
  end

  it "hides reserved underscore keys from to_h" do
    session = Altair::Session.new(session_request(seed!(store, {"user_id" => "42", "_flash" => "{}"})), session_response, store)
    session.to_h.should eq({"user_id" => "42"})
  end
end
