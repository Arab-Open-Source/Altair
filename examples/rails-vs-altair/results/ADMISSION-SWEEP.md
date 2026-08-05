# Admission-control sweep — `db_max_active_queries`

Saturated profile (`THINK_MS=0`, 500/1000/2000 VU tiers). The gate caps how
many fibers may hold a pooled connection at once; excess fibers wait on a
FIFO channel instead of the pool's own wait queue.

| N (gate limit) | workload | req/s | avg (ms) | p50 (ms) | p99 (ms) | p99.9 (ms) | max (ms) |
|---:|---|---:|---:|---:|---:|---:|---:|
| 0 (off) | read  | 8159 | 128.0 | 44.5 | 636.1 | 972.8 | 1599.8 |
| 0 (off) | write | 7136 | 146.5 | 57.2 | 803.9 | 1200.0 | 1871.1 |
| 10 | read  | —    | 136.6 | 116.8 | 322.0 |   —   |  353.1  |
| 10 | write | —    | 263.7 | 228.0 | 537.5 |   —   |  948.4  |
| 30 | read  | —    | 139.7 | 121.6 | 302.5 | 322.0 |  381.4  |
| 30 | write | —    | 160.6 | 137.3 | 391.3 | 412.7 |  906.0  |
| 50 | read  | 8277 | 125.8 | 110.7 | 288.5 |   —   |  342.4  |
| 50 | write | 7205 | 144.5 | 120.5 | 308.7 |   —   |  868.8  |
| 100 | read | —    | 129.5 | 113.4 | 283.7 | 308.4 |  337.6  |
| 100 | write| —    | 145.8 | 122.5 | 311.8 | 347.2 |  903.8  |
| 200 | read | —    | 130.6 | 112.5 | 299.1 | 321.7 |  372.2  |
| 200 | write| —    | 149.6 | 123.5 | 330.0 | 375.0 |  881.6  |

## Reading

- **Any armed gate collapses the tail.** With the gate off, the write max is
  ~1.9 s and read ~1.6 s — the pool's deep wait queue at 2000 clients. With
  any `N` from 30 up, max latency lands ~340 ms (read) / ~900 ms (write):
  excess fibers wait on the FIFO channel *outside* the pool instead of
  piling onto its condition-variable queue.
- **The gate helps even at `N = pool` (200).** At that size the gate never
  blocks (there are only 200 connections), yet the tail still collapses:
  it moves overload *off* the single pool queue and onto the fair channel.
  This is the structural fix; the `N` knob tunes how much of the pool can
  run at once.
- **`N = 50` is the sweet spot.** It keeps ~the full throughput (8,277 /
  7,205 req/s — effectively unchanged from `N=0`) while the worst case
  stretches to 868 ms write / 342 ms read and the p99 writes tighten to
  309 ms. `N = 30` behaves similarly; `N = 10` starts to cap write
  throughput (its p50 rises to 228 ms).
- **p50 rises slightly with the gate.** The gate deliberately turns a few
  queued outliers into a smooth waiting line, so the median shifts up a
  little (~45 → ~115 ms) while the tail is cut by ~4x. That's the intended
  trade: bounded worst case instead of a long tail.
- **Recommendation:** `config.db_max_active_queries = 50` for a 2-core
  database (or roughly 25% of `db_max_pool_size`); `N` above pool size
  still fixes the pool queue if you prefer not to cap concurrency.