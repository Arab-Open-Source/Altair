# Hello World Benchmark — Go vs Altair

A simple load comparison between **Go** (net/http) and **Altair** (Crystal)
on the same endpoint: `GET /` returns a fixed `"Hello, World!"` text.

The purpose is to measure the HTTP layer in isolation — no database, no I/O,
no template rendering. The server just accepts a request and writes a constant
string.

---

## Results

Both runs on the same machine, same parameters: **1000 virtual users**, 100ms
sleep between requests, **2 minutes** each.

| Framework | Requests | Req/s | Avg | p95 | p99 |
|---|---:|---:|---:|---:|---:|
| Go | 1,182,834 | 9,849 | 0.79 ms | 2.11 ms | 4.64 ms |
| Altair | 1,178,633 | 9,814 | 1.11 ms | 3.02 ms | 8.22 ms |

**Zero failed requests** in both runs.

---

## What this measures

This comparison measures the **framework overhead itself** — specifically:

1. **Accept loop**: how the server accepts new connections and dispatches them
   to worker threads/fibers.
2. **Request parsing**: reading HTTP method, path, and headers.
3. **Routing**: matching the path to the right controller.
4. **Response generation**: writing status, headers, and body.
5. **Concurrency scheduler**: how the framework manages 1000 simultaneous
   fibers/goroutines on OS threads.

It does not measure:
- database performance (none)
- template rendering (none)
- JSON serialization (none)
- middleware overhead (only Altair's minimum stack)

---

## Why Go is slightly faster

The difference is small (1.4x on average) and has clear architectural reasons:

### 1. Runtime

- **Go** compiles directly to native code. The scheduler has been refined for
   over a decade for high concurrency.
- **Crystal** (Altair's host language) also compiles to native code via LLVM,
   but its fiber scheduler is cooperative rather than preemptive, so each
   fiber must explicitly yield at suspension points.

### 2. Concurrency model

- **Go** uses goroutines with a work-stealing scheduler — each OS thread has a
   local run queue and can steal work from idle threads, reducing contention.
- **Altair/Crystal** runs cooperative fibers on a fixed number of OS threads
   (equal to `CRYSTAL_WORKERS`) with no work-stealing — 1000 concurrent fibers
   contend on the same thread pool.

### 3. Framework cost

- **Go net/http** is a raw HTTP server with no framework — no routing, no
   middleware, no parameter parsing. Data flows straight from the socket to
   the handler function.
- **Altair** even in its simplest form goes through: accept → parse → route →
   middleware (logger) → controller → renderer → write response. Each
   additional step adds a small but cumulative cost.

### 4. Garbage collection

- **Go** ships a low-pause, concurrent GC optimized for sub-millisecond pauses
   in recent versions.
- **Crystal** uses the Boehm GC — simpler and less aggressively tuned, which
   can mean longer pauses under high allocation pressure.

---

## Why the gap is small regardless

Despite all of the above, the difference is only 1.4x on average — not 10x or
100x. This is because:

1. **The real work is trivial.** Returning a constant string costs almost
   nothing on either runtime. The network round-trip and accept loop dominate,
   and both are close.

2. **Crystal compiles to native code.** It is not interpreted and does not run
   on a VM. The raw performance gap between it and Go is inherently small.

3. **Altair's hot path is lean.** The critical path from socket to response is
   written efficiently with no unnecessary allocation in the simple case.

4. **Saturation is low.** At 1000 VUs with 100ms sleep, each fiber spends most
   of its time sleeping. The true concurrent requests at any instant are ~10
   (1000 x 1ms / 100ms), which is light load for any modern server.

---

## When the gap matters

The difference becomes meaningful under:

- **CPU-bound endpoints**: Go's scheduler and GC advantages show more clearly.
- **Very high concurrency** (> 10,000 simultaneous): memory management and
   scheduling differences compound.
- **Zero sleep**: sending requests back-to-back raises saturation and widens
   the average gap.

---

## How to run

Requires Go, Crystal, and k6.

```bash
# run both benchmarks (Go then Altair)
./run.sh

# run one only
./run.sh go
./run.sh altair

# customize the profile
VUS=500 DURATION=60 SLEEP=0.05 ./run.sh
```

Variables:
- `VUS` — number of virtual users (default: 1000)
- `DURATION` — test duration in seconds (default: 120)
- `SLEEP` — sleep between requests in seconds (default: 0.1)

Results are written to `results/go-hello.json` and `results/altair-hello.json`.

---

## Layout

```
hello_bench/
├── go/main.go              # Go server (net/http)
├── altair/                 # Altair application
│   ├── shard.yml
│   └── src/
│       ├── hello_bench.cr
│       ├── config/application.cr
│       └── app/controllers/
│           ├── application_controller.cr
│           └── hello_controller.cr
├── k6/hello.js             # k6 load script
├── run.sh                  # benchmark runner
└── results/                # k6 summary exports
```

---

## Caveat

These numbers are **indicative, not definitive** — they depend on the machine,
OS, Crystal/Go versions, and system load during the run. The intent is to
give a general picture of where Altair stands against a common reference (Go
net/http), not to render a final verdict.

Altair is still under active development, and performance improves with each
release.
