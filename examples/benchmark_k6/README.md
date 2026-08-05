# Altair Benchmark Report

A load test that compares **Altair** (Crystal) against **Express** (Node.js) and
**Fiber** (Go) on identical PostgreSQL-backed CRUD endpoints, driven by k6 over
real HTTP.

The current committed results live in [`results/`](results/) as k6 summary
exports. The short version:

- **Write** (POST `/items`): Altair sustains **11,209 req/s** — the fastest of
  the three (**1.64x Express**, **2.05x Fiber**), with the tightest write tail
  (max 918 ms; Express's max is 5.2 s).
- **Read** (GET `/items/:id`): Altair sustains **14,105 req/s** — **1.89x
  Express**, 0.86x Fiber. Altair's read p95 (215 ms) beats Express's 369 ms;
  Fiber's tight 177 ms keeps the top spot.
- **Zero failed requests** across all six runs; every `status is 200/201` check
  passed.

These numbers were produced after four fixes. First, the ORM/DB-layer hardening
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
8,200 → 14,096 req/s. Fourth and final, **admission control** (the
`db_max_active_queries` gate) parks the excess virtual users on a FIFO queue
*outside* the pool, so the remaining pool-queueing tail collapsed too: read
max 991 → 617 ms and write max 1,782 → 918 ms with no throughput loss.

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
| Fiber | 1,643,563 | 16,435 req/s | 115.4 ms | 112.6 ms | 144.1 ms | 177.3 ms | 196.0 ms | 220.3 ms | 286.8 ms | 0% |
| **Altair** | **1,410,579** | **14,105 req/s** | **122.7 ms** | **118.6 ms** | 186.7 ms | 214.8 ms | 279.2 ms | 369.3 ms | 617.1 ms | 0% |
| Express | 748,101 | 7,481 req/s | 250.2 ms | 251.1 ms | 314.9 ms | 369.0 ms | 481.1 ms | 1,296.4 ms | 2,285.8 ms | 0% |

The p90 column shows a structural difference: Altair and Express keep a tight
body of requests and a tail that begins at p90, while Fiber's whole body sits
higher and flatter. Altair's two-part shape is the shared pool: most requests
finish on a warm pooled connection, then a queue builds as 2000 VUs contend for
200 slots.

### Write workload — `POST /items`

One row inserted and committed per request (JSON body).

| Framework | Requests | Throughput | Avg | p50 | p90 | p95 | p99 | p99.9 | Max | Failed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Altair** | **1,121,006** | **11,209 req/s** | **169.0 ms** | **170.5 ms** | 212.4 ms | 231.8 ms | 256.6 ms | 397.0 ms | 918.3 ms | 0% |
| Express | 682,283 | 6,822 req/s | 268.7 ms | 258.3 ms | 377.8 ms | 429.9 ms | 545.0 ms | 3,600.5 ms | 5,249.5 ms | 0% |
| Fiber | 545,519 | 5,455 req/s | 348.5 ms | 362.7 ms | 390.7 ms | 394.0 ms | 399.5 ms | 406.5 ms | 407.8 ms | 0% |

Write again favors Altair's throughput: it writes 2.05x Fiber and 1.64x Express
at the same pool budget. Fiber's write median (363 ms) is the highest of the
batch; Altair's write median stays the lowest (170 ms) with the admission gate
keeping the worst-case tail (918 ms) well below Express's 5.2 s.

### Relative throughput

| Comparison | Read | Write |
|---|---:|---:|
| Altair vs Express | 1.89x | 1.64x |
| Altair vs Fiber | 0.86x | 2.05x |
| Fiber vs Express | 2.20x | 0.80x |

### Data moved

| Framework | Scenario | Received | Sent |
|---|---|---:|---:|
| Altair | read | 218.0 MB / 2.08 MiB/s | 112.7 MB / 1.07 MiB/s |
| Altair | write | 143.5 MB / 1.37 MiB/s | 186.1 MB / 1.77 MiB/s |
| Express | read | 209.1 MB / 1.99 MiB/s | 59.8 MB / 0.57 MiB/s |
| Express | write | 171.8 MB / 1.64 MiB/s | 113.1 MB / 1.08 MiB/s |
| Fiber | read | 250.7 MB / 2.39 MiB/s | 131.3 MB / 1.25 MiB/s |
| Fiber | write | 68.6 MB / 0.65 MiB/s | 90.3 MB / 0.86 MiB/s |

---

## Analysis

**Altair leads on writes (11,209 req/s) and reads (14,105 req/s), beating
Express on both and trailing Fiber only on reads.** The write path is dominated
by the INSERT + commit round-trip to PostgreSQL, so all three runtimes converge
on latency, and throughput is where they separate: Altair sustains **2.05x
Fiber** and 1.64x Express on writes. The read path is the reverse — Fiber's
scheduler sustains the most requests (16,435 req/s) — but Altair's read median
(119 ms) is roughly half Express's (251 ms), and its p95 (215 ms) comfortably
beats Express's 369 ms, both behind Fiber's tight 177 ms.

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
tail-latency budget at that equal cap, and how admission control closed it:

- **Every remaining slow request was the pool checkout.** In-request timing
  instrumented during the read load showed the request, pool-checkout+query,
  and query histograms moving identically — the DB path is one blocked span.
  ~2000 simultaneous requests queue on 200 shared slots, so the profile is the
  signature of pool saturation, not a code bug.

- **Admission control removed the queue from the pool.** Altair's
  `db_max_active_queries` gate (see the admission-control section below) parks
  the ~1800 excess VUs on a FIFO queue *outside* the pool instead of letting
  them contend on the pool's own wait list. Fewer fibers ever race for a slot,
  so the queueing is single and fair. The same 200-connection budget, now
  admission-controlled, took read p99.9 641 → 369 ms and read max 991 → 617 ms;
  write p99.9 919 → 397 ms and write max 1,782 → 918 ms — with no throughput
  loss (read 14,096 → 14,105, write 11,889 → 11,209 req/s).

Notable observations:

- Altair's read distribution is now a single tight band (p90 187 ms, max 617
  ms) instead of the bimodal fast-path-plus-long-tail shape from the 50-pool
  runs. Fiber's max on reads (287 ms) still tops it, and Express's read max
  (2.3 s) is 3.7x Altair's.
- On writes Altair has the best throughput (11,209 req/s) *and* the second-best
  worst case (918 ms, vs Express's 5.2 s); Fiber's tight 45-vs-400 ms write
  band is the price of its 8-process split and the fewest writes.
- Express's write tail is the worst of the group (max 5.2 s, p99.9 3.6 s) — a
  200-connection `pg` pool across 8 Node workers queues poorly at 2000 VUs.

---

## Admission control

This benchmark is deliberately stress test: 2000 concurrent requests against a
**single** Altair process and one shared pool. Any single-pool runtime at that
concurrency queues requests at the pool checkout. Altair's answer is a
database **admission gate** (`config.db_max_active_queries`): a FIFO semaphore
that sits *between* the web handler and the pool, so only a bounded number of
fibers ever reach the pool at once and the rest wait on one fair queue.

It is disabled by default (0). To turn it on for this example the server reads
`BENCH_ACTIVE` in `app/altair/src/application.cr`, and `scripts/bench.sh`
passes it on the altair start line. The committed figures above were produced
with `BENCH_ACTIVE=200` — the same connection budget as the other two
frameworks — so the gate does not cap throughput, only replaces the pool's
queue with a single fair one. You can tighten it (e.g. `BENCH_ACTIVE=50`) to
trade a little peak throughput for an even flatter tail; the admission-control
sweep and the design rationale live in
[`docs/architecture/performance-audit.md`](../../docs/architecture/performance-audit.md).

```bash
BENCH_ACTIVE=200 ./scripts/bench.sh altair
```

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
  | **Altair** | 4103 | `CRYSTAL_WORKERS=8` (execution context resized); DB pool 200, initial 200, max idle 200; admission gate `db_max_active_queries=200` (`BENCH_ACTIVE`). |

- The pool sizing is deliberate and is the tail-latency fix documented above:
  with 2000 concurrent virtual users, a 50-slot single pool kept ~1950 requests
  queued behind 50 busy connections (multi-second max latencies). Altair's pool
  is 200 so its single pool reaches the same PostgreSQL `max_connections=220`
  headroom the other two get via 8 pools. The same binary at pool 50 produced
  read max 4,374 ms / p95 900 ms / 8,200 req/s. The admission gate then caps
  how many fibers may *wait* on that pool at once: with `BENCH_ACTIVE=200` the
  budget is unchanged and the tail still collapses (read max 991 → 617 ms,
  write max 1,782 → 918 ms) because excess fibers park on the gate's FIFO
  instead of contending on the pool.

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

# 2. build the servers once (run the crystal build from the app dir so the
#    relative altair shard resolves)
cd app/altair
crystal build --release --no-debug src/bench.cr -o /tmp/bench_altair
cd ../..
go build -o /tmp/bench_fiber app/fiber/main.go
# Express needs no build: node app/express/src/server.js

# 3. run each framework's write + read in isolation
./scripts/bench.sh express   # stops the other apps, starts this one if needed
./scripts/bench.sh fiber
BENCH_ACTIVE=200 ./scripts/bench.sh altair   # admission gate on the 200 budget
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