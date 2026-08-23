# Altair — the batteries-included web framework for Crystal.
#
# Specs for background jobs: typed params round-trip through the payload
# codec, the enqueue family (immediate, delayed, absolute), test-mode
# collection and draining, queue claiming exclusivity under concurrent
# fibers, retry backoff inside the attempt budget, and worker execution
# end to end against the real database.
require "./../spec_helper"
require "./../record/model_fixtures_spec"

class PayloadBox
  include JSON::Serializable
  property note : String

  def initialize(@note : String)
  end
end

class GreetingJob < Altair::Jobs::Job
  params user_id : Int64, slug : String, priority : Int32,
    ratio : Float64, urgent : Bool, meta : PayloadBox

  class_getter performed : Array(Int64) = [] of Int64

  def perform : Nil
    GreetingJob.performed << user_id
  end
end

class FailingJob < Altair::Jobs::Job
  params label : String

  class_getter attempts : Array(String) = [] of String

  def perform : Nil
    FailingJob.attempts << label
    raise "deliberate failure: #{label}"
  end

  def self.max_attempts : Int32
    3
  end
end

class QuietJob < Altair::Jobs::Job
  params n : Int32

  def perform : Nil
  end
end

describe Altair::Jobs do
  before_each do
    conn = Altair::Record.connection
    conn.exec("DROP TABLE IF EXISTS altair_jobs")
    Altair::Jobs::Queue.test_mode = false
    Altair::Jobs::Queue.clear_enqueued!
    GreetingJob.performed.clear
    FailingJob.attempts.clear
  end

  describe "params" do
    it "round-trips every declared type through the payload" do
      job = GreetingJob.new(7_i64, "hello", 3, 0.5, true, PayloadBox.new("meta"))
      decoded = GreetingJob.from_payload(job.payload_json)

      decoded.user_id.should eq(7_i64)
      decoded.slug.should eq("hello")
      decoded.priority.should eq(3)
      decoded.ratio.should eq(0.5)
      decoded.urgent.should be_true
      decoded.meta.note.should eq("meta")
    end

    it "decodes small JSON numbers into Int64 parameters" do
      raw = <<-JSON
        {"user_id": 9, "slug": "s", "priority": 1, "ratio": 1.5, "urgent": false,
         "meta": {"note": "n"}}
        JSON
      decoded = GreetingJob.from_payload(raw)
      decoded.user_id.should eq(9_i64)
      decoded.user_id.should be_a(Int64)
    end
  end

  describe "test mode" do
    it "collects enqueues in memory and drains them synchronously" do
      Altair::Jobs::Queue.test_mode = true
      GreetingJob.enqueue(user_id: 1_i64, slug: "a", priority: 1, ratio: 1.0, urgent: false, meta: PayloadBox.new("m"))
      QuietJob.enqueue(n: 2)
      GreetingJob.enqueue_in(1.hour, user_id: 2_i64, slug: "b", priority: 1, ratio: 1.0, urgent: false, meta: PayloadBox.new("m"))

      Altair::Jobs::Queue.enqueued.size.should eq(3)
      GreetingJob.performed.empty?.should be_true

      worker = Altair::Jobs::Worker.new
      Altair::Jobs::Queue.enqueued.sort_by(&.run_at).each do |call|
        worker.execute(Altair::Jobs::ClaimedJob.new(-1_i64, call.job_name, call.payload))
      end

      GreetingJob.performed.should eq([1_i64, 2_i64])
    end
  end

  describe "queue persistence" do
    it "enqueues into the lazy table with a due timestamp" do
      id = QuietJob.enqueue(n: 5)
      id.should be > 0

      row = Altair::Record.connection.query_one(
        "SELECT job_class, status FROM altair_jobs WHERE id = #{id}"
      ) { |rs| {job_class: rs.read(String), status: rs.read(String)} }
      row[:job_class].should contain("QuietJob")
      row[:status].should eq("pending")
    end

    it "claims only due jobs from the requested queues" do
      QuietJob.enqueue_in(1.hour, n: 1)
      QuietJob.enqueue(n: 2)

      claimed = Altair::Jobs::Queue.claim(["default"])
      claimed.should_not be_nil
      claimed.not_nil!.job_class.should contain("QuietJob")

      second = Altair::Jobs::Queue.claim(["default"])
      second.should be_nil
    end

    it "never hands the same row to two workers" do
      20.times { |i| QuietJob.enqueue(n: i) }
      claimed_ids = Channel(Int64).new(20)
      done = Channel(Nil).new(8)
      workers = 8

      workers.times do
        spawn do
          while claimed = Altair::Jobs::Queue.claim(["default"])
            claimed_ids.send(claimed.id)
          end
          done.send(nil)
        end
      end

      ids = Array.new(20) { claimed_ids.receive }
      workers.times { done.receive }

      ids.size.should eq(20)
      ids.uniq.size.should eq(20)
    end

    it "reports status counts" do
      QuietJob.enqueue(n: 1)
      QuietJob.enqueue(n: 2)
      claimed = Altair::Jobs::Queue.claim(["default"]).not_nil!
      Altair::Jobs::Queue.complete(claimed.id)

      stats = Altair::Jobs::Queue.stats
      stats["pending"].should eq(1)
      stats["done"].should eq(1)
    end
  end

  describe "worker execution" do
    it "runs a claimed job and marks it done" do
      GreetingJob.enqueue(user_id: 42_i64, slug: "s", priority: 1, ratio: 1.0, urgent: true, meta: PayloadBox.new("m"))
      worker = Altair::Jobs::Worker.new

      worker.work_one.should be_true
      GreetingJob.performed.should eq([42_i64])

      stats = Altair::Jobs::Queue.stats
      stats["done"]?.should eq(1)
      stats["pending"]?.should be_nil
    end

    it "returns false when nothing is claimable" do
      Altair::Jobs::Worker.new.work_one.should be_false
    end

    it "retries failures with backoff until the budget is spent" do
      FailingJob.enqueue(label: "boom")
      worker = Altair::Jobs::Worker.new
      clock = Time.utc

      3.times do |attempt|
        worker.work_one.should be_true
        break if attempt == 2

        retry_at = Altair::Record.connection.query_one(
          "SELECT run_at FROM altair_jobs WHERE status = 'pending'"
        ) { |rs| Time.parse(rs.read(String), "%FT%T.%9NZ", location: Time::Location::UTC) }
        (retry_at - clock).total_seconds.should be >= 1
        # Force the retry due immediately for the next claim.
        Altair::Record.connection.exec(
          "UPDATE altair_jobs SET run_at = ? WHERE status = 'pending'",
          clock.to_s("%FT%T.%9NZ")
        )
      end

      FailingJob.attempts.size.should eq(3)
      stats = Altair::Jobs::Queue.stats
      stats["failed"]?.should eq(1)
      stats["pending"]?.should be_nil
    end

    it "records the error message on the failed row" do
      FailingJob.enqueue(label: "final")
      worker = Altair::Jobs::Worker.new
      3.times do
        worker.work_one
        # Pull each scheduled retry due so the next claim succeeds.
        Altair::Record.connection.exec(
          "UPDATE altair_jobs SET run_at = ? WHERE status = 'pending'",
          (Time.utc - 1.second).to_s("%FT%T.%9NZ")
        )
      end

      last_error = Altair::Record.connection.query_one(
        "SELECT last_error FROM altair_jobs WHERE status = 'failed'"
      ) { |rs| rs.read(String?) }
      last_error.not_nil!.should contain("deliberate failure")
    end

    it "parks unknown job classes as failed without crashing" do
      id = Altair::Jobs::Queue.enqueue("GhostJob", "{}", "default")
      worker = Altair::Jobs::Worker.new
      worker.work_one.should be_true

      status = Altair::Record.connection.query_one(
        "SELECT status FROM altair_jobs WHERE id = #{id}"
      ) { |rs| rs.read(String) }
      status.should eq("failed")
    end
  end

  describe "retry backoff" do
    it "doubles per attempt up to the cap" do
      r = Altair::Jobs::Retry
      r.backoff(1).should eq(2.seconds)
      r.backoff(2).should eq(4.seconds)
      r.backoff(3).should eq(8.seconds)
      r.backoff(20).should eq(5.minutes)
    end
  end

  describe "regression: applications that define no jobs" do
    it "fails to compile a no-op: Altair::Jobs::Job.from_payload is dispatchable as Job.class" do
      expect_raises(Altair::Error, /no.*params/) do
        Altair::Jobs::Job.from_payload("{}")
      end
    end
  end
end
