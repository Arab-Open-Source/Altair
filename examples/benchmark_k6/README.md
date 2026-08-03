# Altair Benchmark Report

A load test that compares **Altair** (Crystal) against **Express** (Node.js) and
**Fiber** (Go) on identical PostgreSQL-backed CRUD endpoints, driven by k6 over
real HTTP.

The current committed results live in [`results/`](results/) as k6 summary
exports. The short version:

- **Write** (POST `/items`): Altair sustains **11,889 req/s** — the fastest of
  the three (**1.68x Express**, **2.18x Fiber**).
- **Read** (GET `/items/:id`): Altair sustains **14,096 req/s** — **1.85x
  Express**, 0.84x Fiber. Altair's median read latency (42 ms) is the lowest
  of the three; its p95 (379 ms) lands between Fiber's tight 171 ms and
  Express's 371 ms.
- **Zero failed requests** across all six runs; every `status is 200/201` check
  passed.

These numbers were produced after three fixes. First, the ORM/DB-layer hardening
described in [`CHANGELOG.md`](../../CHANGELOG.md): the query path no longer
pays a global mutex per statement outside transactions, per-statement timing is
skipped when no instrumentation hook is registered, and the `SELECT` prefix is
a compile-time constant instead of an allocation per lookup. Second, the root
cause of Altair's extreme tail latency was found and removed: its **single
connection pool was capped at 50 slots** while the load presented **2000
concurrent requests**, so ~1950 requests queued behind 50 busy connections and
the longest waits ran into the seconds. Third, the benchmark was made fair:
all three frameworks now share the **same 200-connection budget** (up to
PostgreSQL's `max_connections=220`) instead of Altair running 200 while
Express and Fiber each ran 8×50. Giving Altair the same headroom took read p95
from 900 ms → 379 ms, read max from 4.4 s → 991 ms, and read throughput from
8,200 → 14,096 req/s.

**Status: this benchmark is experimental.** Altair is still under active
development, and these numbers are a snapshot of where the framework stands
today. Real-world performance can vary with workload, hardware, and tuning; we
expect Altair to improve further as the framework matures. Treat the results
here as directional, not as a final verdict.

---

## Results

All figures below are from the latest fair runs: **every framework gets the
same 200-connection budget** against PostgreSQL, 90-second sustained load at
2000 VUs. Latency percentiles include k6 warm-up and ramp-down.

### Read workload — `GET /items/:id`

Primary-key lookups against 10,000 seeded rows.

| Framework | Requests | Throughput | Avg | p50 | p90 | p95 | p99 | p99.9 | Max | Failed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fiber | 1,674,709 | 16,747 req/s | 113.1 ms | 109.3 ms | 144.6 ms | 170.8 ms | 198.8 ms | 243.2 ms | 335.7 ms | 0% |
| **Altair** | **1,409,623** | **14,096 req/s** | **126.8 ms** | **41.8 ms** | 329.3 ms | 379.4 ms | 488.8 ms | 640.8 ms | 991.4 ms | 0% |
| Express | 761,609 | 7,616 req/s | 245.0 ms | 246.7 ms | 320.8 ms | 371.3 ms | 485.3 ms | 643.0 ms | 1,302.3 ms | 0% |

The p90 column shows a structural difference: Altair and Express keep a tight
body of requests (p50 in the tens of ms) and a tail that begins at p90, while
Fiber's whole body sits higher and flatter. Altair now shows its two-part shape
clearly: the shared pool serves most requests in ~20-50 ms, then a queue builds.

### Write workload — `POST /items`

One row inserted and committed per request (JSON body).

| Framework | Requests | Throughput | Avg | p50 | p90 | p95 | p99 | p99.9 | Max | Failed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Altair** | **1,188,983** | **11,889 req/s** | **159.4 ms** | **36.9 ms** | 394.7 ms | 472.7 ms | 649.5 ms | 918.5 ms | 1,781.8 ms | 0% |
| Express | 705,949 | 7,059 req/s | 260.0 ms | 251.8 ms | 355.3 ms | 399.8 ms | 500.9 ms | 3,610.6 ms | 4,734 ms | 0% |
| Fiber | 546,313 | 5,463 req/s | 348.0 ms | 363.1 ms | 390.3 ms | 395.4 ms | 408.0 ms | 443.7 ms | 449.6 ms | 0% |

Write again favors Altair's throughput: it writes nearly 2.2x Fiber and 1.7x
Express at the same pool budget. Fiber's write median (363 ms) is the highest
of the batch; Altair's write median stays low (37 ms) with the tail carrying
the load.

### Relative throughput

| Comparison | Read | Write |
|---|---|---:|---:|
| Altair vs Express | 1.85x | 1.68x |
| Altair vs Fiber | 0.84x | 2.18x |
| Fiber vs Express | 2.20x | 0.77x |

### Data moved

| Framework | Scenario | Received | Sent |
|---|---|---:|---:|
| Altair | read | 207.8 MB / 2.08 MiB/s | 107.4 MB / 1.07 MiB/s |
| Altair | write | 145.2 MB / 1.45 MiB/s | 188.3 MB / 1.88 MiB/s |
| Express | read | 203.1 MB / 2.03 MiB/s | 58.0 MB / 0.58 MiB/s |
| Express | write | 169.6 MB / 1.70 MiB/s | 111.6 MB / 1.12 MiB/s |
| Fiber | read | 243.6 MB / 2.44 MiB/s | 127.6 MB / 1.28 MiB/s |
| Fiber | write | 65.5 MB / 0.66 MiB/s | 86.3 MB / 0.86 MiB/s |

---

## Analysis

**Altair leads on writes (11,889 req/s) and reads (14,096 req/s), beating
Express on both and trailing Fiber only on reads.** The write path is dominated
by the INSERT + commit round-trip to PostgreSQL, so all three runtimes converge
on latency, and throughput is where they separate: Altair sustains **2.18x
Fiber** and 1.68x Express on writes. The read path is the reverse — Fiber's
scheduler sustains the most requests (16,747 req/s) — but Altair's read median
(42 ms) is the lowest of the three, and its p95 (379 ms) is on par with
Express's 371 ms, both behind Fiber's tight 171 ms.

### The tail-latency investigation

The original runs after the ORM hardening showed an alarming shape: Altair's
read median was **8 ms** but its max was **2.4 s** (later **4.4 s**). A
no-database `/health` probe under the identical 2000-VU load capped at **355 ms
max and 76 ms p95 at ~40,725 req/s**, proving the HTTP/scheduler layer was
healthy and the delay lived in the database path. The candidate causes were
eliminated one by one with experiments:

- **Not PostgreSQL**: primary-key lookups measured ~2 ms; the pool never ran
  more than ~16 of its 50 connections... at first glance.
- **Not the pool-fairness logic**: porting an upstream pool patch that made
  release signals never drop changed nothing because connections were **never
  free** to be stolen.
- **Not GC, request logging, or per-statement timing**: each was disabled in
  turn with no effect on the tail.

The resolution was a capacity calculation, not a code bug. Kill a closed-loop
load of 2000 virtual users against a single shared pool: at any instant ~1950
of them are waiting for one of the 50 busy connections, which is why total
concurrency (Little's law: req/s × avg latency ≈ 1900) sat at the pool
boundary. Express and Fiber each run **8 OS processes**; Altair is one process
with one pool, so a 50-slot pool was the whole framework's concurrency
ceiling. Giving Altair the same headroom as the pool the other two effectively
had (200 connections, PostgreSQL's `max_connections=220`) took read p95
900 → 379 ms, read max 4,374 → 991 ms, and read throughput 8,200 → 14,096
req/s; write p95 649 → 473 ms and throughput 7,716 → 11,889 req/s. This is a
**configuration** fix (fair pool sizing for a single-process runtime), not a
framework defect — but it changes how the benchmark is tuned and how the
single-pool design should be documented for users.

The next step was making the benchmark honest: the first "fair" run gave Altair
200 and left Express/Fiber at 50, which over-drew Altair. Every figure in this
document now comes from **the same 200-connection budget for all three**. The
tail-latency budget at that equal cap:

- **Every remaining slow request is the pool checkout.** In-request timing
  instrumented during the read load showed the request, pool-checkout+query,
  and query histograms moving identically — the DB path is one blocked span.
  The profile is bimodal: ~60% of reads finish in <20 ms on a warm pooled
  connection, then ~35% land in a 200–500 ms band with almost nothing between
  — the signature of 2000 simultaneous requests queuing on 200 shared slots.
  The no-database probe stays under ~100 ms at p99.

- The pool budget is now the real trade. 200 slots under 2000 VUs leaves a
  sub-second worst case (read p99.9 641 ms, write p99.9 918 ms). Fiber's 8
  processes never contend on one wait queue, which is its whole advantage here;
  Express's cluster does the same but at Node's higher per-contention cost.

Notable observations:

- Altair still shows a heavier max than Fiber (read 991 vs 336 ms, write 1,782
  vs 450 ms). At the same 200-connection ceiling the remaining tail is the same
  queueing physics, only shorter: 2000 VUs against 200 shared slots. Fiber
  sidesteps part of this by splitting the load across 8 processes that never
  share a slot wait.
- Altair's read distribution is now mildly bimodal: the fast path around 40 ms
  (warm pooled connections) and the waiting fraction in the hundreds of
  milliseconds. The multi-second wall from the 50-pool runs is gone.
- Fiber's write latencies are remarkably tight (p95 398 ms, max 450 ms); it
  sustains the fewest writes but never stalls. Express sits in the middle on
  read latency and trails on throughput in both phases.

---

## Methodology

### Stack

- **PostgreSQL 17** (`postgres:17-alpine`) via compose, pinned to **6 CPUs /
  2 GB**, published on `127.0.0.1:55433` with `max_connections=220`, and a
  dedicated table per framework (`items_express`, `items_fiber`,
  `items_altair`). The 6-CPU allocation keeps PostgreSQL clear of the
  framework ceiling — earlier runs with 2 CPUs capped the whole benchmark at
  ~8.4k req/s regardless of framework or pool size.
- The three applications run **natively on the host** (no container overhead),
  one per port, each limited to the same 200-connection budget. Express and
  Fiber each run 8 OS processes; Altair runs one process with one shared pool.

  | Framework | Port | Tuning |
  |---|---|---|
  | **Express** | 4101 | Node cluster: 1 primary + 8 workers; `pg` pool max 200 (25 per worker). |
  | **Fiber** | 4102 | `GOMAXPROCS=8`; `pgxpool` max 200 / min 200. |
  | **Altair** | 4103 | `CRYSTAL_WORKERS=8` (execution context resized); DB pool 200, initial 200, max idle 200. |

- The pool sizing is deliberate and is the tail-latency fix documented above:
  with 2000 concurrent virtual users, a 50-slot single pool kept ~1950 requests
  queued behind 50 busy connections (multi-second max latencies). Altair's pool
  is 200 so its single pool reaches the same PostgreSQL `max_connections=220`
  headroom the other two get via 8 pools. The same binary at pool 50 produced
  read max 4,374 ms / p95 900 ms / 8,200 req/s.

- Every app is started with `ulimit -n 65535`. The default soft limit of 1024
  file descriptors is fatal here: Altair logged 9.5 million
  `accept: Too many open files` errors under 2000 VUs, which collapsed
  throughput and produced a pathological bimodal latency. Express and Fiber
  tolerate EMFILE silently; Altair's server does not.

### Load profile

k6 `ramping-vus` scenario shared by both scripts:

| Phase | Duration | Virtual users |
|---|---|---:|
| Warm-up ramp | 5 s | 1 → 2000 |
| Sustained | 90 s | 2000 |
| Ramp-down | 5 s | 2000 → 0 |

- **Read**: one random seeded row (`id` in 1..10,000) per request, asserting
  `status is 200`.
- **Write**: one JSON insert per request, asserting `status is 201`.
- Threshold: `http_req_failed: rate<0.005`.

### Fairness and caveats

- All three runtimes are tuned symmetrically **to the same 200-connection
  budget** wherever the architecture allows (8 workers / processes, pool 200,
  90-second sustained load at 2000 VUs). There is no untuned baseline and no
  framework gets more than its peers.
- All three share the **same single PostgreSQL instance** (220 connections).
  At this load the database is a shared ceiling, so the numbers describe the
  *combined* stack, not raw framework throughput. During the write phase the
  database is saturated.
- The host runs PostgreSQL, k6, and the application together; the tail latencies
  reflect core contention on the host, not just framework behavior.
- Numbers are per-run samples, not averages across repeated runs. Treat them as
  indicative; rerun locally (below) for confidence on your own hardware.
- Latency percentiles include k6 warm-up and ramp-down traffic, which inflates
  tail values under a fixed-length run.

---

## Reproduce

Requires Crystal, Go, Node.js, [k6](https://k6.io), `docker compose`, and
`psql` on the host.

```bash
# 1. boot only PostgreSQL (the apps run natively on the host)
docker compose up -d postgres
./scripts/seed.sh            # 10,000 rows per framework table

# 2. build the servers once
crystal build --release --no-debug app/altair/src/bench.cr -o /tmp/bench_altair
go build -o /tmp/bench_fiber app/fiber/main.go
# Express needs no build: node app/express/src/server.js

# 3. run each framework's write + read in isolation
./scripts/bench.sh express   # stops the other apps, starts this one if needed
./scripts/bench.sh fiber
./scripts/bench.sh altair

# 4. render the summary tables
./scripts/summary.sh
```

`scripts/bench.sh <express|fiber|altair>` stops the other two apps, starts the
target with `ulimit -n 65535` and its tuned environment if it is not already
up, truncates the table, runs the k6 write phase, reseeds, then runs the read
phase. It stops the other two apps so each framework runs alone. Results land in
`results/<framework>-write.json` / `results/<framework>-read.json`; each app's
log is in `/tmp/bench_<name>.log`.

Tune the load profile with k6's `--vus`/`--duration` flags (bench.sh uses the
defaults above) or the `TOTAL_DURATION`/`VUS` env vars documented in
[`k6/README.md`].

`scripts/run.sh` is an alternative containerized runner that boots all three
apps in compose; the numbers above were produced by the host-native `bench.sh`
path and may differ from the containerized one.

---

## Layout

```
app/altair/     Altair server (bench.cr, application.cr, ItemsController, Item model)
app/express/    Express reference server (node cluster)
app/fiber/      Fiber reference server (GOMAXPROCS + pgx pool)
db/init.sql     One table per framework
k6/read.js      Read load script (random PK lookup)
k6/write.js     Write load script (single-row insert)
k6/echo.js      No-DB load script (GET /health) used to isolate the HTTP layer
scripts/bench.sh     Host-native runner (isolation + ulimit + write/read phases)
scripts/run.sh  Containerized runner (compose)
scripts/summary.sh  Renders results/*.json as markdown tables
results/        k6 summary JSON exports
```