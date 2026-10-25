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
| **Write** `POST /items` | <img src="/assets/img/logos/go.svg" width="16" alt="Go"> Fiber | 20,300 | 4.7 ms | **7.3 ms** | **9.8 ms** | **16.3 ms** | 36.8 ms |
| | <img src="/assets/img/logos/crystal.svg" width="16" alt="Crystal"> **Altair (gcry)** | **13,981** | 7.0 ms | 11.9 ms | 13.8 ms | 17.0 ms | **25.2 ms** |
| | <img src="/assets/img/logos/nodejs.svg" width="16" alt="Node.js"> Express | 8,074 | 12.1 ms | 18.1 ms | 23.2 ms | 33.1 ms | 65.5 ms |
| | <img src="/assets/img/logos/ruby.svg" width="16" alt="Ruby"> Ruby full-stack | 2,213 | 44.5 ms | 376.6 ms | 407.0 ms | 471.2 ms | 1,071.6 ms |
| **Read** `GET /items/:id` | <img src="/assets/img/logos/go.svg" width="16" alt="Go"> Fiber | 18,990 | 5.1 ms | **8.2 ms** | **12.1 ms** | **18.9 ms** | **31.4 ms** |
| | <img src="/assets/img/logos/crystal.svg" width="16" alt="Crystal"> **Altair (gcry)** | **13,619** | 7.2 ms | 13.0 ms | 16.6 ms | 25.9 ms | 37.2 ms |
| | <img src="/assets/img/logos/nodejs.svg" width="16" alt="Node.js"> Express | 7,671 | 12.8 ms | 20.7 ms | 28.0 ms | 41.0 ms | 91.0 ms |
| | <img src="/assets/img/logos/ruby.svg" width="16" alt="Ruby"> Ruby full-stack | 2,975 | 33.1 ms | 281.6 ms | 313.6 ms | 347.7 ms | 1,046.7 ms |

One interleaved session, every arm a fresh process, zero failed requests.
**Altair's write max (25.2 ms) is the best of all four frameworks** -
tighter than Fiber's 36.8 ms - and its read tail is deterministic on the
official gcry collector (no intermittent window; see the gcry section).
Altair holds ~1.7-1.8x Express on throughput.

## The official collector: gcry

Altair ships [gcry](https://github.com/sdogruyol/gcry) as its official
garbage collector. The tables above are the default build (bundled
Boehm); building with a single flag — `-Dgc_none` — swaps the collector
with no code change. A root-cause investigation traced Boehm's
intermittent read-tail spike (p99.9 up to 154 ms on unlucky runs) to
stop-the-world pauses that scale with heap size; gcry removes the spike
deterministically.

Interleaved A/B, medians of three rounds per arm:

| Workload | Collector | rps | p99 | p99.9 | max |
|---|---|---:|---:|---:|---:|
| Write | Boehm | 15,335 | 12.7 ms | **14.9 ms** | **21.3 ms** |
| Write | gcry 0.38.0 | 15,292 | 12.7 ms | 15.6 ms | 26.7 ms |
| Read | Boehm | 14,571 | 15.7 ms | 25.1 ms* | 60.1 ms* |
| Read | gcry 0.38.0 | **14,958** | **14.8 ms** | **22.4 ms** | **36.3 ms** |

*The Boehm read medians flatter it: one of its three rounds exploded to
123.5 / 482.2 ms — the intermittent dirty window. gcry's worst round was
23.3 / 37.9 ms. Write throughput is at parity (earlier gcry versions
paid an 11 percent write penalty; 0.38.0 removed it).

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
