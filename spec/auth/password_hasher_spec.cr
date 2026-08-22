# Altair — the batteries-included web framework for Crystal.
#
# Specs for `Altair::Auth::PasswordHasher`: round-trip hashing, wrong
# passwords, per-hash salts, malformed digests, iteration staleness and the
# constant-time guarantee's observable behavior (verification never depends
# on digest length beyond parseability).
require "../spec_helper"

describe Altair::Auth::PasswordHasher do
  it "round-trips a password" do
    digest = Altair::Auth::PasswordHasher.hash("correct horse battery staple")
    Altair::Auth::PasswordHasher.verify("correct horse battery staple", digest).should be_true
  end

  it "rejects a wrong password" do
    digest = Altair::Auth::PasswordHasher.hash("hunter2")
    Altair::Auth::PasswordHasher.verify("hunter3", digest).should be_false
  end

  it "rejects an empty candidate without touching the digest" do
    digest = Altair::Auth::PasswordHasher.hash("x")
    Altair::Auth::PasswordHasher.verify("", digest).should be_false
  end

  it "salts every hash differently" do
    first = Altair::Auth::PasswordHasher.hash("same")
    second = Altair::Auth::PasswordHasher.hash("same")
    first.should_not eq(second)
    Altair::Auth::PasswordHasher.verify("same", first).should be_true
    Altair::Auth::PasswordHasher.verify("same", second).should be_true
  end

  it "embeds the format tag and iteration count" do
    digest = Altair::Auth::PasswordHasher.hash("x")
    fields = digest.split('$')
    fields.size.should eq(4)
    fields[0].should eq(Altair::Auth::PasswordHasher::FORMAT)
    fields[1].should eq(Altair::Auth::PasswordHasher::DEFAULT_ITERATIONS.to_s)
  end

  it "honors a custom iteration count" do
    digest = Altair::Auth::PasswordHasher.hash("x", iterations: 1000)
    digest.split('$')[1].should eq("1000")
    Altair::Auth::PasswordHasher.verify("x", digest).should be_true
  end

  it "refuses non-positive iteration counts" do
    expect_raises(ArgumentError) do
      Altair::Auth::PasswordHasher.hash("x", iterations: 0)
    end
  end

  it "verifies false on malformed digests instead of raising" do
    ["", "garbage", "md5$1$aa$bb",
     "#{Altair::Auth::PasswordHasher::FORMAT}$abc$aaa$bbb",
     "#{Altair::Auth::PasswordHasher::FORMAT}$1000$not-base64!!!$also-bad!!!"].each do |stored|
      Altair::Auth::PasswordHasher.verify("x", stored).should be_false
      Altair::Auth::PasswordHasher.stale?(stored).should be_true
    end
  end

  it "flags stale digests hashed at an older iteration count" do
    fresh = Altair::Auth::PasswordHasher.hash("x")
    Altair::Auth::PasswordHasher.stale?(fresh).should be_false

    older = Altair::Auth::PasswordHasher.hash("x", iterations: 1000)
    Altair::Auth::PasswordHasher.stale?(older).should be_true
    Altair::Auth::PasswordHasher.stale?(older, current_iterations: 1000).should be_false
  end

  it "produces fixed-width keys regardless of password length" do
    short = Altair::Auth::PasswordHasher.hash("a")
    long = Altair::Auth::PasswordHasher.hash("a" * 500)
    short.split('$')[3].size.should eq(long.split('$')[3].size)
  end
end
