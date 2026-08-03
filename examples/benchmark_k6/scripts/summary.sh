#!/usr/bin/env bash
# Pretty-prints the k6 summary exports in results/*.json as a markdown
# table, ready to paste into the example README.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! ls results/*.json >/dev/null 2>&1; then
  echo "no results yet — run ./scripts/run.sh first"
  exit 0
fi

printf '| framework | scenario | iterations | req/s | failed %% | avg (ms) | p50 (ms) | p95 (ms) | p99 (ms) |\n'
printf '|---|---|---|---|---|---|---|---|---|\n'

for f in results/*.json; do
  name=$(basename "$f" .json)
  framework=${name%%-*}
  scenario=${name##*-}

  read -r iters reqs failed avg p50 p95 p99 <<<"$(jq -r '[ (.metrics.iterations.values.count // 0),
     (.metrics["http_reqs"].values.rate // 0),
     ((.metrics["http_req_failed"].values.rate // 0) * 100),
     (.metrics["http_req_duration"].values.mean // 0),
     (.metrics["http_req_duration"].values.med // 0),
     (.metrics["http_req_duration"].values["p(95)"] // 0),
     (.metrics["http_req_duration"].values["p(99)"] // 0)
   ] | @tsv' "$f")"

  printf '| %s | %s | %s | %.1f | %.2f | %.2f | %.2f | %.2f | %.2f |\n' \
    "$framework" "$scenario" "$iters" "$req" "$failed" "$avg" "$p50" "$p95" "$p99"
done

echo
echo 'raw metrics kept in results/*.json'