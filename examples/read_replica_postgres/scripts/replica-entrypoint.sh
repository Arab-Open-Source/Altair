#!/bin/sh
set -eu

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$PGDATA"
  chown -R postgres:postgres "$PGDATA"
  exec gosu postgres "$0" "$@"
fi

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  until PGPASSWORD=replicator pg_basebackup \
    -h postgres-primary \
    -U replicator \
    -D "$PGDATA" \
    -Fp -Xs -P -R; do
    echo "waiting for postgres-primary replication availability"
    sleep 2
  done
fi

exec docker-entrypoint.sh postgres
