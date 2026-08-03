#!/usr/bin/env bash
# Altair benchmark runner.
#
# For each framework (express, fiber, altair):
#   1. boots its container (docker compose build + up) and waits for /health
#   2. truncates the framework's table and runs the WRITE load
#   3. reseeds the framework's table and runs the READ load
#   4. stores k6 summary JSON + stdout into results/
#
# Load profile via env: VUS_WRITE, VUS_READ, DURATION (s), WARMUP (s).
set -euo pipefail
cd "$(dirname "$0")/.."

WARMUP="${WARMUP:-5}"
DURATION="${DURATION:-30}"
VUS_WRITE="${VUS_WRITE:-50}"
VUS_READ="${VUS_READ:-50}"

SERVICES=(express fiber altair)
PORTS=(4101 4102 4103)
TABLES=(items_express items_fiber items_altair)

if [ $# -ge 1 ]; then
  SERVICES=("$@")
fi

mkdir -p results
rm -f results/*.out

docker compose up -d postgres
until docker compose exec -T postgres pg_isready -U bench -d bench >/dev/null 2>&1; do
  sleep 1
done

./scripts/seed.sh

for i in "${!SERVICES[@]}"; do
  svc=${SERVICES[$i]}
  port=${PORTS[$i]}
  table=${TABLES[$i]}
  base="http://127.0.0.1:${port}"

  echo "== booting ${svc} (port ${port}) =="
  docker compose up -d --build "${svc}"

  echo "== waiting for ${svc} /health =="
  ready=0
  for _ in $(seq 1 120); do
    if curl -sf "${base}/health" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "${ready}" -ne 1 ]; then
    echo "ERROR: ${svc} never became ready" >&2
    docker compose logs --tail 30 "${svc}" >&2
    exit 1
  fi

  echo "== write phase against ${svc} =="
  docker compose exec -T postgres psql -U bench -d bench -c "TRUNCATE ${table} RESTART IDENTITY" >/dev/null
  k6 run k6/write.js \
    -e BASE_URL="${base}" -e VUS="${VUS_WRITE}" -e DURATION="${DURATION}" -e WARMUP="${WARMUP}" \
    --summary-export "results/${svc}-write.json" \
    >"results/${svc}-write.log" 2>&1

  echo "== read phase against ${svc} =="
  ./scripts/seed.sh "${table}" >/dev/null
  k6 run k6/read.js \
    -e BASE_URL="${base}" -e VUS="${VUS_READ}" -e DURATION="${DURATION}" -e WARMUP="${WARMUP}" \
    --summary-export "results/${svc}-read.json" \
    >"results/${svc}-read.log" 2>&1

  echo "== done with ${svc}: results in results/ =="
done

echo
echo "All runs complete."
./scripts/summary.sh || true