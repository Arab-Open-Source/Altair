#!/usr/bin/env bash
# Isolates the write phase against a chosen altair benchmark binary, saving
# the k6 summary to results/diagnose/<tag>-write.json. Used to A/B the
# sampling variants against the control tail shape.
#
# usage: scripts/quick_write.sh <binary_path> <tag>
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="${1:?binary path}"
TAG="${2:?tag}"
PORT=4103
VUS="${VUS:-1000}"
DURATION="${DURATION:-60}"
TREND_STATS="avg,med,p(90),p(95),p(99),p(99.9),max"
DB_URL="postgres://bench:bench@127.0.0.1:55433/bench"
LOG=/tmp/bench_${TAG}.log

PG() { env PGPASSWORD=bench psql -h 127.0.0.1 -p 55433 -U bench -d bench "$@"; }
stop_port() {
  for _ in $(seq 1 5); do
    local pid=""
    pid="$(ss -ltnp 2>/dev/null | grep ":$1 " | grep -oE 'pid=[0-9]+' | cut -d= -f2 | head -1)" || true
    [ -n "$pid" ] || return 0
    kill "$pid" 2>/dev/null || true
    sleep 1
  done
}

stop_port "$PORT" || true
PG -c "TRUNCATE items_altair RESTART IDENTITY;" >/dev/null

setsid env PORT="$PORT" DATABASE_URL="$DB_URL" BENCH_POOL=200 BENCH_ACTIVE=200 \
  BENCH_INITIAL_POOL=200 BENCH_MAX_IDLE=200 CRYSTAL_WORKERS=8 \
  "$BIN" > "$LOG" 2>&1 < /dev/null &
for _ in $(seq 1 30); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" && break
  sleep 1
done
curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" || { echo "failed — $LOG"; tail -15 "$LOG"; exit 1; }

mkdir -p results/diag

# Optional pre-fire: warm the pool and prepared statements with a few POSTs
# before k6 starts (PREFIRE=n posts), to isolate the cold-start spike from
# the sustained measurement.
if [ "${PREFIRE:-0}" != "0" ]; then
  echo "pre-firing ${PREFIRE} POSTs to warm the pool..."
  for _ in $(seq 1 "${PREFIRE}"); do
    curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/items" \
      -H 'Content-Type: application/json' -d '{"name":"prefire","price":1}' || true
  done
  sleep 2
fi

k6 run -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e DURATION="$DURATION" \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/diag/${TAG}-write.json" \
  k6/write.js > /dev/null

stop_port "$PORT"
echo "done: results/diag/${TAG}-write.json"