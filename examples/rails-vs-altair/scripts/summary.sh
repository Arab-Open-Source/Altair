#!/usr/bin/env bash
# Summarizes results/*-read.json and *-write.json into a markdown table.
# Rows are ordered read-then-write, best-framework-first, keeping the tail
# percentile columns (p99, p99.9, max) so the tiered-load story is visible.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -n "$(ls results/*-read.json results/*-write.json 2>/dev/null)" ] || {
  echo "no results yet — run scripts/bench.sh rails|altair first" >&2
  exit 1
}

printf '| framework | scenario | req/s | failed %% | avg (ms) | p50 (ms) | p90 (ms) | p95 (ms) | p99 (ms) | p99.9 (ms) | max (ms) |\n'
printf '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n'

for scenario in read write; do
  for f in results/*-$scenario.json; do
    name=$(basename "$f" "-$scenario.json")
    reqs=$(jq -r '.metrics["http_reqs"].count' "$f")
    rate=$(jq -r '.metrics["http_reqs"].rate' "$f")
    failed=$(jq -r '.metrics["http_req_failed"].values.rate // 0' "$f")
    avg=$(jq -r '.metrics["http_req_duration"].avg // 0' "$f")
    med=$(jq -r '.metrics["http_req_duration"].med // 0' "$f")
    p90=$(jq -r '.metrics["http_req_duration"]["p(90)"] // 0' "$f")
    p95=$(jq -r '.metrics["http_req_duration"]["p(95)"] // 0' "$f")
    p99=$(jq -r '.metrics["http_req_duration"]["p(99)"] // 0' "$f")
    p999=$(jq -r '.metrics["http_req_duration"]["p(99.9)"] // 0' "$f")
    max=$(jq -r '.metrics["http_req_duration"].max // 0' "$f")
    printf '| %-8s | %-6s | %-10.1f | %.2f | %-9.2f | %-8.2f | %-8.2f | %-8.2f | %-8.2f | %-9.2f | %-9.2f |\n' \
      "$name" "$scenario" "$rate" "$failed" "$avg" "$med" "$p90" "$p95" "$p99" "$p999" "$max"
  done
done
echo
echo "raw k6 exports in results/*.json (stdout in results/*.out)"