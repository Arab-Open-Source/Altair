# gcry 0.38.0 vs Boehm - interleaved A/B on the fix branch

Branch: `fix-read-tail-gc` (local). Motivation: the read-tail
investigation traced the intermittent dirty tail (read p99.9 123-154 ms,
max 247-482 ms) to Boehm stop-the-world pauses, and the November
experiment on gcry 0.27.1 showed a flatter read tail but an 11 percent
write penalty. gcry 0.38.0 (2026-10-21) removed the locked instruction
from the allocation hot path, so the trade was re-measured.

Setup: `app/altair` builds two binaries from the same source - stock
Boehm (with `gc_tuning` compiled to stock behavior: divisor 3, trickle
off) and gcry via `-Dgc_none` + `require "gcry"`. Six interleaved full
`bench.sh altair` rounds (100 VUs / 60 s / pool 20 / 6 workers), server
process verified unique per round (PID-stamped files under
`results/gcrytest/`), zero duplicate signatures.

## Results - medians of 3 rounds

| Workload | Collector | rps | p95 | p99 | p99.9 | max |
|---|---|---:|---:|---:|---:|---:|
| Write | Boehm | 15,335 | 11.4 | 12.7 | **14.9** | **21.3** |
| Write | gcry 0.38.0 | 15,292 | 11.4 | 12.7 | 15.6 | 26.7 |
| Read | Boehm | 14,571 | 12.3 | 15.7 | 25.1 | 60.1 |
| Read | **gcry 0.38.0** | **14,958** | **12.2** | **14.8** | **22.4** | **36.3** |

gcry vs Boehm: write rps -0.3 (parity), write max -25.6 (worse, still
sub-30 ms), read rps **+2.7**, read p99 **+6.2**, read p99.9 **+10.8**,
read max **+39.6**.

## The decisive observation: stability

Per-round read p99.9 / max (ms):

| Collector | r1 | r2 | r3 |
|---|---|---|---|
| Boehm | **123.5 / 482.2** | 25.1 / 60.1 | 23.6 / 37.6 |
| gcry 0.38.0 | 23.3 / 35.6 | 22.1 / 36.3 | 22.4 / 37.9 |

Boehm's median looks acceptable only because two of three rounds landed
clean windows; its bad round exploded to 123.5 / 482.2 - the same
intermittent dirty window as the committed baseline (153.6 / 247.0).
gcry never dirtied: its worst round is better than Boehm's clean
median, across all three rounds.

Against the committed main baseline (a Boehm dirty-window sample),
gcry's read tail improves p99.9 by **85 percent** (153.6 -> 22.4) and
max by **85 percent** (247.0 -> 36.3).

## Verdict

- The 0.27.1 write penalty is gone in 0.38.0 (write throughput at
  parity; write max 26.7 vs 21.3 ms is the only regression, and it is
  small in absolute terms).
- gcry turns the intermittent Boehm dirty window into a deterministic,
  tight tail - which was the entire goal of this branch.
- Open questions before any merge decision: long-run memory behavior
  (RSS over hours), and gcry 0.38.0's age (four days; it fixed a
  memory-safety bug present in 0.37.0 and earlier).

Everything on this branch is local-only per maintainer instruction;
nothing merged or pushed.
