#!/usr/bin/env bash
# Rails vs Altair benchmark runner.
#
# Runs the write and read benchmark for ONE framework natively on the host
# (only PostgreSQL is in Docker): stops the other app, starts the target if
# needed, then exercises it with the tiered 500 -> 1000 -> 2000 VU load.
#
# usage: scripts/bench.sh rails|altair
#
# Fairness contract: every framework shares the SAME total connection budget
# against PostgreSQL's max_connections=220, and each uses the host's full
# worker count so the comparison is framework vs framework, not tuning vs
# tuning. Both run with a 200-connection pool here.
set -euo pipefail
cd "$(dirname "$0")/.."

# Under 2000 VUs the HTTP server needs far more than the default 1024 open
# files or accept() fails with EMFILE. Raised here so the app inherits it.
ulimit -n 65535

# Tiered load: hold TIER_HOLD s at 500, 1000, then 2000 concurrent clients.
TIER_HOLD="${TIER_HOLD:-5}"
TIER1="${TIER1:-500}"
TIER2="${TIER2:-1000}"
TIER3="${TIER3:-2000}"

# Think time between a virtual user's requests, in milliseconds.
THINK_MS="${THINK_MS:-100}"

# Latency stats captured so the tail is comparable across frameworks.
TREND_STATS="avg,med,p(90),p(95),p(99),p(99.9),max"

DB_URL="postgres://bench:bench@127.0.0.1:55434/bench"
mkdir -p results

# Build Altair once so the runner is start-or-exercise, not build-or-fail.
if [ ! -x /tmp/bench_altair ]; then
  echo "building altair -> /tmp/bench_altair"
  crystal build --release --no-debug app/altair/src/bench.cr -o /tmp/bench_altair
fi

FRAMEWORK="${1:-}"
case "$FRAMEWORK" in
  rails)   PORT=4201; TABLE=items_rails; LOG=/tmp/bench_rails.log   ;;
  altair)  PORT=4203; TABLE=items_altair; LOG=/tmp/bench_altair.log ;;
  *) echo "usage: $0 rails|altair"; exit 1 ;;
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
    rails)
      # Puma multi-process (workers) + threads. AR splits the same 200-connection
      # budget across workers in config/database.yml, so worker*pool never
      # exceeds PostgreSQL's max_connections=220.
      setsid env PORT=4201 DATABASE_URL="$DB_URL" RAILS_ENV=production \
        BENCH_WORKERS="${BENCH_WORKERS:-$(nproc)}" BENCH_THREADS="${BENCH_THREADS:-8}" BENCH_POOL=200 BENCH_TABLE=items_rails \
        bin/rails server -e production -p 4201 > "$LOG" 2>&1 < /dev/null &
      ;;
    altair)
      # Altair is one process with one shared pool, sized to the same ceiling
      # (200) the other side gets.
      setsid env PORT=4203 DATABASE_URL="$DB_URL" BENCH_POOL=200 BENCH_INITIAL_POOL=200 BENCH_MAX_IDLE=200 \
        CRYSTAL_WORKERS="$(nproc)" /tmp/bench_altair > "$LOG" 2>&1 < /dev/null &
      ;;
  esac
}

# Stop every benchmark app first so a leftover from a previous session can't
# hold pooled connections and starve the run (pool x workers must never exceed
# PostgreSQL's max_connections=220).
for other_port in 4201 4203; do
  stop_port "$other_port"
done

# Start the target if it is not already up.
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/health"; then
  echo "starting $FRAMEWORK on :$PORT (log: $LOG)"
  if [ "$FRAMEWORK" = "rails" ]; then
    ( cd app/rails && start_target )
  else
    start_target
  fi
  for _ in $(seq 1 60); do
    curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" && break
    sleep 1
  done
fi
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/health"; then
  echo "error: $FRAMEWORK failed to start — see $LOG" >&2
  exit 1
fi
echo "== $FRAMEWORK ready on :$PORT — write phase =="

PG() { docker compose exec -T postgres psql -U bench -d bench "$@"; }

# Write phase: empty table, POSTs add rows.
PG -c "TRUNCATE $TABLE RESTART IDENTITY;" > /dev/null
k6 run -e "BASE_URL=http://127.0.0.1:$PORT" \
  -e "TIER_HOLD=$TIER_HOLD" -e "TIER1=$TIER1" -e "TIER2=$TIER2" -e "TIER3=$TIER3" -e "THINK_MS=$THINK_MS" \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/$FRAMEWORK-write.json" k6/write.js 2>&1 | tee "results/$FRAMEWORK-write.out"

# Read phase: reseed 10,000 rows then GET them.
echo "== $FRAMEWORK — read phase =="
PG <<SQL > /dev/null
TRUNCATE $TABLE RESTART IDENTITY;
INSERT INTO $TABLE (id, name, price)
SELECT g, 'item-' || g, ROUND((random() * 1000)::numeric, 2)
FROM generate_series(1, 10000) AS g;
SELECT setval('${TABLE}_id_seq', 10000);
SQL
k6 run -e "BASE_URL=http://127.0.0.1:$PORT" \
  -e "TIER_HOLD=$TIER_HOLD" -e "TIER1=$TIER1" -e "TIER2=$TIER2" -e "TIER3=$TIER3" -e "THINK_MS=$THINK_MS" \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/$FRAMEWORK-read.json" k6/read.js 2>&1 | tee "results/$FRAMEWORK-read.out"

echo "== done: results/$FRAMEWORK-write.json, results/$FRAMEWORK-read.json =="