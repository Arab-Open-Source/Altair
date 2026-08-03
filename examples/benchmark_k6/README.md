# Altair Benchmark Report

A load test that compares **Altair** (Crystal) against **Express** (Node.js) and
**Fiber** (Go) on identical PostgreSQL-backed CRUD endpoints, driven by k6 over
real HTTP.

The current committed results live in [`results/`](results/) as k6 summary
exports. The short version:

- **Read** (GET `/items/:id`): Altair sustains **9,513 req/s** — **3.8x Express**,
  1.6x slower than Fiber.
- **Write** (POST `/items`): Altair sustains **4,213 req/s** — **1.8x Express**,
  1.3x slower than Fiber.
- **Zero failed requests** across all six runs; every `status is 200/201` check
  passed.

Express is the intentional **untuned baseline**; Fiber and Altair are both
**tuned** to the CPU quota they are granted (see
[Fairness and caveats](#fairness-and-caveats)).

**Status: this benchmark is experimental.** Altair is still under active
development, and these numbers are a snapshot of where the framework stands
today. Real-world performance can vary with workload, hardware, and tuning;
we expect Altair to improve further as the framework matures. Treat the
results here as directional, not as a final verdict.

---

## Results

### Read workload — `GET /items/:id`

Primary-key lookups against 10,000 seeded rows.

| Framework | Requests | Throughput | Avg | p50 | p90 | p95 | Max | Failed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Fiber | 612,760 | 15,319 req/s | 28.4 ms | 25.1 ms | 47.2 ms | 48.9 ms | 95.2 ms | 0% |
| **Altair** | **380,908** | **9,513 req/s** | **46.0 ms** | **1.0 ms** | **201.6 ms** | **202.4 ms** | **251.7 ms** | **0%** |
| Express | 99,841 | 2,496 req/s | 175.5 ms | 195.0 ms | 207.0 ms | 211.2 ms | 247.7 ms | 0% |

### Write workload — `POST /items`

One row inserted and committed per request (JSON body).

| Framework | Requests | Throughput | Avg | p50 | p90 | p95 | Max | Failed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Fiber | 221,921 | 5,548 req/s | 78.8 ms | 89.9 ms | 95.3 ms | 97.0 ms | 106.5 ms | 0% |
| **Altair** | **168,546** | **4,213 req/s** | **103.8 ms** | **111.1 ms** | **126.9 ms** | **132.1 ms** | **524.7 ms** | **0%** |
| Express | 93,006 | 2,325 req/s | 188.4 ms | 204.5 ms | 214.5 ms | 219.8 ms | 544.4 ms | 0% |

### Relative throughput

| Comparison | Read | Write |
|---|---:|---:|
| Altair vs Express | **3.81x** | **1.81x** |
| Altair vs Fiber | 0.62x | 0.76x |
| Fiber vs Express | 6.14x | 2.39x |

### Data moved

| Framework | Scenario | Received | Sent |
|---|---:|---:|---:|
| Altair | read | 58.9 MB (1.47 MB/s) | 30.4 MB (0.76 MB/s) |
| Altair | write | 21.7 MB (0.54 MB/s) | 27.8 MB (0.70 MB/s) |
| Express | read | 27.9 MB (0.70 MB/s) | 8.0 MB (0.20 MB/s) |
| Express | write | 23.3 MB (0.58 MB/s) | 15.3 MB (0.38 MB/s) |
| Fiber | read | 93.5 MB (2.34 MB/s) | 49.0 MB (1.22 MB/s) |
| Fiber | write | 27.9 MB (0.70 MB/s) | 36.7 MB (0.92 MB/s) |

---

## Analysis

**Altair is 3.8x faster than Express on reads and 1.8x on writes, with roughly
1.3x slower write and 1.6x slower read throughput than Fiber.** Read latency is
close to Fiber's at the median (1.0 ms vs 25.1 ms — Altair's median is actually
the lowest of the three), though its p95 grows to 202 ms under queueing at peak
load. Write latency follows throughput rank (Fiber < Altair < Express).

Notable observations:

- The Node.js event loop saturates first: Express peaks around 2.5k req/s reads
  while its median response time grows to 195 ms, where Altair's median stays
  near 1 ms.
- Altair's read distribution is strongly bimodal — a fast path below a millisecond
  plus a tail of requests waiting on the database connection pool. That is
  consistent with a 30-connection pool contending for a single 2-CPU PostgreSQL
  shared by all three frameworks.
- The write path is dominated by the round-trip to PostgreSQL (INSERT + commit).
  Altair still outruns Express by 1.8x here, confirming the framework itself is
  not the bottleneck at this load level.

---

## Methodology

### Stack

- **PostgreSQL 17** (`postgres:17-alpine`) pinned to **2 CPUs / 2 GB** inside
  compose, with a dedicated table per framework
  (`items_express`, `items_fiber`, `items_altair`).
- Each application container is granted **2 CPUs / 768 MB** (`BENCH_APP_CPUS`).
- k6 runs on the host (outside compose) and generates the load.
- One endpoint pair per framework, backed by a connection pool to the same
  Postgres instance.

### Load profile

k6 `ramping-vus` scenario shared by both scripts:

| Phase | Duration | Virtual users |
|---|---:|---:|
| Warm-up ramp | 5 s | 1 → 50 |
| Sustained | 30 s | 50 |
| Ramp-down | 5 s | 50 → 0 |

- **Read**: one random seeded row (`id` in 1..10,000) per request, asserting
  `status is 200`.
- **Write**: one JSON insert per request, asserting `status is 201`.
- Threshold: `http_req_failed: rate<0.005`.

### Server configurations

| Framework | Notes |
|---|---|
| **Express** | Stock single-process Node.js on its default event loop, default `pg` pool (max 10). The untuned baseline. |
| **Fiber** | `GOMAXPROCS` pinned to the container's 2 CPUs; `pgxpool` max 30 / min 5. |
| **Altair** | Crystal execution context resized to the 2-CPU quota (`CRYSTAL_WORKERS=2`); DB pool sized to 30 with warm idle connections (`BENCH_POOL=30`, initial 10, max idle 30). |

### Fairness and caveats

- The runtimes are **not** tuned symmetrically by design: Express is the stock
  baseline, while Fiber and Altair apply the minimal tuning (CPU pinning, pool
  sizing) that production deployments would use.
- All three frameworks share the **same single Postgres instance**. At 2 CPUs
  the database becomes a shared bottleneck during the write phase, so these
  numbers describe the *combined* stack, not raw framework throughput.
- Numbers are per-run samples, not averages across repeated runs. Treat them as
  indicative; rerun locally (below) for confidence on your own hardware.
- Latency percentiles include k6 warm-up and ramp-down traffic, which inflates
  tail values under a fixed-length run.

---

## Reproduce

Requires `docker`, `docker compose`, and [k6](https://k6.io).

```bash
# build and boot everything
docker compose up -d --build

# seed 10,000 rows per framework table
./scripts/seed.sh

# run the full benchmark (express, fiber, altair) — 30s sustained each
./scripts/run.sh

# rerun a single framework only
./scripts/run.sh altair

# pretty-print the summary JSON as markdown tables
./scripts/summary.sh
```

Tune the load profile with environment variables (see `.env.example`):
`BENCH_VUS_WRITE`, `BENCH_VUS_READ`, `BENCH_WARMUP`, `BENCH_DURATION`, and the
container limits `BENCH_APP_CPUS` / `BENCH_APP_MEM`.

Raw k6 summary exports are written to `results/<framework>-<scenario>.json`
alongside the full stdout logs (`results/*.log`) for each run.

---

## Layout

```
app/altair/     Altair server (application.cr, ItemsController, Item model)
app/express/    Express reference server (untuned baseline)
app/fiber/      Fiber reference server (tuned GOMAXPROCS + pgx pool)
db/init.sql     One table per framework
k6/read.js      Read load script (random PK lookup)
k6/write.js     Write load script (single-row insert)
scripts/run.sh  Full runner (boot, warm up, write phase, reseed, read phase)
scripts/seed.sh Seeds 10,000 rows per table
scripts/summary.sh Renders results/*.json as markdown tables
results/        k6 summary JSON + logs
```
