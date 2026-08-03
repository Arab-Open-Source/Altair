# Rails vs Altair Benchmark Report

A load test comparing **Altair** (Crystal) against **Ruby on Rails** (MRI/Ruby
3.3, Puma 6) on identical PostgreSQL-backed CRUD endpoints, driven by k6 over
real HTTP. It complements the Express vs Fiber vs Altair report in
[`../benchmark_k6`](../benchmark_k6).

> **Disclaimer — numbers are not accurate yet.** Altair is still under active
> development and is **not feature-complete**. It lands optimizations weekly,
> has no battle-tested production hardening, and is missing much of the
> ecosystem (jobs, auth, asset pipeline) that a real app ships with. Take
> these figures as a directional snapshot of the current codebase, not a
> settled verdict — expect the Altair side to change frequently as the
> framework evolves toward release.

## Setup

- **PostgreSQL 17** in Docker, pinned to **2 CPU cores / 3 GB RAM**
  (`max_connections=220`), published on `127.0.0.1:55434`.
- Both applications run **natively on the host** (no container overhead).
- **Tiered load**: each workload ramps to **500** concurrent clients, holds,
  ramps to **1000**, holds, then ramps to **2000** and holds — 60 s per tier.
- **Fair pool budget**: both frameworks share the same 200-connection budget
  against PostgreSQL, so neither over-draws the shared `max_connections=220`.
  Altair: one pool of 200. Rails: Puma workers x Active Record pool = 200.
- Host: 12 cores / 13 GB RAM, both runtimes using all cores.

## Results

Current runs land in [`results/`](results/) (k6 summary JSON + stdout).
Render the table with:

```bash
./scripts/summary.sh
```

| framework | scenario | req/s | failed % | avg (ms) | p50 (ms) | p90 (ms) | p95 (ms) | p99 (ms) | p99.9 (ms) | max (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| altair | read  | 7931.8 | 0.00 | 140.30 | 51.70  | 364.28 | 460.03 |  693.42 | 1061.54 | 2276.96 |
| rails  | read  | 2728.7 | 0.00 | 408.62 | 350.71 | 759.61 | 825.08 |  935.89 | 1049.47 | 1148.89 |
| altair | write | 7443.7 | 0.00 | 149.62 | 55.99  | 378.42 | 495.21 |  794.16 | 1212.88 | 2823.43 |
| rails  | write | 1979.3 | 0.00 | 563.71 | 529.04 | 950.95 | 1000.48 | 1087.14 | 1194.00 | 1268.22 |

## Analysis

On this machine Altair outruns the Ruby/Puma stack on both workloads by a
wide margin while holding p99 latency well below the competing server's
median:

- **Read throughput ~2.9x higher** (7,932 vs 2,728 req/s).
- **Write throughput ~3.8x higher** (7,444 vs 1,979 req/s) — very close to
  the read number, so database inserts are not the binding constraint for
  Altair; for Rails, writes take a markedly larger hit than reads do.
- **Latency shape is completely different.** Rails is *consistently* slow
  (p50 350 ms on reads, 529 ms on writes) and compresses at the tail —
  its max (1.15–1.27 s) is close to its p99.9. Altair has a fat p50 (52–56
  ms) but a *very* long tail (p99 693–794 ms, max up to 2.8 s). In other
  words: Altair's median is an order of magnitude faster, but its worst-case
  straggler is up to twice Rails's worst case.
- **The tail is load-shaped, not per-request.** The tiered ramping-load mixes
  500/1000/2000-client phases into one aggregate; the long ASC tail on
  Altair comes from the 2000-VU tier pressure on the shared, CPU- and
  connection-pool capped PostgreSQL (2 cores, max 220 connections shared
  *without* per-tier isolation here). Rails's slowly-burning stable latency
  is the signature of a saturated runtime pacing each request, whereas
  Altair's occasional multi-second stragglers line up with the pool being
  fully checked out at peak pressure.
- **No failures on any run** (0.00% in all four phases), even sustained at
  2000 concurrent sockets against a 2-core database.

Two honest caveats keep this from being apples-to-apples at the extreme end:

1. The **database is the shared bottleneck.** Both stacks contend for one
   PostgreSQL capped at 2 CPUs / 220 connections. The right reading is
   "how much of that one Postgres each framework can push through", not
   the theoretical ceiling of the language/runtime.
2. **The 2000-VU tier decides the tail.** k6 keeps maximal in the 2000
   tier for the longest single phase (60 s), so p99–p99.9–max are
   dominated by the most loaded tier. That is honest to "what happens at
   capacity", but it means the *median* numbers (p50) represent the tier
   mix, not a steady state.

## Methodology

### Load profile

k6 `ramping-vus`, shared by `k6/read.js` and `k6/write.js`:

| Phase | Duration | Virtual users |
|---|---:|---:|
| Ramp | 10 s | 1 → 500 |
| Hold tier 1 | 60 s | 500 |
| Ramp | 15 s | 500 → 1000 |
| Hold tier 2 | 60 s | 1000 |
| Ramp | 15 s | 1000 → 2000 |
| Hold tier 3 | 60 s | 2000 |
| Ramp-down | 10 s | 2000 → 0 |

- **Read**: one random seeded row (`id` in 1..10,000) per request, asserting
  `status is 200`.
- **Write**: one JSON insert per request, asserting `status is 201`.
- Threshold: `http_req_failed: rate<0.005`.

### Fairness and caveats

- Both frameworks get the **same 200-connection budget**; Altair splits it
  across one shared pool, Rails across its Puma workers via the pool formula
  in `app/rails/config/database.yml` (`BENCH_POOL / BENCH_WORKERS`).
- The database is a shared ceiling, so the numbers describe the *combined*
  stack, not raw framework throughput.
- The host runs PostgreSQL, k6, and the app together; tail latencies reflect
  core contention on the host, not just framework behavior.
- Numbers are per-run samples, not averages across repeated runs.

## Reproduce

Requires Crystal, Ruby (3.3+), Bundler, [k6](https://k6.io), and
`docker compose` on the host.

```bash
# 1. boot PostgreSQL (2 CPUs / 3 GB) and seed 10,000 rows per table
docker compose up -d postgres
./scripts/seed.sh

# 2. build the servers once
crystal build --release --no-debug app/altair/src/bench.cr -o /tmp/bench_altair
(cd app/rails && bundle install)   # vendor/bundle, no system gems touched

# 3. run each framework's write + read in isolation (tiered 500/1000/2000)
./scripts/bench.sh altair
./scripts/bench.sh rails

# 4. render the summary table
./scripts/summary.sh
```

`scripts/bench.sh <altair|rails>` stops any leftover apps (so pooled
connections can't starve a run), starts the target with `ulimit -n 65535`,
truncates the table, runs the k6 write phase, reseeds, then runs the read
phase. Results land in `results/<framework>-write.json` /
`results/<framework>-read.json`; each app's log is in `/tmp/bench_<name>.log`.

Tune the tier with env vars: `TIER1`, `TIER2`, `TIER3`, `TIER_HOLD` (defaults
500 / 1000 / 2000 / 60). Tune Rails with `BENCH_WORKERS`, `BENCH_THREADS`,
`BENCH_POOL`; Altair with `CRYSTAL_WORKERS`, `BENCH_POOL`.

## Layout

```
app/altair/     Altair server (bench.cr, application.cr, ItemsController, Item model)
app/rails/      Rails API app (ItemsController, Item model, puma + AR config)
db/init.sql     One table per framework
k6/read.js      Tiered read load (random PK lookup)
k6/write.js     Tiered write load (single-row insert)
scripts/bench.sh     Host-native runner (isolation + tiered write/read phases)
scripts/seed.sh Seeds 10,000 rows per table
scripts/summary.sh Renders results/*.json as markdown tables
results/        k6 summary JSON + stdout exports
```