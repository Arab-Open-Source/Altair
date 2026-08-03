#!/usr/bin/env bash
# Runs the write and read benchmark for a single framework in isolation:
# stops the other two apps, starts the target if needed, then exercises it.
#
# usage: scripts/bench.sh express|fiber|altair
#
# Fairness contract: every framework gets the SAME total connection budget
# against PostgreSQL's max_connections (220). Express splits BENCH_POOL across
# its 8 cluster workers (=25 each), Fiber uses BENCH_POOL directly, and Altair
# shares one pool of BENCH_POOL. All three run 200 here so upgrade is measured
# against an equal cap, not against an under-sized pool.
set -euo pipefail
cd "$(dirname "$0")/.."

# Under 2000 VUs the HTTP server needs far more than the default 1024 open
# files or accept() fails with EMFILE. Raised here so the app inherits it.
ulimit -n 65535

# Latency stats captured in addition to the defaults (p90/p95) so the tail is
# comparable across frameworks: p99 and p99.9 expose the multi-second outliers.
TREND_STATS="avg,med,p(90),p(95),p(99),p(99.9),max"

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
      # Pool 200 splits to 25 connections per cluster worker (8 workers).
      setsid env PORT=4101 DATABASE_URL="$DB_URL" BENCH_POOL=200 BENCH_WORKERS=8 BENCH_TABLE=items_express \
        node app/express/src/server.js > "$LOG" 2>&1 < /dev/null &
      ;;
    fiber)
      setsid env PORT=4102 DATABASE_URL="$DB_URL" BENCH_POOL=200 BENCH_WORKERS=8 BENCH_TABLE=items_fiber \
        /tmp/bench_fiber > "$LOG" 2>&1 < /dev/null &
      ;;
    altair)
      # Altair is one process with one shared pool, sized to the same ceiling
      # Express and Fiber get via their 8 workers (200 total, at PostgreSQL's
      # max_connections=220). Smaller pools queue ~1950 of 2000 VUs behind a
      # handful of busy connections and the tail latency explodes.
      setsid env PORT=4103 DATABASE_URL="$DB_URL" BENCH_POOL=200 BENCH_INITIAL_POOL=200 BENCH_MAX_IDLE=200 \
        CRYSTAL_WORKERS=8 /tmp/bench_altair > "$LOG" 2>&1 < /dev/null &
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

# Write phase: empty table, POSTs add rows.
PG -c "TRUNCATE $TABLE RESTART IDENTITY;" > /dev/null
k6 run -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS=2000 -e DURATION=90 \
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
k6 run -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS=2000 -e DURATION=90 \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/$FRAMEWORK-read.json" k6/read.js

echo "== done: results/$FRAMEWORK-write.json, results/$FRAMEWORK-read.json =="
