#!/usr/bin/env bash
# Seeds the benchmark tables with 10,000 fixed rows (ids 1..10000) so the
# read load hits existing rows. Pass one table name to reseed just that
# table (the runner does this before each read phase).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -ge 1 ]; then
  TABLES=("$1")
else
  TABLES=(items_altair items_rails)
fi

for t in "${TABLES[@]}"; do
  docker compose exec -T postgres psql -U bench -d bench <<SQL
TRUNCATE ${t};
INSERT INTO ${t} (id, name, price)
SELECT g, 'item-' || g, ROUND((random() * 1000)::numeric, 2)
FROM generate_series(1, 10000) AS g;
SELECT setval('${t}_id_seq', 10000);
SQL
  echo "seeded ${t} (10000 rows)"
done