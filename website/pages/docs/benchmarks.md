# Benchmarks

Altair is compared against **Express** (Node.js) and **Fiber** (Go) on
identical PostgreSQL-backed CRUD endpoints, driven by k6 over real HTTP. The
harness lives in the repository at `examples/benchmark_k6` and can be re-run
locally.

Every framework gets the same **200-connection database budget**. A discarded
k6 warm-up run first ramps each app to 1,000 virtual users and absorbs the
cold-start spike, then the measured run holds **1,000 VUs for 60 seconds**.
PostgreSQL is pinned to 6 CPUs / 2 GB — enough headroom that throughput is
framework-limited, so per-request cost is what is measured.

## Results

| Workload | Framework | req/s | avg | p95 | p99 | p99.9 | max |
|---|---|---:|---:|---:|---:|---:|---:|
| **Write** `POST /items` | Fiber | 17,088 | 57.0 ms | 94.3 ms | 131.7 ms | 171.5 ms | 242.4 ms |
| | **Altair** | **13,167** | **75.4 ms** | 101.3 ms | 117.8 ms | **145.9 ms** | **201.5 ms** |
| | Express | 7,273 | 133.8 ms | 232.1 ms | 302.8 ms | 1,036.8 ms | 2,067.8 ms |
| **Read** `GET /items/:id` | Fiber | 19,527 | 37.1 ms | 71.7 ms | 103.5 ms | 149.9 ms | 236.3 ms |
| | **Altair** | **14,687** | **64.3 ms** | 129.0 ms | 180.4 ms | 318.4 ms | 479.6 ms |
| | Express | 7,700 | 127.3 ms | 197.3 ms | 267.3 ms | 350.3 ms | 965.8 ms |

All six runs completed with **zero failed requests**.

## What the numbers say

- **Altair is ~1.8–1.9x faster than Express** on throughput in both
  workloads, with a far tighter tail: its write p99.9 (145.9 ms) is 7x lower
  than Express's and its write max (201.5 ms) is the best of all three.
- **Fiber (Go) leads raw throughput** — the honest gap is 0.75–0.77x.
  Altair's write tail is nevertheless tighter than Fiber's at every
  percentile from p99 up.
- **Altair's read tail runs ~2x Fiber's** (p99.9 318.4 / max 479.6 ms). The
  outliers land inside one Boehm stop-the-world pause per second on the
  plateaued heap; the next optimization target is read-side allocation
  (JSON response building dominates), and it is tracked as follow-up work.

## Methodology

- One k6 warm-up run per phase (ramp to 1,000 VUs + settle) precedes the
  measured `constant-vus` run, so the summaries describe sustained load only.
- The pool budget is the same for every framework: 200 connections total,
  matching PostgreSQL's `max_connections = 220` headroom (Express and Fiber
  split theirs across 8 workers; Altair uses one shared pool).
- Latency statistics: `avg, med, p(90), p(95), p(99), p(99.9), max`.
- Raw k6 summary exports are committed next to the harness in `results/`.

## Where this came from

The numbers are maintained together with the benchmark harness: see
`examples/benchmark_k6/README.md` for the full report — the tail-latency
investigation, the per-second GC pause measurement and the allocation
findings — and the repository's `CHANGELOG.md` for what changed between
measurement passes.
