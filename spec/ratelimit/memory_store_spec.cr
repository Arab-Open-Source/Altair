# Altair — the rate limiter's store contract.
#
# The same examples run against every Store implementation. All timing is
# injected (`now:`), so the sliding-window math is verified deterministically
# — no sleeps, no flakes. Each example builds a fresh store through the
# factory; counters never leak across examples.
require "../spec_helper"

def run_store_contract(factory : Proc(Altair::RateLimit::Store)) : Nil
  it "allows up to the limit then denies" do
    store = factory.call
    begin
      t = 10_000.0
      5.times do |i|
        hit = store.hit("k", 5, 2.seconds, now: t + i * 0.01)
        hit.allowed.should be_true
      end
      hit = store.hit("k", 5, 2.seconds, now: t + 0.1)
      hit.allowed.should be_false
      hit.remaining.should eq(0)
    ensure
      store.close if store.responds_to?(:close)
    end
  end

  it "reports the remaining budget decreasing" do
    store = factory.call
    begin
      t = 20_000.0
      first = store.hit("r", 3, 1.minute, now: t)
      first.remaining.should eq(2)
      second = store.hit("r", 3, 1.minute, now: t + 1)
      second.remaining.should eq(1)
    ensure
      store.close if store.responds_to?(:close)
    end
  end

  it "weights the previous window instead of hard-cutting at the boundary" do
    # Fill most of a 4-second window in its last quarter; crossing into
    # the next window keeps that budget counted against the caller, so a
    # fresh boundary must not restore the full allowance.
    store = factory.call
    begin
      t = 30_000.0
      period = 4.seconds
      boundary = (t / 4).floor * 4 + 4
      fill_start = boundary - 1.0
      hits_in_old = 10
      hits_in_old.times { |i| store.hit("w", 10, period, now: fill_start + i * 0.05) }
      crossed = store.hit("w", 10, period, now: boundary + 0.1)
      # The previous window still weighs nearly full this early into the
      # new one: 10 * (1 - 0.025) ≈ 9.75 — the crossing hit barely fits,
      # and its weight immediately chokes the next one.
      crossed.allowed.should be_true
      crossed.remaining.should eq(0)

      denied = store.hit("w", 10, period, now: boundary + 0.2)
      denied.allowed.should be_false
    ensure
      store.close if store.responds_to?(:close)
    end
  end

  it "restores the full allowance once both windows age out" do
    store = factory.call
    begin
      t = 40_000.0
      period = 1.second
      3.times { |i| store.hit("age", 3, period, now: t + i * 0.01) }
      denied = store.hit("age", 3, period, now: t + 0.5)
      denied.allowed.should be_false
      fresh = store.hit("age", 3, period, now: t + 2.5)
      fresh.allowed.should be_true
      fresh.remaining.should eq(2)
    ensure
      store.close if store.responds_to?(:close)
    end
  end

  it "reports reset_in seconds until the current window closes" do
    store = factory.call
    begin
      t = 50_000.0
      period = 10.seconds
      hit = store.hit("reset", 1, period, now: t + 3.25)
      hit.reset_in.should be > 0
      hit.reset_in.should be <= 6.76
    ensure
      store.close if store.responds_to?(:close)
    end
  end

  it "keeps keys independent" do
    store = factory.call
    begin
      t = 60_000.0
      2.times { |i| store.hit("a", 2, 1.minute, now: t + i * 0.01) }
      other = store.hit("b", 2, 1.minute, now: t + 0.02)
      other.allowed.should be_true
      other.remaining.should eq(1)
    ensure
      store.close if store.responds_to?(:close)
    end
  end

  it "clears all state" do
    store = factory.call
    begin
      t = 70_000.0
      2.times { |i| store.hit("c", 2, 1.minute, now: t + i * 0.01) }
      store.clear
      hit = store.hit("c", 2, 1.minute, now: t + 0.03)
      hit.allowed.should be_true
      hit.remaining.should eq(1)
    ensure
      store.close if store.responds_to?(:close)
    end
  end
end

describe Altair::RateLimit::MemoryStore do
  run_store_contract(-> { Altair::RateLimit::MemoryStore.new })

  it "evicts dead keys lazily" do
    store = Altair::RateLimit::MemoryStore.new
    begin
      t = 80_000.0
      3.times { |i| store.hit("ghost", 5, 1.second, now: t + i * 0.01) }
      store.size.should eq(1)
      store.hit("ghost", 5, 1.second, now: t + 30.0)
      store.size.should eq(1)
      store.hit("alive", 5, 1.second, now: t + 30.1)
      store.size.should eq(2)
      store.clear
      store.size.should eq(0)
    ensure
      store.close
    end
  end

  it "caps total hits" do
    store = Altair::RateLimit::MemoryStore.new
    allowed = 0
    160.times do
      allowed += 1 if store.hit("race", 50, 1.hour).allowed
    end
    allowed.should eq(50)
    store.hit("race", 50, 1.hour).allowed.should be_false
    store.close
  end
end
