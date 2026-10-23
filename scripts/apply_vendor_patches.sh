#!/usr/bin/env bash
# Applies the vendored-driver patches for the issue #21 wire-protocol fix onto
# every lib/ tree this checkout owns. `shards install` restores pristine
# upstream sources, so this must run after every fresh install (CI included)
# or the framework compiles against the unpatched wire protocol.
#
#   scripts/apply_vendor_patches.sh                  # all known lib/ trees
#   scripts/apply_vendor_patches.sh lib              # a single lib/ directory
#
# Patches live in scripts/vendor_patches/ as unified diffs against the exact
# pinned upstream revisions (crystal-pg 0.30.0, crystal-db 0.14.0).
set -euo pipefail
cd "$(dirname "$0")/.."

roots=("$@")
if [ ${#roots[@]} -eq 0 ]; then
  roots=(lib examples/benchmark_k6/app/altair/lib)
fi

status=0
for root in "${roots[@]}"; do
  if [ -d "$root/pg" ]; then
    if grep -q "altair_" "$root/pg/src/pq/connection.cr"; then
      echo "already patched: $root/pg"
    elif patch --silent -p1 -d "$root/pg" \
      < scripts/vendor_patches/crystal-pg-issue21.patch; then
      echo "patched $root/pg (issue #21 wire-protocol fix)"
    else
      echo "warning: $root/pg patch did not apply cleanly" >&2
      status=1
    fi
  fi
  if [ -d "$root/db" ]; then
    if grep -q "raise PoolRetryAttemptsExceeded.new(cause: last_error)" "$root/db/src/db/pool.cr"; then
      echo "already patched: $root/db"
    elif patch --silent -p1 -d "$root/db" \
      < scripts/vendor_patches/crystal-db-retry-cause.patch; then
      echo "patched $root/db (retry-cause preservation)"
    else
      echo "warning: $root/db patch did not apply cleanly" >&2
      status=1
    fi
  fi
done
find lib examples/benchmark_k6/app/altair/lib -name "*.rej" -delete 2>/dev/null || true
exit $status
