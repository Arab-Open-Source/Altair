#!/usr/bin/env bash
# Hello World benchmark — Go vs Altair.
#
# Boots each server in turn, fires 1000 VUs with a 100ms sleep for 2 minutes,
# and writes a k6 summary JSON + a human-readable summary for each.
#
# Usage:
#   ./run.sh                # run both benchmarks
#   ./run.sh go             # benchmark only Go
#   ./run.sh altair         # benchmark only Altair
#
# Override profile:
#   VUS=500 DURATION=60 SLEEP=0.05 ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

ulimit -n 65535

VUS="${VUS:-1000}"
DURATION="${DURATION:-120}"
SLEEP_VAL="${SLEEP:-0.1}"
mkdir -p results

TREND_STATS="avg,med,p(90),p(95),p(99),p(99.9),max"

GO_PORT=4201
ALTAIR_PORT=4202

GO_BIN="/tmp/hello_bench_go"
ALTAIR_BIN="/tmp/hello_bench_altair"

log() { printf '\n=== %s ===\n' "$1"; }

build_go() {
  log "building Go server"
  go build -o "$GO_BIN" go/main.go
}

build_altair() {
  log "building Altair server"
  (cd altair && crystal build --release --no-debug src/hello_bench.cr -o "$ALTAIR_BIN")
}

wait_for() {
  local port="$1"
  for _ in $(seq 1 30); do
    curl -sf -o /dev/null "http://127.0.0.1:$port/" && return 0
    sleep 0.5
  done
  return 1
}

bench() {
  local fw="$1"
  local port="$2"
  local logfile="/tmp/hello_bench_${fw}.log"

  log "starting $fw on :$port"
  case "$fw" in
    go)     setsid "$GO_BIN" > "$logfile" 2>&1 < /dev/null & ;;
    altair) setsid env CRYSTAL_WORKERS="${CRYSTAL_WORKERS:-1}" "$ALTAIR_BIN" > "$logfile" 2>&1 < /dev/null & ;;
  esac
  local pid=$!

  if ! wait_for "$port"; then
    echo "error: $fw failed to start — see $logfile" >&2
    kill "$pid" 2>/dev/null || true
    exit 1
  fi

  log "running k6: $fw ($VUS VUs, ${DURATION}s, ${SLEEP_VAL}s sleep)"
  k6 run \
    -e "BASE_URL=http://127.0.0.1:$port" \
    -e "VUS=$VUS" \
    -e "DURATION=$DURATION" \
    -e "SLEEP=$SLEEP_VAL" \
    --summary-trend-stats "$TREND_STATS" \
    --summary-export "results/${fw}-hello.json" \
    k6/hello.js

  log "stopping $fw (pid $pid)"
  kill "$pid" 2>/dev/null || true
  sleep 1
}

run_both() {
  build_go
  build_altair

  bench go     "$GO_PORT"
  bench altair "$ALTAIR_PORT"

  echo
  echo "=== results ==="
  echo "  Go:     results/go-hello.json"
  echo "  Altair: results/altair-hello.json"
  echo
  echo "Quick compare (http_req_duration avg / p95 / p99):"
  for f in results/go-hello.json results/altair-hello.json; do
    local fw avg p95 p99
    fw="$(basename "$f" -hello.json)"
    avg="$(jq -r '.metrics.http_req_duration.avg' "$f")"
    p95="$(jq -r '.metrics.http_req_duration["p(95)"]' "$f")"
    p99="$(jq -r '.metrics.http_req_duration["p(99)"]' "$f")"
    printf '  %-7s avg=%6.2f ms  p95=%6.2f ms  p99=%6.2f ms\n' "$fw" "$avg" "$p95" "$p99"
  done
}

case "${1:-all}" in
  go)     build_go;             bench go     "$GO_PORT" ;;
  altair) build_altair;         bench altair "$ALTAIR_PORT" ;;
  all)    run_both ;;
  *) echo "usage: $0 [go|altair|all]"; exit 1 ;;
esac
