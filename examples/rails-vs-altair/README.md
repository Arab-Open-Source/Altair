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
  ramps to **1000**, holds, then ramps to **2000** and holds — 5 s per tier
  (fast feedback; `TIER_HOLD` controls the duration).
- **Paced virtual users**: every VU pauses **100 ms** (`THINK_MS`) between
  requests, so the pool sees realistic, think-timed users rather than a closed
  loop that saturates the connection queue.
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
| altair | read  | 6515.1 | 0.00 | 58.46  | 13.84  | 254.96 | 278.94 | 313.81 | 368.20 | 450.39 |
| rails  | read  | 3519.0 | 0.00 | 195.45 | 170.56 | 401.67 | 438.98 | 520.85 | 639.41 | 708.76 |
| altair | write | 6114.7 | 0.00 | 69.42  | 18.59  | 267.57 | 287.85 | 346.13 | 429.33 | 968.24 |
| rails  | write | 2656.7 | 0.00 | 294.37 | 238.59 | 620.85 | 662.13 | 725.85 | 823.91 | 897.64 |

## Analysis

Under paced load, Altair outruns the Ruby/Puma stack on both workloads while
keeping its worst-case latency in line with — or better than — Rails's:

- **Read throughput ~1.9x higher** (6,515 vs 3,519 req/s) and **~12x faster
  median** (13.8 vs 170.6 ms).
- **Write throughput ~2.3x higher** (6,115 vs 2,657 req/s) and **~13x faster
  median** (18.6 vs 238.6 ms).
- **The tail now converges.** Altair's read max (450 ms) beats Rails's
  (709 ms), and both sit close to their p99.9 — the worst case is no longer a
  pool-queue artifact. The write phases are within ~70 ms of each other
  (968 vs 898 ms); Altair's one straggler is a single-sample max on a grow‑
  ing table, not a structural difference.
- **Latency shape differs sharply.** Altair's p50 is single-digit-to-teens
  milliseconds (a bare `SELECT` by PK on a quiet pool); Rails pays a
  consistent ~170–240 ms floor. Both compress towards their p99, which is
  what think-timed load looks like: nobody queues at the pool, so the
  percentiles track per-request work, not contention.
- **No failures on any run** (0.00% in all four phases) at up to 2000 paced
  clients against a 2-core database.

## Why admission control exists

This is not a tuning knob — it is a structural difference from every framework
that uses `crystal-db` as-is. Without a gate, a burst of requests all pile onto
the pool's wait queue, and the tail latency grows with the depth of that queue:

```
Without
  2000 Requests
        │
        ▼
      DB Pool
        │
     Long Tail
```

With admission control, excess requests wait on the gate's FIFO channel
*outside* the pool — a short, fair line instead of a wall — so the tail stays
bounded under overload:

```
With
  2000 Requests
        │
        ▼
  FIFO Admission
        │
        ▼
      DB Pool
        │
    Predictable Tail
```

The numbers below are the proof of that shape, not the point in itself.

## Admission control

A follow-up sweep ([`results/ADMISSION-SWEEP.md`](results/ADMISSION-SWEEP.md))
measured Altair's database admission-control gate (`config.db_max_active_queries`).
At saturation (`THINK_MS=0`), arming the gate at `N` from 30 up cuts the
worst-case latency from ~1.9 s (write) / ~1.6 s (read) with the gate off down
to ~900 ms / ~340 ms — excess fibers wait on the gate's FIFO channel outside
the pool instead of stacking on the pool's wait queue. The gate helps even at
`N = pool size` (it relocates overload off the single pool queue onto the
fair channel); `N = 50` keeps the full throughput while bounding the tail. See
the sweep for the full table and tuning guidance.

Two honest caveats keep this from being apples-to-apples at the extreme end:

1. The **database is the shared bottleneck.** Both stacks contend for one
   PostgreSQL capped at 2 CPUs / 220 connections. The right reading is
   "how much of that one Postgres each framework can push through", not
   the theoretical ceiling of the language/runtime.
2. **The tiers are short.** At 5 s per tier the aggregate is a snapshot, not
   a steady state — the earlier saturated run (no think time, 60 s tiers)
   told the "max throughput under a closed loop" story, this run tells the
   "realistic paced users" one. `TIER_HOLD` and `THINK_MS` trade between
   them.

## Methodology

### Load profile

k6 `ramping-vus`, shared by `k6/read.js` and `k6/write.js`:

| Phase | Duration | Virtual users |
|---|---:|---:|
| Ramp | 3 s | 1 → 500 |
| Hold tier 1 | 5 s | 500 |
| Ramp | 3 s | 500 → 1000 |
| Hold tier 2 | 5 s | 1000 |
| Ramp | 3 s | 1000 → 2000 |
| Hold tier 3 | 5 s | 2000 |
| Ramp-down | 3 s | 2000 → 0 |

- **Read**: one random seeded row (`id` in 1..10,000) per request, asserting
  `status is 200`.
- **Write**: one JSON insert per request, asserting `status is 201`.
- **Think time**: each VU sleeps `THINK_MS` (100 ms) after every request, so
  one VU issues one request per ~100 ms + response instead of a closed loop.
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
(cd app/altair && crystal build --release --no-debug src/bench.cr -o /tmp/bench_altair)
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

Tune the tier with env vars: `TIER1`, `TIER2`, `TIER3`, `TIER_HOLD`,
`RAMP_S` (defaults 500 / 1000 / 2000 / 5 / 3). Each virtual user paces itself
with a `THINK_MS` millisecond pause between requests (default 100), so the
pool sees a realistic user load instead of a saturated queue; set `THINK_MS=0`
for the closed-loop, throughput-maximizing profile. Tune Rails with
`BENCH_WORKERS`, `BENCH_THREADS`, `BENCH_POOL`; Altair with `CRYSTAL_WORKERS`,
`BENCH_POOL`. Altair's admission-control gate is tuned with `BENCH_ACTIVE`
(`db_max_active_queries`; `0` disables it, ~50 recommended for a 2-core DB).

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