#!/usr/bin/env bash
# Altair tail-latency diagnosis run (Wave D1).
#
# Runs the same profile as the committed benchmark (VUS=1000 DURATION=60
# BENCH_ACTIVE=200, pool 200, CRYSTAL_WORKERS=8) but on a binary compiled
# with `--define bench_sample`, and captures:
#   results/diagnose/altair-{write,read}.json  k6 summaries (same TREND_STATS)
#   /tmp/bench_altair_sample.csv               app-side GC heap + pool + per-second latency
#   results/diagnose/pg.csv                   PG backends, wait events, xact commits
#
# The committed ./results/ are untouched: everything lands in results/diagnose/.
#
# usage: scripts/diagnose.sh            (VUS=1000 DURATION=60 by default)
#        VUS=500 DURATION=30 scripts/diagnose.sh
#        SKIP_BUILD=1 scripts/diagnose.sh   (reuse /tmp/bench_altair_sampled)
set -euo pipefail
cd "$(dirname "$0")/.."

VUS="${VUS:-1000}"
DURATION="${DURATION:-60}"
TREND_STATS="avg,med,p(90),p(95),p(99),p(99.9),max"

DB_URL="postgres://bench:bench@127.0.0.1:55433/bench"
PORT=4103
LOG=/tmp/bench_diagnose.log
APP_CSV=/tmp/bench_altair_sample.csv
PG_CSV=results/diagnose/pg.csv
PG_PID_FILE=scripts/.sample_pg.pid

PG() { env PGPASSWORD=bench psql -h 127.0.0.1 -p 55433 -U bench -d bench "$@"; }

stop_port() {
  local port="$1"
  for _ in $(seq 1 5); do
    local pid=""
    pid="$(ss -ltnp 2>/dev/null | grep ":$port " | grep -oE 'pid=[0-9]+' | cut -d= -f2 | head -1)" || true
    [ -n "$pid" ] || return 0
    kill "$pid" 2>/dev/null || true
    sleep 1
  done
}

stop_pg_sample() {
  [ -f "$PG_PID_FILE" ] && kill "$(cat "$PG_PID_FILE")" 2>/dev/null || true
  rm -f "$PG_PID_FILE"
}

cleanup() {
  stop_pg_sample
  stop_port "$PORT"
}
trap cleanup EXIT

mkdir -p results/diagnose
rm -f "$APP_CSV" "$PG_CSV" results/diagnose/*.json

echo "== ensuring postgres is up =="
docker compose up -d postgres >/dev/null
until PG -tAc "select 1" >/dev/null 2>&1; do sleep 1; done

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== building altair with the sampler (sam) =="
  ( cd app/altair && crystal build --release --no-debug --define bench_sample \
      -o /tmp/bench_altair_sampled src/bench.cr )
fi

# Stop any stray apps from earlier runs so the target runs alone.
for p in 4101 4102 4103; do stop_port "$p"; done

echo "== starting sampled altair on :$PORT =="
setsid env PORT="$PORT" DATABASE_URL="$DB_URL" BENCH_POOL=200 BENCH_ACTIVE=200 \
  BENCH_INITIAL_POOL=200 BENCH_MAX_IDLE=200 CRYSTAL_WORKERS=8 \
  BENCH_SAMPLE="$APP_CSV" \
  /tmp/bench_altair_sampled > "$LOG" 2>&1 < /dev/null &
for _ in $(seq 1 30); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" && break
  sleep 1
done
curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" || {
  echo "error: startup failed — see $LOG" >&2; tail -20 "$LOG" >&2; exit 1
}
echo "== altair ready on :$PORT — write phase =="
./scripts/sample_pg.sh "$PG_CSV" "$PWD/$PG_PID_FILE" &

PG -c "TRUNCATE items_altair RESTART IDENTITY;" >/dev/null
k6 run -q -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e MODE=warmup k6/write.js >/dev/null
k6 run -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e DURATION="$DURATION" \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/diagnose/altair-write.json" \
  k6/write.js

sleep 2
echo "== read phase =="
PG <<SQL > /dev/null
TRUNCATE items_altair RESTART IDENTITY;
INSERT INTO items_altair (id, name, price)
SELECT g, 'item-' || g, ROUND((random() * 1000)::numeric, 2)
FROM generate_series(1, 10000) AS g;
SELECT setval('items_altair_id_seq', 10000);
SQL
k6 run -q -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e MODE=warmup k6/read.js >/dev/null
k6 run -e "BASE_URL=http://127.0.0.1:$PORT" -e VUS="$VUS" -e DURATION="$DURATION" \
  --summary-trend-stats "$TREND_STATS" --summary-export "results/diagnose/altair-read.json" \
  k6/read.js

echo
echo "done:"
echo "  k6         results/diagnose/altair-{write,read}.json"
echo "  app-side   $APP_CSV"
echo "  pg-side    $PG_CSV"