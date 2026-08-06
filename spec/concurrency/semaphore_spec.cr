# Altair — the concurrency primitives.
#
# Specs for `Altair::Concurrency::Semaphore`: initial permit count,
# blocking acquisition, strict FIFO fairness across fibers, and the
# exception-safe `with_permit` wrapper.
require "../spec_helper"

describe Altair::Concurrency::Semaphore do
  it "begins with the configured number of permits" do
    sem = Altair::Concurrency::Semaphore.new(3)
    sem.acquire
    sem.acquire
    sem.acquire
    completed = Channel(Bool).new
    spawn do
      sem.acquire
      completed.send(true)
    end
    select
    when completed.receive
      fail "acquire should have blocked once the permits ran out"
    when timeout(100.milliseconds)
    end
  end

  it "blocks acquire until a permit is released" do
    sem = Altair::Concurrency::Semaphore.new(1)
    sem.acquire
    completed = Channel(Bool).new
    spawn do
      sem.acquire
      completed.send(true)
    end
    Fiber.yield
    select
    when completed.receive
      fail "acquire should have blocked"
    when timeout(100.milliseconds)
    end
    sem.release
    completed.receive.should be_true
  end

  it "hands permits out in FIFO order across waiters" do
    sem = Altair::Concurrency::Semaphore.new(1)
    sem.acquire
    order = Channel(Int32).new
    n = 5
    n.times do |i|
      spawn do
        sem.acquire
        order.send(i)
        sem.release
      end
    end
    Fiber.yield
    sem.release
    received = n.times.map { order.receive }
    received.to_a.should eq([0, 1, 2, 3, 4])
  end

  it "releases the permit when the block raises" do
    completed = Channel(Bool).new
    spawn do
      sem = Altair::Concurrency::Semaphore.new(1)
      expect_raises(Exception) do
        sem.with_permit do
          raise "boom"
        end
      end
      sem.acquire
      completed.send(true)
    end
    select
    when completed.receive
    when timeout(100.milliseconds)
      fail "with_permit should put the permit back after the block raised"
    end
  end

  it "times out acquiring a permit that never becomes available" do
    sem = Altair::Concurrency::Semaphore.new(1)
    sem.acquire
    acquired = Channel(Bool).new
    spawn do
      acquired.send(sem.acquire(40.milliseconds))
    end
    sem.release
    acquired.receive.should be_true
    sem.acquire(timeout: 1.millisecond).should be_false
  end

  it "acquires within a short deadline when a permit is free" do
    sem = Altair::Concurrency::Semaphore.new(1)
    sem.acquire(10.milliseconds).should be_true
  end

  it "raises Concurrency::Timeout past the deadline and leaves the permit intact" do
    sem = Altair::Concurrency::Semaphore.new(1)
    sem.acquire
    expect_raises(Altair::Concurrency::Timeout) do
      sem.with_permit(20.milliseconds) { }
    end
    # The timed-out acquire never took a permit, so releasing the held one
    # makes it available again and the next acquire succeeds.
    sem.release
    sem.acquire(10.milliseconds).should be_true
  end
end
