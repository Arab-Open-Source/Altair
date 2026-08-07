# Altair — the battery-included web framework for Crystal.
#
# Specs for `Altair::Auth::JWT`: a self-contained HS256 JSON Web Token
# implementation. A signed token round-trips its claims, a tampered or
# expired token is rejected, and a wrong secret never verifies.
require "../spec_helper"
require "json"

private def secret : String
  "a-jwt-testing-secret"
end

describe Altair::Auth::JWT do
  it "signs and verifies a token" do
    token = Altair::Auth::JWT.sign({"sub" => "7", "role" => "admin"}, secret)
    claims = Altair::Auth::JWT.verify(token, secret).not_nil!
    claims["sub"].should eq("7")
    claims["role"].should eq("admin")
  end

  it "rejects a tampered payload" do
    token = Altair::Auth::JWT.sign({"sub" => "7"}, secret)
    parts = token.split(".")
    payload = Base64.urlsafe_encode({"sub" => "8"}.to_json, padding: false)
    tampered = "#{parts[0]}.#{payload}.#{parts[2]}"
    Altair::Auth::JWT.verify(tampered, secret).should be_nil
  end

  it "rejects a token signed with a different secret" do
    token = Altair::Auth::JWT.sign({"sub" => "7"}, secret)
    Altair::Auth::JWT.verify(token, "a-different-secret").should be_nil
  end

  it "rejects an empty or malformed token" do
    Altair::Auth::JWT.verify("", secret).should be_nil
    Altair::Auth::JWT.verify("a.b", secret).should be_nil
    Altair::Auth::JWT.verify("not-a-jwt", secret).should be_nil
  end

  it "rejects an expired token" do
    token = Altair::Auth::JWT.sign({"sub" => "7"}, secret, expires_in: 1.millisecond)
    sleep 5.milliseconds
    Altair::Auth::JWT.verify(token, secret).should be_nil
  end

  it "honors the exp claim written at issue time" do
    token = Altair::Auth::JWT.sign({"sub" => "7", "exp" => (Time.utc - 1.hour).to_unix.to_s}, secret)
    Altair::Auth::JWT.verify(token, secret).should be_nil
  end
end
