#!/usr/bin/env bash
# Pretty-prints the k6 summary exports in results/*.json as a markdown
# table, ready to paste into the example README.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! ls results/*.json >/dev/null 2>&1; then
  echo "no results yet — run ./scripts/run.sh first"
  exit 0
fi

printf '| framework | scenario | iterations | req/s | failed %% | avg (ms) | p50 (ms) | p95 (ms) | p99 (ms) | p99.9 (ms) | max (ms) |\n'
printf '|---|---|---|---|---|---|---|---|---|---|---|\n'

for f in results/*.json; do
  name=$(basename "$f" .json)
  framework=${name%%-*}
  scenario=${name##*-}

  read -r iters reqs failed avg p50 p95 p99 p999 max <<<"$(jq -r '[ (.metrics["iterations"].count // 0),
     (.metrics["http_reqs"].rate // 0),
     ((.metrics["http_req_failed"].value // 0) * 100),
     (.metrics["http_req_duration"].avg // 0),
     (.metrics["http_req_duration"].med // 0),
     (.metrics["http_req_duration"]["p(95)"] // 0),
     (.metrics["http_req_duration"]["p(99)"] // 0),
     (.metrics["http_req_duration"]["p(99.9)"] // 0),
     (.metrics["http_req_duration"].max // 0)
   ] | @tsv' "$f")"

  printf '| %s | %s | %s | %.1f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f |\n' \
    "$framework" "$scenario" "$iters" "$reqs" "$failed" "$avg" "$p50" "$p95" "$p99" "$p999" "$max"
done

echo
echo 'raw metrics kept in results/*.json'
