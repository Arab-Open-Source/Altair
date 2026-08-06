# Altair Benchmark Report

A load test that compares **Altair** (Crystal) against **Express** (Node.js) and
**Fiber** (Go) on identical PostgreSQL-backed CRUD endpoints, driven by k6 over
real HTTP.

The current committed results live in [`results/`](results/) as k6 summary
exports. The short version:

- **Write** (POST `/items`): Fiber leads at **17,088 req/s**. Altair sustains
  **13,167 req/s** (**1.81x Express**, 0.77x Fiber), with a p99.9 of 145.9 ms.
- **Read** (GET `/items/:id`): Fiber leads at **19,527 req/s**. Altair sustains
  **14,687 req/s** (**1.91x Express**, 0.75x Fiber). Altair's average is
  64.3 ms, with a p95 of 129.0 ms and a maximum of 479.6 ms.
- **Zero failed requests** across all six runs; every `status is 200/201` check
  passed.

These numbers are from a **sustained-load measurement** (see
[Methodology](#methodology)): a discarded k6 warm-up run first ramps the target
to 1,000 virtual users and absorbs the cold-start spike, then the measured run
holds **1,000 virtual users for 60 seconds** at the same **200-connection
budget**, with PostgreSQL pinned to **6 CPUs / 2 GB** — enough DB headroom that
throughput is framework-limited, so per-request cost, not pool starvation, is
what's measured. They were produced after the benchmark and database-path fixes
described below:

1. **ORM/DB-layer hardening** (see [`CHANGELOG.md`](../../CHANGELOG.md)):
   the query path no longer pays a global mutex per statement outside
   transactions, per-statement timing is skipped when no instrumentation hook is
   registered, and the `SELECT` prefix is a compile-time constant.
2. **Pool fairness** — the original altair build capped its single pool at 50
   slots while presenting 2,000 concurrent requests, so ~1,950 requests queued
   behind 50 busy connections (multi-second tails). The pool is now 200 so its
   one shared pool reaches the same PostgreSQL `max_connections=220` headroom
   the other two get via 8 worker pools.
3. **Admission control** — `db_max_active_queries` parks the excess VUs on a
   FIFO queue *outside* the pool so the tail stays bounded.
4. **Prepared statements for the Go side (the one that reshuffled the result).**
5. **Altair request-path hardening**: benchmark-only request logging was removed,
   SQL/decode timing was separated, PostgreSQL statements are named and reused,
   and the configured PostgreSQL statement timeout is sent at connection startup.

### The prepared-statement finding

When this example was first audited, **Fiber was the slowest writer — but it was
unfairly handicapped by its own stack.** pgx v5's default exec mode runs a
`Describe` round-trip on every `QueryRow`, so each `INSERT ... RETURNING id` cost
two network round-trips instead of one. At 1,000 VUs that doubled the DB-path
cost and capped Fiber at **~5,460 write req/s** with **~408 ms max**.

The fix is the pgx best practice: parse the config once, then prepare the
statements on each physical connection in an `AfterConnect` hook, and reuse the
named statements in the handlers.

```go
config.AfterConnect = func(ctx context.Context, conn *pgx.Conn) error {
    if _, err := conn.Prepare(ctx, "insert_item", insertQuery); err != nil {
        return err
    }
    if _, err := conn.Prepare(ctx, "select_item", selectQuery); err != nil {
        return err
    }
    return nil
}
```

In the earlier 90-second comparison, that change took Fiber from **5,460 →
14,154 write req/s** (2.6×) and cut its write max **408 → 234 ms** — Fiber then
led every workload. It is a good
reminder that a runtime's *defaults* can look like a framework deficit until the
driver is configured, and it is why this report audits each app's DB path, not
just its HTTP layer.

With these fixes in place the latest picture is now:

- **Write** (`POST /items`): **Fiber** leads at 17,088 req/s, Altair 13,167
  req/s (**1.81x Express**, 0.77x Fiber), Express 7,273 req/s. Altair's p95 is
  101.3 ms, its p99.9 is 145.9 ms.
- **Read** (`GET /items/:id`): **Fiber** leads at 19,527 req/s, Altair 14,687
  req/s (**1.91x Express**, 0.75x Fiber), Express 7,700 req/s. Altair's p95 is
  129.0 ms, its p99.9 is 318.4 ms.
- **Zero failed requests** across all six runs; every `status is 200/201`
  check passed.

**Status: this benchmark is experimental.** Altair is still under active
development, and these numbers are a snapshot of where the framework stands
today. Real-world performance can vary with workload, hardware, and tuning; we
expect Altair to improve further as the framework matures. Treat the results
here as directional, not as a final verdict.

---

## Results

All figures below are from the latest fair runs: **every framework gets the
same 200-connection budget** against PostgreSQL, 60-second sustained load at
1,000 VUs. A discarded k6 warm-up run precedes each phase, so the summaries
measure **sustained load only** — cold-start effects are excluded (see
[Methodology](#methodology)).

### Read workload — `GET /items/:id`

Primary-key lookups against 10,000 seeded rows.

| Framework | Requests | Throughput | Avg | p50 | p90 | p95 | p99 | p99.9 | Max | Failed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fiber | 1,171,974 | 19,527 req/s | 37.1 ms | 35.1 ms | 60.4 ms | 71.7 ms | 103.5 ms | 149.9 ms | 236.3 ms | 0% |
| **Altair** | **881,772** | **14,687 req/s** | **64.3 ms** | **58.2 ms** | 101.2 ms | 129.0 ms | 180.4 ms | 318.4 ms | 479.6 ms | 0% |
| Express | 462,813 | 7,700 req/s | 127.3 ms | 122.7 ms | 172.9 ms | 197.3 ms | 267.3 ms | 350.3 ms | 965.8 ms | 0% |

Altair keeps a fixed ~1.7x gap to Fiber on the read side (p90 101.2 vs
60.4 ms). Its own tail is tight from p99 up (180.4 ms) and stays flat until the
per-second GC pause lands on in-flight requests; Express's max (965.8 ms) shows
the same artifact worse.

### Write workload — `POST /items`

One row inserted and committed per request (JSON body).

| Framework | Requests | Throughput | Avg | p50 | p90 | p95 | p99 | p99.9 | Max | Failed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fiber | 1,025,953 | 17,088 req/s | 57.0 ms | 53.5 ms | 77.3 ms | 94.3 ms | 131.7 ms | 171.5 ms | 242.4 ms | 0% |
| **Altair** | **790,920** | **13,167 req/s** | **75.4 ms** | **73.1 ms** | 94.5 ms | 101.3 ms | 117.8 ms | 145.9 ms | 201.5 ms | 0% |
| Express | 436,805 | 7,273 req/s | 133.8 ms | 124.7 ms | 198.2 ms | 232.1 ms | 302.8 ms | 1036.8 ms | 2067.8 ms | 0% |

Fiber leads the write throughput at the same pool budget. Altair remains faster
than Express and now carries the cleanest write tail of the three: its p99
(117.8 ms) and max (201.5 ms) are *below* Fiber's, and its p99.9 (145.9 ms) is
7x tighter than Express's (1,036.8 ms). The Wave-D2 SQL template cache halved
the write-path allocations (frozen-GC harness: `Item.create` 2,033 → 964 B/op),
which dropped the write max from 429.6 → 201.5 ms; the remaining outlier is one
GC stop-the-world pause per second under sustained load (see
[The tail-latency investigation](#the-tail-latency-investigation)).

### Relative throughput

| Comparison | Read | Write |
|---|---:|---:|
| Altair vs Express | 1.91x | 1.81x |
| Altair vs Fiber | 0.75x | 0.77x |
| Fiber vs Express | 2.54x | 2.35x |

### Data moved

| Framework | Scenario | Received | Sent |
|---|---:|---:|---:|
| Altair | read | 136.3 MB / 2.27 MB/s | 70.4 MB / 1.17 MB/s |
| Altair | write | 101.2 MB / 1.69 MB/s | 131.0 MB / 2.18 MB/s |
| Express | read | 129.4 MB / 2.15 MB/s | 37.0 MB / 0.62 MB/s |
| Express | write | 110.0 MB / 1.83 MB/s | 72.2 MB / 1.20 MB/s |
| Fiber | read | 178.8 MB / 2.98 MB/s | 93.6 MB / 1.56 MB/s |
| Fiber | write | 129.4 MB / 2.16 MB/s | 170.0 MB / 2.83 MB/s |

---

## Analysis

**Altair beats Express on throughput in both workloads, while Fiber leads both.**
Altair sustains **13,167 write req/s** and **14,687 read req/s**. Its average
and p95 latency are lower than Express in both cases in this run, and its write
tail (p99 / p99.9 / max) is tighter than Fiber's.

### The Wave-D measurement pass (cold start vs. sustained load)

The previous committed figures (and this one's `results/archive-fair-runs/`)
were produced with a **single k6 `ramping-vus` scenario whose summary included
the warm-up ramp**. Instrumenting Altair per-second (GC heap + collections,
pool state, request latency; see `scripts/sample_pg.sh` and the `--define
bench_sample` build in `app/altair/src/bench_sample.cr`) showed where the
worst tail actually lives:

- The **entire ~900 ms write outlier happened in the first second** of the
  ramp: 198 requests at avg 401 ms / max 883 ms while the pool's 200
  connections and prepared statements came up under a VU burst (PostgreSQL
  momentarily saw 131 active connections). From second two on, the run is
  flat: per-second average ~65-75 ms, per-second max 108-158 ms, and the GC
  heap **plateaus at ~191 MB** (it does not grow across the 60 s — the
  late-run degradation hypothesis is disproved).
- PostgreSQL is nowhere near saturation: ~201 backends with **1-2 active**,
  ~13 k commits/s, and zero wait events through the sustained phase.
- The cold-start hypothesis was confirmed by pre-firing: warming the pool with
  30 POSTs first moved the ~860 ms spike into the pre-fire window and the
  measured run stayed flat (max 30-66 ms per second).

So the benchmark now **separates warm-up from measurement**: each phase runs a
discarded `ramping-vus` warm-up (5 s ramp to 1,000 VUs + 3 s settle), then the
measured `constant-vus` run at 1,000 VUs for 60 s (`MODE=warmup|load` in
`k6/write.js` / `k6/read.js`). That removed the cold-start artifact from the
summaries: Altair's write max dropped **873.1 → 201.5 ms** and its read max
(286.7 → 479.6 ms) is now pure sustained behavior, not warm-up.

What remains in the sustained summaries is one **GC stop-the-world pause per
second** (Boehm full collection on the ~190 MB plateau): the per-second max of
108-158 ms coincides one-for-one with the collection counter, and the p99.9 /
max values (145.9 / 201.5 ms write, 318.4 / 479.6 ms read) are the pauses
landing on in-flight requests. The Wave-D2 SQL template cache
(`Model`/`Connection#sql_template`) halved the write-path cost (frozen-GC
harness, PostgreSQL: `Item.create` 2,033 → 964 B/op, `Item.find` 1,378 →
1,060 B/op), which pulled the write tail back under the pause: Altair's write
p99.9 is now tighter than Fiber's and its write max beats both. The read side
still allocates more per request (JSON response building dominates), so its
outliers land inside the same pause windows; cutting read-side allocations is
the next lever.

### The tail-latency investigation

The original runs after the ORM hardening showed an alarming shape: Altair's
read median was **8 ms** but its max was **2.4 s** (later **4.4 s**). A
no-database `/health` probe under the identical 2000-VU load capped at **355 ms
max and 76 ms p95 at ~40,725 req/s**, proving the HTTP/scheduler layer was
healthy and the delay lived in the database path. The candidate causes were
eliminated one by one with experiments:

- **Not PostgreSQL**: primary-key lookups measured ~2 ms; the database was not
  the source of the framework-side tail in the isolated probes.
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
200 and left Express/Fiber at 50, which over-drew Altair. The latest figures in
this document come from **the same 200-connection budget for all three**. The
tail-latency profile at that equal cap is:

- **Every remaining slow request was the pool checkout.** In-request timing
  instrumented during the read load showed the request, pool-checkout+query,
  and query histograms moving identically — the DB path is one blocked span.
  ~800 excess requests queue behind 200 shared slots, so the profile is the
  signature of pool saturation, not a code bug.

- **Admission control bounds the queue outside the pool.** Altair's
  `db_max_active_queries` gate (see the admission-control section below) parks
  the excess VUs on a FIFO queue *outside* the pool instead of letting them
  contend on the pool's own wait list. Fewer fibers ever race for a slot,
  so the queueing is single and fair. In the latest run it completed all six
  workloads with zero failed requests.

Notable observations:

- Altair's read throughput was 14,687 req/s, between Fiber at 19,527 req/s and
  Express at 7,700 req/s. Its p95 was 129.0 ms, below Express's 197.3 ms.
- On writes Altair sustained 13,167 req/s, ahead of Express at 7,273 req/s and
  behind Fiber at 17,088 req/s. Altair's p95 was 101.3 ms, and its p99 / p99.9 /
  max (117.8 / 145.9 / 201.5 ms) were the tightest write tail of the three.
- Fiber had the best read tail (236.3 ms max); Altair's write max (201.5 ms)
  beat both Fiber (242.4 ms) and Express (2,067.8 ms). All three applications
  completed the runs without failed requests.

---

## Admission control

This benchmark is deliberately a stress test: 1,000 concurrent requests against a
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
  With 1,000 concurrent virtual users, a 50-slot single pool would keep ~800
  requests queued behind 50 busy connections (multi-second max latencies).
  Altair's pool
  is 200 so its single pool reaches the same PostgreSQL `max_connections=220`
  headroom the other two get via 8 pools. The same binary at pool 50 produced
  read max 4,374 ms / p95 900 ms / 8,200 req/s. The admission gate then caps
  how many fibers may *wait* on that pool at once: with `BENCH_ACTIVE=200` the
  budget is unchanged and excess fibers park on the gate's FIFO queue
  instead of contending on the pool.

- Every app is started with `ulimit -n 65535`. In an earlier 2000-VU run, the
  default soft limit of 1024 file descriptors caused Altair to log 9.5 million
  `accept: Too many open files` errors, which collapsed
  throughput and produced a pathological bimodal latency. Express and Fiber
  tolerate EMFILE silently; Altair's server does not.

### Load profile

Each phase runs **two** k6 scenarios against the same script (`MODE` env):

| Phase | Scenario | Duration | Virtual users | Summary |
|---|---|---|---|---|
| Warm-up | `ramping-vus` | 5 s ramp + 3 s settle | 1 → 1000 | discarded |
| Measured | `constant-vus` | 60 s | 1000 | exported |

- The warm-up run absorbs the cold-start spike (pool + prepared statements +
  GC heap storm in the first seconds), so the exported summary describes
  sustained load only. This is what removed Altair's 873.1 ms write outlier
  (see [The Wave-D measurement pass](#the-wave-d-measurement-pass-cold-start-vs-sustained-load)).
- **Read**: one random seeded row (`id` in 1..10,000) per request, asserting
  `status is 200`.
- **Write**: one JSON insert per request, asserting `status is 201`.
- Threshold: `http_req_failed: rate<0.005`.

### Fairness and caveats

- All three runtimes are tuned symmetrically **to the same 200-connection
  budget** wherever the architecture allows (8 workers / processes, pool 200,
  60-second sustained load at 1,000 VUs). There is no untuned baseline and no
  framework gets more than its peers.
- All three share the **same single PostgreSQL instance** (220 connections).
  At this load the database is a shared ceiling, so the numbers describe the
  *combined* stack, not raw framework throughput.
- The host runs PostgreSQL, k6, and the application together; the tail latencies
  reflect core contention on the host, not just framework behavior.
- Numbers are per-run samples, not averages across repeated runs. Treat them as
  indicative; rerun locally (below) for confidence on your own hardware. The
  host's state (thermal/other load) shifts absolute values between days; the
  relative ordering has been stable across sessions.

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
VUS=1000 DURATION=60 ./scripts/bench.sh express
VUS=1000 DURATION=60 ./scripts/bench.sh fiber
VUS=1000 DURATION=60 BENCH_ACTIVE=200 ./scripts/bench.sh altair
```

`scripts/bench.sh <express|fiber|altair>` stops the other two apps, starts the
target with `ulimit -n 65535` and its tuned environment if it is not already
up, truncates the table, runs the k6 warm-up + write phase, reseeds, then runs
the k6 warm-up + read phase. It stops the other two apps so each framework
runs alone. Results land in
`results/<framework>-write.json` / `results/<framework>-read.json`; each app's
log is in `/tmp/bench_<name>.log`.

Tune the load profile with the `VUS` and `DURATION` environment variables (the
exact run above uses `VUS=1000 DURATION=60`) or the options documented in
[`k6/README.md`].

`scripts/run.sh` is an alternative containerized runner that boots all three
apps in compose; the numbers above were produced by the host-native `bench.sh`
path and may differ from the containerized one.

---

## Layout

```
app/altair/     Altair server (bench.cr, application.cr, bench_sample.cr, ItemsController)
app/express/    Express reference server (node cluster)
app/fiber/      Fiber reference server (GOMAXPROCS + pgx pool)
db/init.sql     One table per framework
k6/read.js      Read load script (random PK lookup; MODE=warmup|load)
k6/write.js     Write load script (single-row insert; MODE=warmup|load)
k6/echo.js      No-DB load script (GET /health) used to isolate the HTTP layer
scripts/bench.sh       Host-native runner (isolation + ulimit + warmup + write/read)
scripts/run.sh         Containerized runner (compose)
scripts/summary.sh     Renders results/*.json as markdown tables
scripts/sample_pg.sh   Per-second PostgreSQL sampler for tail-latency diagnosis
scripts/diagnose.sh    Sampled run: GC heap + pool + PG CSVs under the k6 load
results/               k6 summary JSON exports
```
