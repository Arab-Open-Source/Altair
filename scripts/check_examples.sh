#!/usr/bin/env sh
# Compile every curated starter example against a freshly generated project.
#
# The generated project uses the framework at --framework-path (the checkout
# running this script), so each example is verified against the same shard
# an `altair new --with-examples` user receives. Examples carry no shard.yml
# of their own and must compile with the project's dependencies.
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
bin="$root/bin/altair"
# Always rebuild unless the caller explicitly supplies a fresh binary: a
# stale binary in bin/ would test the wrong generator.
if [ "${ALTAIR_SKIP_BUILD:-0}" != "1" ]; then
  echo "Building the Altair CLI ..."
  (cd "$root" && shards build altair)
fi
[ -x "$bin" ] || { echo "missing $bin — build with shards build altair" >&2; exit 1; }

tmp="${TMPDIR:-/tmp}/altair-examples-$$"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp"

echo "Generating a project with --with-examples ..."
(cd "$tmp" && "$bin" new check_app --with-examples --framework-path "$root" >/dev/null)

cd "$tmp/check_app"
shards install >/dev/null

for name in hello json_api cache; do
  echo "Compiling examples/altair/$name/app.cr"
  crystal build "examples/altair/$name/app.cr" --no-codegen
done

echo "All curated examples compile against the generated project."
