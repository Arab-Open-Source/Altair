# Read-tail fix trial - branch results (local, not merged)

Branch: `fix-read-tail-gc`. Applies every measured mitigation to the bench
app: `Content-Length` framed renders (already on main), plus
`gc_tuning.cr` - `GC_set_free_space_divisor(1)` and a 2 ms
`GC_collect_a_little` trickle fiber - wired into `bench.cr` behind
`BENCH_GC_DIVISOR` / `BENCH_GC_TRICKLE` (defaults on).

## Trial

Six interleaved full `bench.sh altair` rounds (100 VUs / 60 s / pool 20 /
6 workers), server process verified unique per round (PID-stamped
filenames under `results/fixtest3/`; two phantom rounds where a failed
start left the previous run's JSON in place were dropped by
exact-duplicate detection).

Read phase:

| Config | rps | p95 | p99 | p99.9 | max |
|---|---:|---:|---:|---:|---:|
| OLD stock GC (2 clean rounds) | 15,489 | 9.5 | 14.1 | 20.1 | 35.3 |
| NEW divisor 1 + trickle (2 clean rounds) | 14,950 | 10.0 | 14.9 | 21.4 | 36.5 |
| NEW, dirty-window round (r3) | 13,898 | 10.9 | 16.1 | 123.5 | 482.2 |
| Committed main baseline (dirty window) | 15,539 | 8.4 | 14.6 | 153.6 | 247.0 |

## Verdict

1. **The dirty tail is per-run intermittent, not per-config.** In this
   session the stock configuration produced clean rounds (max 26-44 ms)
   with no fix at all, while a fixed round still landed a dirty window
   (482 ms). The committed 153.6 / 247.0 baseline was itself a
   dirty-window sample.
2. **The GC knobs do not control which window a run gets** - they change
   collection pacing, not the heap-trajectory branch the run lands on
   (the hysteresis mechanism in `read-tail-investigation.md`).
3. **In clean windows the knobs cost 3.5-6.5 percent** on throughput and
   every read percentile. Net: a default-on fix is a regression; kept
   opt-in via `BENCH_GC_DIVISOR=0`-style env (defaults documented here
   as experimental, off in comparisons).

## Consequences for the benchmark methodology

Single-run k6 summaries on this host have bimodal tails. Official
comparisons should use the **median of at least three interleaved
rounds** per arm (the exact procedure this trial validated), and the
committed four-arm table's read-tail row for Altair should be re-taken
under that rule - it currently reflects one dirty-window sample.

## Recommended next step

The remaining path to a deterministic fix is the open question in the
investigation: why some runs' read phase settles on the high-heap
equilibrium. A first-seconds heap histogram per phase is the
discriminating measurement.
