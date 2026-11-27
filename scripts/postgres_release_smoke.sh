#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
database_url="${ALTAIR_TEST_PG_URL:-postgres://postgres:postgres@localhost:5433/altair_test}"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/altair-pg-smoke.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

if [[ "${ALTAIR_SKIP_BUILD:-0}" != "1" ]]; then
  (cd "$root" && shards build altair)
fi
cd "$tmp"
"$root/bin/altair" new app -d postgresql --framework-path "$root" >/dev/null
cd app
shards install

cat > smoke.cr <<'CRYSTAL'
require "pg"

url = ENV.fetch("DATABASE_URL")
separator = url.includes?("?") ? "&" : "?"
pool_url = "#{url}#{separator}initial_pool_size=1&max_pool_size=1&max_idle_pool_size=1&checkout_timeout=30&retry_attempts=3"

DB.open(pool_url) do |db|
  db.exec("CREATE TEMP TABLE altair_release_smoke (id BIGSERIAL PRIMARY KEY, value INT)")

  fibers = 64
  per_fiber = 10
  results = Channel(Exception?).new(fibers)

  fibers.times do |i|
    spawn(name: "release-smoke-#{i}") do
      per_fiber.times do |j|
        db.exec("INSERT INTO altair_release_smoke (value) VALUES ($1)", i * 100 + j)
      end
      db.scalar("SELECT max(id) FROM altair_release_smoke").as(Int64)
      results.send(nil)
    rescue e
      results.send(e)
    end
  end

  fibers.times do
    if error = results.receive
      raise error
    end
  end

  count = db.scalar("SELECT count(*) FROM altair_release_smoke").as(Int64)
  raise "unexpected row count: #{count}" unless count == (fibers * per_fiber).to_i64
  raise "pool used more than one connection" unless db.pool.stats.open_connections == 1
end

puts "PostgreSQL release smoke passed"
CRYSTAL

DATABASE_URL="$database_url" crystal run smoke.cr
