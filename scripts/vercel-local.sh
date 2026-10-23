#!/usr/bin/env bash
# Runs vercel.json's installCommand and buildCommand the way Vercel does: in a fresh clone of
# HEAD, inside Amazon Linux 2023 (Vercel's build image base), as root, with node_modules/ kept
# in a Docker volume like Vercel's build cache. Rerun to see the cached second build.
#
#   scripts/vercel-local.sh [out-dir]     # copies the output directory to out-dir (default /tmp/fg-vercel-out)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

out="${1:-/tmp/fg-vercel-out}"
src="$(mktemp -d)"
trap 'rm -rf "$src"' EXIT
git clone --quiet "$REPO_ROOT" "$src/repo"
git -C "$src/repo" -c advice.detachedHead=false checkout --quiet "$(git -C "$REPO_ROOT" rev-parse HEAD)"

field() { node -e "process.stdout.write(require('$src/repo/vercel.json')['$1'])"; }
install_cmd="$(field installCommand)"
build_cmd="$(field buildCommand)"
output_dir="$(field outputDirectory)"
log "install: $install_cmd"
log "build:   $build_cmd"

docker run --rm --memory 5g \
  -v "$src/repo:/vercel/path0" -v fg-vercel-node-modules:/vercel/path0/node_modules -w /vercel/path0 \
  -e SUPABASE_URL="${SUPABASE_URL:-https://jdwqrallbpdbshrdhenk.supabase.co}" \
  -e SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY:-sb_publishable_YMFUFoZ-smly3zDIYTIFRw_vRt6UBk5}" \
  amazonlinux:2023 bash -c "set -e; time ($install_cmd); time ($build_cmd); chown -R $(id -u):$(id -g) app"

rm -rf "$out"
cp -r "$src/repo/$output_dir" "$out"
log "output: $out ($(du -sh "$out" | cut -f1))"
