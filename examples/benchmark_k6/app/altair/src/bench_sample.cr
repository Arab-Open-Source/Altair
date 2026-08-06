# Altair benchmark — per-second observability sampler (diagnosis only).
#
# Compiled only with `--define bench_sample` (see scripts/diagnose.sh). The
# normal benchmark binary is bit-for-bit unaffected: without the flag this
# file defines nothing and application.cr registers no middleware.
#
# The sampler records, once per second:
#   - request count, average and maximum processing time
#   - Boehm GC heap curves (GC.stats) and collection counter (LibGC.gc_no)
#   - the GC world-stop windows (count + total ms) measured from collection
#     events, so a tail spike can be matched against the pause that caused it
#   - the shared DB pool's open/idle/in-flight connections
#
# Output: one CSV line per second (header written at start), to the path in
# BENCH_SAMPLE. The PG side of the same diagnosis is captured by
# scripts/sample_pg.sh, and the two CSV timelines are correlated by unix time.
{% if flag?(:bench_sample) %}
  require "gc"

  module BenchSample
    class_getter path : String = ENV["BENCH_SAMPLE"]? || "/tmp/bench_altair_sample.csv"

    # Per-request counters. Class variables (not `class_getter = ...`, which
    # would build a fresh `Atomic` on every call) so every reader/writer
    # touches the same instance.
    @@count = Atomic(Int64).new(0)
    @@sum_ns = Atomic(Int64).new(0)
    @@max_ns = Atomic(Int64).new(0)
    @@errs = Atomic(Int64).new(0)

    # The writer fiber, started once (idempotent).
    @@started = Atomic(Bool).new(false)

    # GC world-stop meter. `PRE_STOP_WORLD`/`POST_START_WORLD` bracket the
    # window in which request fibers cannot run; the callbacks run on the
    # collector thread while the world is paused, so the meter is strictly
    # lock- and allocation-free (plain atomic traffic only).
    @@stw_started = Atomic(UInt64).new(0_u64)
    @@stw_ns = Atomic(Int64).new(0)
    @@stw_events = Atomic(Int64).new(0)
    @@meter_installed = Atomic(Bool).new(false)

    def self.start : Nil
      return if @@started.swap(true)
      install_pause_meter
      io = File.open(path, "w")
      io.puts "unix_sec,reqs,avg_ms,max_ms,errs,gc_heap_mb,gc_live_mb,gc_total_mb,gc_alloc_mb,gc_collections,gc_stw_events,gc_stw_ms,pool_open,pool_idle,pool_inflight,pool_max"
      io.flush
      spawn do
        loop do
          sleep 1.second
          begin
            write_line(io)
            io.flush
          rescue ex
            # Sampling must never take the app down; a write failure just
            # stops the CSV after the last successful line.
            break
          end
        end
      end
    end

    # The callback installed before ours, chained so existing hooks survive.
    # A class variable instead of a captured local: C callbacks cannot close
    # over locals, but module-level state is fine.
    @@previous_event_cb : LibGC::OnCollectionEventProc? = nil

    # Installs the collection-event callback.
    private def self.install_pause_meter : Nil
      return if @@meter_installed.swap(true)
      @@previous_event_cb = LibGC.get_on_collection_event
      LibGC.set_on_collection_event(->(event : LibGC::EventType) {
        case event
        when LibGC::EventType::PRE_STOP_WORLD
          @@stw_started.set(Crystal::System::Time.ticks)
        when LibGC::EventType::POST_START_WORLD
          started = @@stw_started.swap(0_u64)
          unless started == 0_u64
            @@stw_ns.add((Crystal::System::Time.ticks - started).to_i64)
            @@stw_events.add(1)
          end
        end
        @@previous_event_cb.try(&.call(event))
      })
    end

    def self.record(error : Bool, elapsed_ns : Int64) : Nil
      @@count.add(1)
      @@sum_ns.add(elapsed_ns)
      loop do
        current = @@max_ns.get
        break if current >= elapsed_ns
        break if @@max_ns.compare_and_set(current, elapsed_ns)
      end
      @@errs.add(1) if error
    end

    private def self.write_line(io : IO) : Nil
      reqs = @@count.swap(0_i64)
      sum = @@sum_ns.swap(0_i64)
      max = take_max
      errors = @@errs.swap(0_i64)

      stats = GC.stats
      collections = LibGC.gc_no
      live = stats.heap_size - stats.free_bytes
      stw_ns = @@stw_ns.swap(0_i64)
      stw_events = @@stw_events.swap(0_i64)

      pool = Altair::Record.connection.pool_stats

      avg_ms = reqs > 0 ? (sum / reqs) / 1_000_000.0 : 0.0
      io << Time.utc.to_unix << ","
      io << reqs << "," << avg_ms.round(3) << "," << (max / 1_000_000.0) << "," << errors << ","
      io << (stats.heap_size / 1_048_576.0) << "," << (live / 1_048_576.0) << ","
      io << (stats.total_bytes / 1_048_576.0) << "," << (stats.bytes_since_gc / 1_048_576.0) << ","
      io << collections << "," << stw_events << "," << (stw_ns / 1_000_000.0) << ","
      if pool
        io << pool.open_connections << "," << pool.idle_connections << ","
        io << pool.in_flight_connections << "," << pool.max_connections
      else
        io << "0,0,0,0"
      end
      io << '\n'
    end

    # Reads the running maximum and resets it for the next interval. The CAS
    # loop only loses a maximum written between the read and the reset, which
    # is acceptable for a one-second histogram bucket.
    private def self.take_max : Int64
      loop do
        current = @@max_ns.get
        return current if @@max_ns.compare_and_set(current, 0_i64)
      end
    end
  end

  # Per-request middleware: records the processing time of the whole chain.
  # With only `bench_sample` (no `bench_timing`) it is an inert pass-through,
  # so GC/pool sampling can be measured in isolation from request timing.
  class BenchMetrics < Altair::Middleware
    def initialize(app : Altair::Application)
      super
      {% if flag?(:bench_timing) %}
        BenchSample.start
      {% end %}
    end

    def call(request : Altair::HTTP::Request, response : Altair::HTTP::Response, chain : Proc(Nil)) : Nil
      {% if flag?(:bench_timing) %}
        started = Time.instant
        begin
          chain.call
          BenchSample.record(!response.status.success?, (Time.instant - started).nanoseconds)
        rescue ex
          BenchSample.record(true, (Time.instant - started).nanoseconds)
          raise ex
        end
      {% else %}
        chain.call
      {% end %}
    end
  end
{% end %}
