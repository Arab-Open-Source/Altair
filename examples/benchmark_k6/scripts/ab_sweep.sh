#!/usr/bin/env bash
# Rotating A/B sweep: unpatched vs patched crystal-pg, one arm per invocation,
# altair arm. Results accumulate under results/ab-sweep-<stamp>/.
# Usage: scripts/ab_sweep.sh <arm> <round> <vus> <duration>
set -uo pipefail
cd "$(dirname "$0")/.."
ARM="$1"; ROUND="$2"; VUS="${3:-500}"; DURATION="${4:-90}"
OUT=$(ls -d results/ab-sweep-* 2>/dev/null | head -1)
if [ -z "$OUT" ]; then
  OUT=results/ab-sweep-$(date +%Y%m%d-%H%M%S)
  mkdir -p "$OUT"
fi

cp "/tmp/bench_altair_$ARM" /tmp/bench_altair
kill "$(ss -ltnp 2>/dev/null | grep 4103 | grep -oP 'pid=\K[0-9]+' | head -1)" 2>/dev/null
sleep 2
rm -f results/altair-write.json results/altair-read.json
echo "=== round $ROUND arm $ARM -> $OUT ==="
VUS="$VUS" DURATION="$DURATION" scripts/bench.sh altair > /dev/null 2>&1
rc=$?
if [ -f results/altair-write.json ]; then
  cp results/altair-write.json "$OUT/${ARM}-r${ROUND}-write.json"
  cp results/altair-read.json "$OUT/${ARM}-r${ROUND}-read.json" 2>/dev/null
fi
echo "round $ROUND $ARM done rc=$rc"
sleep 10

