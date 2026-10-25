# Altair Benchmark Report

A load test that compares **Altair** (Crystal) against **Express** (Node.js),
**Fiber** (Go) and a **Ruby** (Puma + ActiveRecord) app on identical
PostgreSQL-backed CRUD endpoints, driven by k6 over real HTTP.

The current committed results live in [`examples/benchmark_k6/results/`](examples/benchmark_k6)
as k6 summary exports. The short version, at the unified realistic profile
(**100 virtual users, 60 seconds, 20 database connections, 6 workers each**):

- **Write** (POST `/items`): Fiber leads at **22,080 req/s**. Altair sustains
  **17,245 req/s** (**1.71x Express**, 0.78x Fiber) — with the **best tail of
  all four**: p99.9 of 10.7 ms and a max of 18.1 ms.
- **Read** (GET `/items/:id`): Fiber leads at **20,908 req/s**. Altair sustains
  **15,539 req/s** (**1.63x Express**, 0.74x Fiber), p99 of 14.6 ms.
- **Zero meaningful failures** across all eight runs (17 warmup-boundary
  resets on the Express write run; 2 on the Ruby write run).

### The official collector: gcry (interleaved A/B)

Altair adopts [gcry](https://github.com/sdogruyol/gcry) 0.38.0 as its
official collector. The committed tables above are the default build
(bundled Boehm); with `-Dgc_none` the same app swaps collectors with no
code change. Interleaved A/B, medians of three rounds per arm, unique
server processes:

| Workload | Collector | rps | p95 | p99 | p99.9 | max |
|---|---|---:|---:|---:|---:|---:|
| Write | Boehm | 15,335 | 11.4 | 12.7 | **14.9** | **21.3** |
| Write | gcry 0.38.0 | 15,292 | 11.4 | 12.7 | 15.6 | 26.7 |
| Read | Boehm | 14,571 | 12.3 | 15.7 | 25.1* | 60.1* |
| Read | gcry 0.38.0 | **14,958** | **12.2** | **14.8** | **22.4** | **36.3** |

*Boehm medians look acceptable only because two of three rounds landed
clean windows; its third round exploded to 123.5 / 482.2 ms - the
intermittent dirty window this whole investigation chased. gcry never
dirtied: worst round 23.3 / 37.9 ms. Full evidence:
`gcry-results.md` and `read-tail-investigation.md`.

These numbers are from a **sustained-load measurement** (see
[Methodology](#methodology)): a discarded k6 warm-up run first ramps the target
to 100 virtual users and absorbs the cold-start spike, then the measured run
holds **100 virtual users for 60 seconds** at the same **20-connection /
6-worker budget**, with PostgreSQL pinned to **6 CPUs / 2 GB** — enough DB
headroom that throughput is framework-limited, so per-request cost, not pool
starvation, is what's measured. They were produced after the benchmark and
database-path fixes described below:

1. **ORM/DB-layer hardening** (see [`CHANGELOG.md`](CHANGELOG.md)):
   the query path no longer pays a global mutex per statement outside
   transactions, per-statement timing is skipped when no instrumentation hook is
   registered, and the `SELECT` prefix is a compile-time constant.
2. **Pool right-sizing** — 20 connections served 98.5% of the 200-connection
   throughput at 100 VUs with a better tail, so the unified profile gives every
   framework the same realistic 20-connection / 6-worker budget.
3. **Admission control** — `db_max_active_queries` parks the excess VUs on a
   FIFO queue *outside* the pool so the tail stays bounded.
4. **Prepared statements for the Go side (the one that reshuffled the result).**
5. **Altair request-path hardening**: benchmark-only request logging was removed,
   SQL/decode timing was separated, PostgreSQL statements are named and reused,
   and the configured PostgreSQL statement timeout is sent at connection startup.
6. **PostgreSQL wire-protocol fix** (issue #21): a reentrant per-connection
   lock keeps an extended-query exchange from interleaving under concurrency,
   and frame-unsynced connections are discarded instead of recycled dirty.


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

The full picture at the unified profile, all four arms (the official
gcry session - one interleaved run window, every arm a fresh process,
zero failed requests; raw exports under `results/official-gcry/`):

| Framework | Write req/s | Write p95 | Write p99 | Write p99.9 | Write max | Read req/s | Read p95 | Read p99 | Read max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fiber | **20,300** | **7.3 ms** | **9.8 ms** | **16.3 ms** | 36.8 ms | **18,990** | **8.2 ms** | **12.1 ms** | **31.4 ms** |
| **Altair (gcry)** | 13,981 | 11.9 ms | 13.8 ms | 17.0 ms | **25.2 ms** | 13,619 | 13.0 ms | 16.6 ms | 37.2 ms |
| Express | 8,074 | 18.1 ms | 23.2 ms | 33.1 ms | 65.5 ms | 7,671 | 20.7 ms | 28.0 ms | 91.0 ms |
| Ruby | 2,213 | 376.6 ms | 407.0 ms | 471.2 ms | 1,071.6 ms | 2,975 | 281.6 ms | 313.6 ms | 1,046.7 ms |

Notes on the picture:

- **Altair's write max (25.2 ms) is the best of all four arms** - below
  even Fiber's 36.8 ms - and the read tail is deterministic (37.2 ms
  max, no intermittent window; the official gcry collector removed it).
- **The Ruby arm's median is fast but its tail collapses behind worker
  queueing**: 6 Puma workers x 3 threads serialize under load, so p95
  lands near 300 ms. That is the honest shape of the Ruby stack at this
  profile - the same `BENCH_WORKERS` / `BENCH_POOL` budget every arm gets.
- The earlier committed session (bundled-Boehm build, faster host window)
  is preserved in git history; this is the current official comparison
  under the official collector.

**Status: this benchmark is experimental.** Altair is still under active
development, and these numbers are a snapshot of where the framework stands
today. Real-world performance can vary with workload, hardware, and tuning; we
expect Altair to improve further as the framework matures. Treat the results
here as directional, not as a final verdict.

---


### Read workload — `GET /items/:id`

Primary-key lookups against 10,000 seeded rows. 100 VUs, 60 s, after a
discarded warm-up.

| Framework | Requests | Throughput | Avg | p50 | p90 | p95 | p99 | p99.9 | Max | Failed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Fiber | 1,218,075 | **20,300 req/s** | **4.7 ms** | **4.5 ms** | **6.4 ms** | **7.3 ms** | **9.8 ms** | **16.3 ms** | 36.8 ms | 0% |
| **Altair (gcry)** | **838,913** | **13,981 req/s** | 7.0 ms | 6.5 ms | 9.3 ms | 11.9 ms | 13.8 ms | 17.0 ms | **25.2 ms** | 0% |
| Express | 484,518 | 8,074 req/s | 12.1 ms | 11.7 ms | 16.3 ms | 18.1 ms | 23.2 ms | 33.1 ms | 65.5 ms | 0% |
| Ruby | 135,052 | 2,213 req/s | 44.5 ms | 7.2 ms | 17.0 ms | 376.6 ms | 407.0 ms | 471.2 ms | 1,071.6 ms | 0% |

Fiber leads write throughput. Altair carries **the best write max of all
four arms** (25.2 ms, below Fiber's 36.8 ms) with a p99.9 of 17.0 ms
statistically level with Fiber's 16.3 ms - every run error-free.

### Relative throughput

| Comparison | Read | Write |
|---|---:|---:|
| Altair vs Express | 1.78x | 1.73x |
| Altair vs Fiber | 0.72x | 0.69x |
| Altair vs Ruby | 4.58x | 6.31x |
| Fiber vs Express | 2.47x | 2.51x |

### Data moved

| Framework | Scenario | Received | Sent |
|---|---:|---:|---:|
| Altair | read | 144 MB / 2.4 MB/s | 75 MB / 1.2 MB/s |
| Altair | write | 133 MB / 2.2 MB/s | 172 MB / 2.9 MB/s |
| Express | read | 160 MB / 2.7 MB/s | 46 MB / 0.76 MB/s |
| Express | write | 152 MB / 2.5 MB/s | 100 MB / 1.7 MB/s |
| Fiber | read | 191 MB / 3.2 MB/s | 100 MB / 1.7 MB/s |
| Fiber | write | 167 MB / 2.8 MB/s | 220 MB / 3.7 MB/s |
| Ruby | read | 103 MB / 1.7 MB/s | 17 MB / 0.28 MB/s |
| Ruby | write | 71 MB / 1.2 MB/s | 26 MB / 0.43 MB/s |

---


## Analysis

**Altair beats Express and Ruby on throughput in both workloads, while Fiber
leads both.** Altair sustains **17,245 write req/s** and **15,539 read req/s**.
Its average and p95 latency are lower than Express's in both cases, and its
write tail (p99.9 / max) is the tightest of all four arms.

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

- Altair's read throughput was 15,539 req/s, between Fiber at 20,908 req/s and
  Express at 9,532 req/s. Its p95 was 8.4 ms, below Express's 15.6 ms.
- On writes Altair sustained 17,245 req/s, ahead of Express at 10,074 req/s and
  behind Fiber at 22,080 req/s. Altair's p99.9 / max (10.7 / 18.1 ms) were the
  tightest write tail of the four arms.
- The Ruby arm completes the picture at 2,587 write / 3,531 read req/s: the
  fastest per-request median of the four once a request reaches a worker, with
  a tail that queues behind its worker budget.
- All four arms completed their runs error-free apart from 17 warmup-boundary
  resets (Express write) and 2 (Ruby write).

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
  `items_altair`, `items_ruby`). The 6-CPU allocation keeps PostgreSQL clear of the
  framework ceiling — earlier runs with 2 CPUs capped the whole benchmark at
  ~8.4k req/s regardless of framework or pool size.
- The applications run **natively on the host** (no container overhead),
  one per port, each limited to the same connection budget and worker count
  (`BENCH_POOL` / `BENCH_WORKERS`, defaulting to 20 / 6 — the realistic
  profile tuned on this machine; override via env for stress reruns).
  Express runs a cluster of `BENCH_WORKERS` processes, Fiber maps
  `BENCH_WORKERS` to `GOMAXPROCS`, Altair maps it to `CRYSTAL_WORKERS`, and
  the Ruby arm maps it to Puma workers. The Ruby arm's app lives under
  `app/ruby/`, gitignored by repo policy — generate it locally before
  running `scripts/bench.sh ruby`.

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
# Default (bundled Boehm):
crystal build --release --no-debug src/bench.cr -o /tmp/bench_altair
# Official collector (gcry):
crystal build --release --no-debug -Dgc_none src/bench.cr -o /tmp/bench_altair
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
