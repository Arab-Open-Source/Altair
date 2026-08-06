#!/usr/bin/env bash
# Isolates the read phase against a chosen altair benchmark binary, saving
# the k6 summary to results/diag/<tag>-read.json. Mirrors quick_write.sh
# but does not truncate the table (reads need rows).
#
# usage: scripts/quick_read.sh <binary_path> <tag>
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

setsid env PORT="$PORT" DATABASE_URL="$DB_URL" BENCH_POOL=200 BENCH_ACTIVE=200 \
  BENCH_INITIAL_POOL=200 BENCH_MAX_IDLE=200 CRYSTAL_WORKERS=8 \
  "$BIN" > "$LOG" 2>&1 < /dev/null &
for _ in $(seq 1 30); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" && break
  sleep 1
done
curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" || { echo "failed — $LOG"; tail -15 "$LOG"; exit 1; }

mkdir -p results/diag

k6 run -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e DURATION="$DURATION" \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/diag/${TAG}-read.json" \
  k6/read.js > /dev/null

stop_port "$PORT"
echo "done: results/diag/${TAG}-read.json"
