#!/usr/bin/env bash
# Per-second PostgreSQL observability sampler for diagnosis runs.
#
# usage: scripts/sample_pg.sh [out_csv] [stop_file]
#
# Appends one CSV line per second with the bench database's connection
# snapshot and cumulative transaction counters. Killed by SIGTERM (the diagnose
# script sends TERM); pid is written to [cwd]/sample_pg.pid.
#
# Columns (comma separated, no header row):
#   unix_sec, backends, active, client_wait, io_wait, lock_wait,
#   xact_commit, xact_rollback
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-/tmp/bench_pg_sample.csv}"
PIDFILE="${2:-$PWD/scripts/.sample_pg.pid}"

trap 'exit 0' TERM INT
echo $$ > "$PIDFILE"
rm -f "$OUT"

PG() { env PGPASSWORD=bench psql -h 127.0.0.1 -p 55433 -U bench -d bench "$@"; }

export PGPASSWORD=bench
while true; do
  PG -At -F ',' <<SQL >> "$OUT"
SELECT
  EXTRACT(EPOCH FROM clock_timestamp())::bigint AS t,
  (SELECT count(*)::bigint FROM pg_stat_activity WHERE datname = 'bench'),
  (SELECT count(*)::bigint FROM pg_stat_activity WHERE datname = 'bench' AND state = 'active'),
  (SELECT count(*)::bigint FROM pg_stat_activity WHERE datname = 'bench' AND wait_event_type = 'Client'),
  (SELECT count(*)::bigint FROM pg_stat_activity WHERE datname = 'bench' AND wait_event_type = 'IO'),
  (SELECT count(*)::bigint FROM pg_stat_activity WHERE datname = 'bench' AND wait_event_type = 'Lock'),
  (SELECT xact_commit::bigint FROM pg_stat_database WHERE datname = 'bench'),
  (SELECT xact_rollback::bigint FROM pg_stat_database WHERE datname = 'bench');
SQL
  sleep 1
done