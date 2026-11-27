#!/usr/bin/env sh
# Clean-machine deployment smoke for a generated Altair project.
#
# Usage: scripts/deployment_smoke.sh sqlite|postgresql|api
#
# Generates a fresh project with the locally built CLI (the generated
# shard.yml uses the published GitHub framework dependency, so the Docker
# build fetches Altair itself — no repository bind mount, matching a real
# user's clean machine), adds a real HTTP route and one migration, builds the
# generated image, starts it through the generated Compose file, applies the
# migration explicitly, and verifies health, the route, the non-root user,
# the absence of secrets/source in the runtime image, and volume persistence
# across a restart. Containers and volumes are always removed on exit.
set -eu

mode="${1:-sqlite}"
case "$mode" in
  sqlite | postgresql | api) ;;
  *) echo "usage: $0 sqlite|postgresql|api" >&2; exit 2 ;;
esac

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
bin="$root/bin/altair"
if [ "${ALTAIR_SKIP_BUILD:-0}" != "1" ]; then
  echo "Building the Altair CLI ..."
  (cd "$root" && shards build altair)
fi
[ -x "$bin" ] || { echo "missing $bin — build with shards build altair" >&2; exit 1; }

pid="$$"
project="altairsmoke${mode}${pid}"
tmp="${TMPDIR:-/tmp}/altair-smoke-${mode}-${pid}"
trap 'status=$?; if [ "$status" -ne 0 ]; then (cd "$tmp/$project" 2>/dev/null && compose logs --tail=200) || true; fi; (cd "$tmp/$project" 2>/dev/null && compose down -v --remove-orphans >/dev/null 2>&1) || true; rm -rf "$tmp"; exit $status' EXIT HUP INT TERM
mkdir -p "$tmp"

compose() {
  docker compose -p "$project" -f compose.yml "$@"
}

if command -v python3 >/dev/null 2>&1; then
  port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')"
  export SECRET_KEY_BASE="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
else
  port=$((20000 + pid % 20000))
  export SECRET_KEY_BASE="smoke-test-secret-not-for-production"
fi
export HOST_PORT="$port"
export POSTGRES_USER=app
export POSTGRES_PASSWORD="smoke-local-password"
export POSTGRES_DB="${project}_production"

args=""
if [ "$mode" = "postgresql" ]; then args="-d postgresql"; fi
if [ "$mode" = "api" ]; then args="--api"; fi
echo "Generating $mode project on port $port ..."
(cd "$tmp" && "$bin" new "$project" $args >/dev/null)
cd "$tmp/$project"

endpoint="/hello"
route_body='response.print("hello from generated app")'
if [ "$mode" = "api" ]; then
  endpoint="/api/status"
  route_body='response.json(%({"status":"ok"}))'
fi
app_class="$(printf '%s' "$project" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
cat >> src/config/routes.cr <<CR

class $app_class
  routes do
    get "$endpoint" do |request, response|
      $route_body
    end
  end
end
CR

echo "Adding one migration ..."
"$bin" g migration CreateSmokeItems name:string >/dev/null

echo "Building and starting the generated image ..."
compose up --build -d

echo "Waiting for /health ..."
healthy=0
i=0
while [ "$i" -lt 90 ]; do
  if curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    healthy=1
    break
  fi
  i=$((i + 1))
  sleep 2
done
if [ "$healthy" -ne 1 ]; then
  echo "health check never succeeded" >&2
  exit 1
fi

# The app boots without applying migrations.
if [ "$mode" = "postgresql" ]; then
  before="$(compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT to_regclass('schema_migrations')" | tr -d '[:space:]')"
  [ -z "$before" ] || { echo "schema migrated before explicit command" >&2; exit 1; }
else
  compose exec -T web sh -c 'test -z "$(ls db/data/*.db 2>/dev/null)"' || {
    echo "database created before explicit migration" >&2
    exit 1
  }
fi

image="$(compose images -q web)"
[ -n "$image" ] || { echo "could not resolve built image" >&2; exit 1; }
builder_image="${project}-builder"
docker build --target builder -t "$builder_image" . >/dev/null
runtime_size="$(docker image inspect "$image" --format '{{.Size}}')"
builder_size="$(docker image inspect "$builder_image" --format '{{.Size}}')"
[ "$runtime_size" -lt "$builder_size" ] || {
  echo "runtime image ($runtime_size) is not smaller than the builder image ($builder_size)" >&2
  exit 1
}
docker image rm "$builder_image" >/dev/null
echo "Runtime image is smaller than the builder stage ($runtime_size < $builder_size bytes)."
docker run --rm --entrypoint sh "$image" -c \
  'test ! -f .env && test ! -d lib && test ! -d src && test ! -f db/schema.cr' || {
  echo "runtime image contains secrets or framework sources" >&2
  exit 1
}
echo "Runtime image contains no .env, lib/, src/ or db/schema.cr"

echo "Applying migrations explicitly ..."
compose run --rm web ./bin/altair db:migrate
second="$(compose run --rm web ./bin/altair db:migrate 2>&1)"
echo "$second" | grep -q "Already up to date" || {
  echo "second migration run was not a no-op: $second" >&2
  exit 1
}
echo "Migrations apply exactly once; the second run is a no-op."

if [ "$mode" = "postgresql" ]; then
  after="$(compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT to_regclass('smoke_items')" | tr -d '[:space:]')"
  [ "$after" = "smoke_items" ] || { echo "migration did not create smoke_items" >&2; exit 1; }
else
  compose exec -T web sh -c 'test -n "$(ls db/data/*.db 2>/dev/null)"' || {
    echo "migration did not create a SQLite database" >&2
    exit 1
  }
fi

body="$(curl -fsS "http://127.0.0.1:$port$endpoint")"
case "$body" in
  *hello* | *'"status":"ok"'*) ;;
  *) echo "unexpected endpoint body: $body" >&2; exit 1 ;;
esac
echo "Endpoint $endpoint responded: $body"

uid="$(compose exec -T web id -u | tr -d '[:space:]')"
[ "$uid" != "0" ] || { echo "web container runs as root" >&2; exit 1; }
echo "web container uid: $uid"

echo "Restarting and verifying volume persistence ..."
if [ "$mode" = "postgresql" ]; then
  compose restart db
  i=0
  while [ "$i" -lt 60 ]; do
    if compose exec -T db pg_isready -U "$POSTGRES_USER" >/dev/null 2>&1; then break; fi
    i=$((i + 1))
    sleep 1
  done
fi
compose restart web
healthy=0
i=0
while [ "$i" -lt 90 ]; do
  if curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    healthy=1
    break
  fi
  i=$((i + 1))
  sleep 2
done
[ "$healthy" -eq 1 ] || { echo "health check failed after restart" >&2; exit 1; }
curl -fsS "http://127.0.0.1:$port$endpoint" >/dev/null
if [ "$mode" = "postgresql" ]; then
  after_restart="$(compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT to_regclass('smoke_items')" | tr -d '[:space:]')"
  [ "$after_restart" = "smoke_items" ] || { echo "PostgreSQL volume lost the migrated table" >&2; exit 1; }
else
  compose exec -T web sh -c 'test -n "$(ls db/data/*.db 2>/dev/null)"' || {
    echo "SQLite volume lost the database" >&2
    exit 1
  }
fi

echo "$mode deployment smoke passed."
