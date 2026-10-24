# Read-tail latency investigation

Symptom: at the unified profile (100 VUs, 60 s, 20 connections, 6 workers)
the read workload (`GET /items/:id`) shows a heavy extreme tail while the
write workload on the same server, same minute, is clean:

| Workload | p50 | p95 | p99 | p99.9 | max |
|---|---:|---:|---:|---:|---:|
| Write `POST /items` | 5.5 ms | 7.3 ms | 8.6 ms | 10.7 ms | 18.1 ms |
| Read `GET /items/:id` | 5.5 ms | 8.4 ms | 14.6 ms | 153.6 ms | 247.0 ms |

The distributions are identical through p95; roughly 1 in 1,000 read
requests lands in a 150-250 ms cluster that writes never visit. This
document collects the evidence gathered so far, ranks the candidate
causes, and defines the experiments that discriminate between them.

## Evidence

Measured runs on the benchmark host (Ryzen 5 4600G, 6c/12t, PostgreSQL
pinned to 6 CPUs / 2 GB on 127.0.0.1:55433):

| Run | Profile | Harness | Write max | Read p99.9 / max |
|---|---|---|---:|---:|
| Committed four-arm (patched) | 100 VU, pool 20 | `bench.sh` (warmup + phases) | 18.1 ms | 153.6 / 247.0 ms |
| Ad-hoc k6 (patched) | 100 VU, pool 20 | manual, after a 60 s write phase | 121 ms | ~ / 46.2 ms |
| Ad-hoc k6 (patched, cold server) | 100 VU, pool 200 | manual, write first | 917 ms (cold start) | ~ / 44.5 ms |
| A/B patched arm | 500 VU, pool 200 | `bench.sh` | 5,135 ms | 438 / 965 ms |
| A/B unpatched arm | 500 VU, pool 200 | `bench.sh` | 3,612 ms | ~90 ms max |
| 2026-09 fair runs (unpatched) | 1,000 VU, pool 200 | `bench.sh`-style | 873 ms | 184 / 287 ms |
| 2026-09 baseline (unpatched) | 1,000 VU, pool 200 | `bench.sh`-style | 304 ms | 2,427 / 3,913 ms |

Patterns worth explaining:

1. **The split tail is phase-specific.** One server process serves the
   write phase (clean, 18 ms max) and then, seconds later, the read phase
   (247 ms max). A purely global stall source (GC alone) should mark both
   phases; something about the read phase or its setup differs.
2. **Manual read runs are clean; harness read runs are dirty** at the same
   20/6 settings and the same binary. The manual runs differ in one
   visible way: the read table was seeded *on top of* existing rows (no
   `TRUNCATE`), and no fresh 10k-row table was created immediately before
   measurement.
3. **The wire-protocol patch correlates with a heavier read tail under
   oversubscription** (500 VU A/B: patched 438 ms p99.9 vs unpatched ~90
   ms max) while improving throughput. Dirty read tails predate the patch
   (September runs), so the patch is an amplifier, not the origin.
4. **Throughput and p95 are healthy everywhere** (15.5k rps reads). The
   system is not saturated; this is a rare-event tail, not queueing.

## Candidate causes, ranked

### C1 - Boehm stop-the-world pause, amplified by the per-connection lock convoy

Mechanism. Boehm's full collection stops all Crystal worker threads for a
window that scales with the live heap. The vendored wire-protocol fix
(issue #21) added a reentrant per-connection mutex around each
extended-query exchange; with the 20-connection budget, five request
fibers share every physical connection and queue on that mutex. A
stop-the-world pause that lands while one fiber holds the connection lock
freezes the holder; on resume the four queued fibers drain serially, and
each accumulates pause plus queue. One 40-80 ms pause can therefore
surface as a 150-250 ms cluster - the exact shape observed.

Supporting evidence. The 500 VU A/B arm (heavier oversubscription, larger
heap) shows the amplified shape (438/965 ms); the amplification grows
with fibers-per-connection and heap size, both of which the patch's
latency profile should track. The earlier per-second instrumentation
(September, `scripts/diagnose.sh`) demonstrated one collection per second
landing on in-flight requests at the 1,000 VU profile.

Counter-evidence. The write phase in the same process shows no events
above 18 ms across ~1M requests; if full collections ran at the same rate
and duration during the write phase, some writes should carry one. Either
collections are rarer/shorter during writes (smaller live heap early in
the run, see C4) or C1 is not the dominant source at 100 VU.

How to confirm. Run the read phase under the sampling build - it counts
stop-the-world events and their total ms per second, next to per-second
request latency:

```
VUS=100 DURATION=60 scripts/diagnose.sh
```

Then correlate: if the seconds containing the request-latency spikes are
the seconds with `gc_stw_events > 0` and `gc_stw_ms` in the 40-250 ms
range, C1 is confirmed and quantified. If the STW meter stays quiet
during the spike seconds, C1 is ruled out for this profile.

### C2 - PostgreSQL-side transient during the measured read phase

Mechanism. `bench.sh` runs `TRUNCATE items_altair` then seeds 10,000
fresh rows immediately before the read phase. Two server-side events can
fire *inside* the 60-second measurement window: autoanalyze/autovacuum
wakes on the freshly (re)built table about a minute after the seed, and
the checkpoint pushed by the preceding write phase (~1M inserts of WAL)
completes during the read phase. Both stall or slow queries briefly and
in clusters.

Supporting evidence. This is the one concrete difference between the
dirty harness runs and the clean manual runs (pattern 2): the manual flow
never truncated, never created a fresh 10k table right before measuring,
and let the write phase's checkpoint complete before reads began. The
September baseline's catastrophic read tail (3.9 s max) also followed
fresh-seed phases.

Counter-evidence. PostgreSQL is pinned to 6 CPUs and was measured at 1-2
active backends during reads; whether an autoanalyze on a 10k-row table
can produce 150-250 ms client-visible stalls on this hardware is
unproven.

How to confirm. Two runs, no code changes:

- Run the read phase twice back-to-back without re-seeding between them
  (re-run only `k6/read.js`). If the second run is clean, the transient
  lives in the seeding/checkpoint path (C2), not in steady state.
- Before the measured run, execute `SET autovacuum = off` on the bench
  database and force `CHECKPOINT;`. If the tail disappears, C2 is
  confirmed.

### C3 - Read-path allocation profile (GC trigger frequency asymmetry)

Mechanism. The read path allocates more per request than the write path:
primary-key decode plus `Item` instantiation plus `String.build` +
`JSON.build` for the ~160-byte body, versus a parsed two-field JSON tree
and a 10-byte write response. A higher allocation rate triggers
collections more often during the read phase, raising the probability
that a pause (C1's mechanism) lands inside the measured window - while
the write phase, allocating less, collects less.

Supporting evidence. The framework audit attributed read-side allocation
to JSON response building; the write tail staying flat is consistent with
fewer/shorter collections in that phase.

Counter-evidence. Write traffic still allocates substantially (a JSON
parse tree per request); the per-request allocation gap is a hypothesis
without a measurement yet.

How to confirm. The sampling build prints per-second
`gc_alloc_mb`/`gc_collections` next to per-second request stats for both
phases - `VUS=100 DURATION=60 scripts/diagnose.sh` and compare the write
phase's row against the read phase's row. An A/B with a hand-rolled
response string (skip `JSON.build`, format with `String.build` only)
would isolate the serializer's share directly.

### C4 - Admission-gate burst parking (likely minor at 100 VU)

Mechanism. `BENCH_ACTIVE=20` parks fibers beyond 20 concurrent database
callers on a FIFO gate. If a burst or a stall (C1) blocks the 20 admitted
fibers, the 80 parked ones inherit the stall plus drain time.

Counter-evidence (strong). Little's law and the measured medians argue
the gate is not engaged at this profile: 100 in-flight requests at 15.5k
rps imply 6.4 ms average latency - exactly what p50 shows (5.5 ms). If 80
fibers were parked behind 20 permits, the median would sit near 25-30 ms.
The gate matters at 500-2,000 VU, not here.

How to confirm. Re-run with `BENCH_ACTIVE=0`; no change expected at 100
VU. (At 500 VU it should matter - a useful control for that profile.)

### C5 - Chunked response writes for read bodies

Mechanism. `render json` writes without `Content-Length`, so each read
response goes out chunked (chunk header, body, terminator - extra
allocations and syscalls), and read bodies are ~16x larger than write
bodies.

Assessment. Contributes to C3's allocation rate but cannot produce
100 ms-scale stalls alone; treat as a secondary term inside C3, worth
fixing opportunistically (set `Content-Length` before writing for
buffered JSON renders) rather than investigating separately.

## Ruled out

- **Pool saturation** - p50/p95 are flat and PG idles at 1-2 active
  backends; the September diagnosis already showed throughput is not
  pool-bound at this profile.
- **The read replica router** - no `db_replica_url` is configured in the
  benchmark app; the router short-circuits to the primary pool.
- **k6 client artifacts** - the same k6 instance produced clean read runs
  (manual) and dirty ones (harness) against the same server binary.

## Experiment plan (in order)

1. `VUS=100 DURATION=60 scripts/diagnose.sh` - one instrumented sweep
   covering both phases; correlate per-second `max_ms` with
   `gc_stw_ms`/`gc_collections` (decides C1 vs C2/C3).
2. Read phase run twice without re-seeding; then with
   `autovacuum=off` + forced `CHECKPOINT` (decides C2).
3. Content-Length fast-path A/B on the JSON render (quantifies C5/C3's
   serializer share).
4. If C1 confirms: evaluate mitigation options - raise Boehm's
   `GC_INITIAL_HEAP_SIZE` (fewer, still-predictable collections), tune
   `GC_MARK_THREADS`/parallel mark, or move read-path allocation off the
   hot path. The `gcry` collector A/B (November experiment notes) stays a
   separate track.

The raw evidence for every number above is committed under `results/` or
reproducible with the commands in this file.
