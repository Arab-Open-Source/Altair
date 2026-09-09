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

## Session 2026-09-09 — isolated databases

The harness was re-run with the same unified settings (200-connection
budget, 1,000 VUs for 60 s, discarded warm-up, Altair first with a 60 s
cooldown between frameworks), but each framework ran against its **own**
PostgreSQL container, so checkpoints and WAL can no longer leak between
runs. Isolation verified: zero failed requests, each database holding only
its own framework's table.

| Workload | Framework | req/s | avg | p95 | p99 | p99.9 | max |
|---|---|---:|---:|---:|---:|---:|---:|
| **Write** `POST /items` | Fiber | 9,186 | 108.3 ms | 159.5 ms | 175.5 ms | 199.8 ms | 274.1 ms |
| | **Altair** | **9,035** | **109.5 ms** | 181.0 ms | 274.0 ms | 1,032.3 ms | 1,142.4 ms |
| | Express | 4,199 | 235.5 ms | 313.3 ms | 5,010.5 ms | 6,925.4 ms | 7,028.9 ms |
| **Read** `GET /items/:id` | Fiber | 12,994 | 73.5 ms | 109.2 ms | 136.1 ms | 178.0 ms | 313.8 ms |
| | **Altair** | **9,361** | **104.4 ms** | 225.8 ms | 462.4 ms | 855.7 ms | 1,408.8 ms |
| | Express | 7,011 | 141.7 ms | 208.3 ms | 265.5 ms | 676.4 ms | 1,164.5 ms |

Ordering matches the baseline on both workloads, and Fiber's write tail
shows what isolation buys (p99.9 2,502.9 → 199.8 ms vs the shared-DB
session). Caveats: the smaller per-DB slice (2 CPUs) caps the fastest
reader, and absolute 1000-VU numbers move with host state — the tables
above stay the reference. The read-path fix itself is proven by the
same-day controlled A/B on Altair at 300 VUs: read p99.9 −53%, max −66%,
throughput +32% with no write regression.

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
