#!/usr/bin/env bash
# Runs the write and read benchmark for a single framework in isolation:
# stops the other two apps, starts the target if needed, then exercises it.
#
# usage: scripts/bench.sh express|fiber|altair
#
# Fairness contract: every framework gets the SAME connection budget and the
# SAME worker count. Express splits BENCH_POOL across its BENCH_WORKERS
# cluster workers, Fiber maps BENCH_WORKERS to GOMAXPROCS and BENCH_POOL to
# its maxOpenConns, and Altair shares one pool of BENCH_POOL over
# CRYSTAL_WORKERS threads. Defaults are the low-saturation realistic profile
# tuned on this machine (20 connections, 6 workers at 100 VUs); override via
# env, e.g. `BENCH_POOL=200 BENCH_WORKERS=8 VUS=2000 scripts/bench.sh altair`.
BENCH_POOL="${BENCH_POOL:-20}"
BENCH_WORKERS="${BENCH_WORKERS:-6}"
BENCH_ACTIVE="${BENCH_ACTIVE:-20}"
set -euo pipefail
cd "$(dirname "$0")/.."

# Under 2000 VUs the HTTP server needs far more than the default 1024 open
# files or accept() fails with EMFILE. Raised here so the app inherits it.
ulimit -n 65535

# Latency stats captured in addition to the defaults (p90/p95) so the tail is
# comparable across frameworks: p99 and p99.9 expose the multi-second outliers.
TREND_STATS="avg,med,p(90),p(95),p(99),p(99.9),max"

# Load profile: the realistic low-saturation profile tuned on this machine
# (100 VUs, 60s) — override for stress reruns, e.g.
# `VUS=2000 DURATION=90 ./scripts/bench.sh altair`.
VUS="${VUS:-100}"
DURATION="${DURATION:-60}"

DB_URL="postgres://bench:bench@127.0.0.1:55433/bench"
mkdir -p results

FRAMEWORK="${1:-}"
case "$FRAMEWORK" in
  express) PORT=4101; TABLE=items_express; LOG=/tmp/bench_express.log ;;
  fiber)   PORT=4102; TABLE=items_fiber;   LOG=/tmp/bench_fiber.log   ;;
  altair)  PORT=4103; TABLE=items_altair;  LOG=/tmp/bench_altair.log  ;;
  *) echo "usage: $0 express|fiber|altair"; exit 1 ;;
esac

# Stop whatever is on a port (a few passes for cluster children to die).
stop_port() {
  for _ in $(seq 1 5); do
    local pid=""
    pid="$(ss -ltnp 2>/dev/null | grep ":$1 " | grep -oE 'pid=[0-9]+' | cut -d= -f2 | head -1)" || true
    [ -n "$pid" ] || return 0
    echo "stopping app on :$1 (pid $pid)"
    kill "$pid" 2>/dev/null || true
    sleep 1
  done
}

# Detached start so the app survives the calling shell.
start_target() {
  case "$FRAMEWORK" in
    express)
      # The total pool splits across the cluster workers.
      setsid env PORT=4101 DATABASE_URL="$DB_URL" BENCH_POOL="$BENCH_POOL" BENCH_WORKERS="$BENCH_WORKERS" BENCH_TABLE=items_express \
        node app/express/src/server.js > "$LOG" 2>&1 < /dev/null &
      ;;
    fiber)
      setsid env PORT=4102 DATABASE_URL="$DB_URL" BENCH_POOL="$BENCH_POOL" BENCH_WORKERS="$BENCH_WORKERS" BENCH_TABLE=items_fiber \
        /tmp/bench_fiber > "$LOG" 2>&1 < /dev/null &
      ;;
    altair)
      # One process, one shared pool, seeded warm so connection setup is not
      # part of the steady-state cost. Admission control (BENCH_ACTIVE) parks
      # excess VUs on a FIFO gate outside the pool so the tail stays bounded
      # under heavy load; 0 = off (classic pool-only).
      # ALTAIR_ENV=production keeps the Development-only N+1 detector off the
      # hot path (it would otherwise register on_query and force every
      # statement through measured_statement), matching how a real deploy runs.
      setsid env PORT=4103 ALTAIR_ENV=production DATABASE_URL="$DB_URL" BENCH_POOL="$BENCH_POOL" BENCH_ACTIVE="$BENCH_ACTIVE" \
        BENCH_INITIAL_POOL="$BENCH_POOL" BENCH_MAX_IDLE="$BENCH_POOL" \
        CRYSTAL_WORKERS="$BENCH_WORKERS" /tmp/bench_altair > "$LOG" 2>&1 < /dev/null &
      ;;
  esac
}

# Stop the other two apps so the target runs alone.
for other_port in 4101 4102 4103; do
  [ "$other_port" != "$PORT" ] && stop_port "$other_port"
done

# Start the target if it is not already up.
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/health"; then
  echo "starting $FRAMEWORK on :$PORT (log: $LOG)"
  start_target
  for _ in $(seq 1 30); do
    curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" && break
    sleep 1
  done
fi
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/health"; then
  echo "error: $FRAMEWORK failed to start — see $LOG" >&2
  exit 1
fi
echo "== $FRAMEWORK ready on :$PORT — write phase =="

PG() { env PGPASSWORD=bench psql -h 127.0.0.1 -p 55433 -U bench -d bench "$@"; }

# Write phase: empty table, POSTs add rows. The warmup run (ramp to VUS plus
# a settle pause) absorbs the cold-start spike (pool + prepared statements +
# GC heap storm) so the measured run's summary reflects sustained load only.
PG -c "TRUNCATE $TABLE RESTART IDENTITY;" > /dev/null
k6 run -q -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e MODE=warmup k6/write.js > /dev/null
k6 run -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e DURATION="$DURATION" \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/$FRAMEWORK-write.json" k6/write.js

# Read phase: reseed 10,000 rows then GET them.
echo "== $FRAMEWORK — read phase =="
PG <<SQL > /dev/null
TRUNCATE $TABLE RESTART IDENTITY;
INSERT INTO $TABLE (id, name, price)
SELECT g, 'item-' || g, ROUND((random() * 1000)::numeric, 2)
FROM generate_series(1, 10000) AS g;
SELECT setval('${TABLE}_id_seq', 10000);
SQL
k6 run -q -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e MODE=warmup k6/read.js > /dev/null
k6 run -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e DURATION="$DURATION" \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/$FRAMEWORK-read.json" k6/read.js

echo "== done: results/$FRAMEWORK-write.json, results/$FRAMEWORK-read.json =="
