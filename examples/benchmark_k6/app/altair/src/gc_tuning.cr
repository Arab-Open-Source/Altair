# Altair benchmark — Boehm GC tail tuning.
#
# The read workload settles Boehm onto a high-heap equilibrium (collections
# rare but long), which lands 10-30 ms stop-the-world pauses on in-flight
# requests; see ../read-tail-investigation.md. Two runtime interventions,
# measured there with paired controls:
#
#   BENCH_GC_DIVISOR (default 1) — GC_set_free_space_divisor. The env var of
#   the same name is ignored by this build; the function halves the
#   stop-time budget for ~4 percent throughput.
#
#   BENCH_GC_TRICKLE (default 1) — a maintenance fiber calling
#   GC_collect_a_little every few milliseconds, amortizing collection work
#   into small steps instead of letting the heap spiral between full marks.
#   Set 0 to disable for A/B.
{% unless flag?(:gc_none) %}
  lib LibGC
    fun set_free_space_divisor = GC_set_free_space_divisor(divisor : UInt32)
    fun collect_a_little = GC_collect_a_little : Int32
  end

  module BenchGC
    def self.setup! : Nil
      LibGC.set_free_space_divisor(ENV["BENCH_GC_DIVISOR"]?.try(&.to_u32?) || 1_u32)
      return if ENV["BENCH_GC_TRICKLE"]? == "0"
      interval = ENV["BENCH_GC_TRICKLE_MS"]?.try(&.to_f64?) || 2.0
      spawn(name: "gc-trickle") do
        loop do
          LibGC.collect_a_little
          sleep interval.milliseconds
        end
      end
    end
  end
{% end %}
