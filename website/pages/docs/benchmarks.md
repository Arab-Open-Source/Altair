# Benchmarks

Altair is compared against **Express** (Node.js), **Fiber** (Go) and a
**Ruby** full-stack MVC app on identical PostgreSQL-backed CRUD endpoints,
driven by k6 over real HTTP. The harness lives in the repository at
`examples/benchmark_k6` and can be re-run locally.

Every framework gets the same **20-connection / 6-worker budget** at the
realistic profile — **100 virtual users for 60 seconds** — tuned on the
benchmark machine; a discarded k6 warm-up run precedes each measured phase.
PostgreSQL is pinned to 6 CPUs / 2 GB — enough headroom that throughput is
framework-limited, so per-request cost is what is measured.

## Results — unified profile (100 VUs, 60 s, 20 connections, 6 workers)

| Workload | Framework | req/s | avg | p95 | p99 | p99.9 | max |
|---|---|---:|---:|---:|---:|---:|---:|
| **Write** `POST /items` | Fiber | 22,080 | 4.3 ms | 6.1 ms | 8.5 ms | 14.7 ms | 24.8 ms |
| | **Altair** | **17,245** | 5.7 ms | 7.3 ms | 8.6 ms | **10.7 ms** | **18.1 ms** |
| | Express | 10,074 | 9.7 ms | 13.5 ms | 16.2 ms | 22.4 ms | 53.6 ms |
| | Ruby | 2,587 | 38.1 ms | 325.5 ms | 337.7 ms | 380.6 ms | 1,060 ms |
| **Read** `GET /items/:id` | Fiber | 20,908 | 4.6 ms | 7.0 ms | 10.4 ms | 15.8 ms | 25.1 ms |
| | **Altair** | **15,539** | 6.3 ms | 8.4 ms | 14.6 ms | 153.6 ms | 247.0 ms |
| | Express | 9,532 | 10.3 ms | 15.6 ms | 20.5 ms | 28.3 ms | 64.4 ms |
| | Ruby | 3,531 | 27.9 ms | 239.1 ms | 257.5 ms | 272.3 ms | 1,042 ms |

- **Altair's write tail is the best of all four arms** — p99.9 of 10.7 ms and
  a max of 18.1 ms, below even Fiber's, with a write p99 (8.6 ms) statistically
  tied with Fiber's (8.5 ms).
- **Fiber (Go) leads raw throughput** — the honest gap is 0.74–0.78x.
- Express showed 17 connection resets clustered at the warmup boundary of its
  write run; Ruby showed 2. Everything else was error-free across the eight
  runs.

## The closest architectural peer: the Ruby full-stack arm

The most instructive comparison is not the raw throughput table — it is the
arm built the same way Altair is. The Ruby arm is a **full-stack MVC
framework with the same shape**: an ORM writing every row per request,
convention-driven controllers, a batteries-included philosophy, and a real
production application server (Puma) in front of it. It is the closest thing
in this comparison to "what Altair replaces", and the two are architecturally
much closer to each other than either is to Fiber's hand-rolled raw-SQL
handlers or Express's minimal pg pool.

At the same connection and worker budget the results are:

| Metric | **Altair** | Ruby full-stack | Altair advantage |
|---|---:|---:|---:|
| Write throughput | 17,245 req/s | 2,587 req/s | **6.7x** |
| Read throughput | 15,539 req/s | 3,531 req/s | **4.4x** |
| Write p99 | 8.6 ms | 337.7 ms | **39x tighter** |
| Read p99 | 14.6 ms | 257.5 ms | **18x tighter** |
| Write max | 18.1 ms | 1,060 ms | **59x tighter** |

Honest reading of that table:

- The Ruby arm posts the **fastest per-request median of all four arms**
  (4.3 ms on reads) — once a request reaches a worker, the stack is quick.
  Its tail collapses because 6 Puma workers serialize the ORM work under
  load; that is the honest shape of the Ruby stack at this budget, not a
  misconfiguration. Scaling it means more worker processes and more database
  connections — a different trade than Altair's single process with one
  shared pool and compile-time templates.
- Altair gets its numbers from the same philosophy the Ruby arm embodies —
  an ORM on every request, no raw SQL shortcuts — so the gap measures the
  stack itself: compiled templates and queries, fibers over a threaded
  scheduler, and a database path that never blocks a second fiber on one
  connection (see the wire-protocol fix, issue #21, in the repository).

## Historical sessions

### Session 2026-09-09 — isolated databases (older profile)

The harness was previously run at a 200-connection budget, 1,000 VUs for 60 s,
with each framework against its own PostgreSQL container. Order matched the
baseline; those tables live in the repository report. The current reference
is the unified realistic profile above.

## Methodology

- One k6 warm-up run per phase (ramp + settle) precedes the measured
  `constant-vus` run, so the summaries describe sustained load only.
- The budget is identical for every framework: **20 database connections and
  6 workers** (Express: cluster workers splitting the pool; Fiber:
  `GOMAXPROCS` + `pgxpool` max; Altair: `CRYSTAL_WORKERS` + one shared pool;
  Ruby: Puma workers x threads). Override via env for stress reruns.
- Latency statistics: `avg, med, p(90), p(95), p(99), p(99.9), max`.
- Raw k6 summary exports are committed next to the harness in `results/`.

## Where this came from

The numbers are maintained together with the benchmark harness: see
`examples/benchmark_k6/README.md` for the full report — the tail-latency
investigation, the per-second GC pause measurement and the allocation
findings — and the repository's `CHANGELOG.md` for what changed between
measurement passes.
