#!/usr/bin/env bash
# Vercel's install and build steps (vercel.json runs `scripts/vercel.sh install|build`).
# Vercel restores node_modules/ between builds, so the Flutter SDK and the pub cache live there.
#
#   scripts/vercel.sh install
#   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/vercel.sh build
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

FLUTTER_VERSION="$(sed -n 's/^  FLUTTER_VERSION: *//p' .github/workflows/ci.yml)"
FLUTTER_ROOT="$PWD/node_modules/.flutter"
export PUB_CACHE="$PWD/node_modules/.pub-cache"
export PATH="$FLUTTER_ROOT/bin:$PATH"
export CI=true

fail() { echo "vercel.sh: $*" >&2; exit 1; }
trap 'echo "vercel.sh: failed (exit $?) at line $LINENO: $BASH_COMMAND" >&2' ERR

install() {
  [[ -n $FLUTTER_VERSION ]] || fail "no FLUTTER_VERSION in .github/workflows/ci.yml"
  echo "vercel.sh: Flutter $FLUTTER_VERSION, uid $(id -u), $(. /etc/os-release && echo "$PRETTY_NAME")"
  local missing=() tool
  for tool in git curl unzip xz which tar find; do
    command -v "$tool" >/dev/null || missing+=("${tool/#find/findutils}")
  done
  if ((${#missing[@]})); then dnf install -y -q "${missing[@]}"; fi
  # The restored cache belongs to another uid; Flutter reads its version from git.
  git config --global --add safe.directory '*'

  if [[ "$(git -C "$FLUTTER_ROOT" describe --tags --exact-match 2>/dev/null)" != "$FLUTTER_VERSION" ]]; then
    rm -rf "$FLUTTER_ROOT"
    git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
  fi
  flutter --disable-analytics >/dev/null
  flutter precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia
  flutter --version
  (cd app && flutter pub get --enforce-lockfile)
}

build() {
  [[ -n ${SUPABASE_URL:-} ]] || fail "set SUPABASE_URL (https://<ref>.supabase.co) in the Vercel project"
  [[ $SUPABASE_URL == https://*.supabase.co ]] || fail "SUPABASE_URL must be https://<ref>.supabase.co"
  [[ ${SUPABASE_PUBLISHABLE_KEY:-} == sb_publishable_* ]] \
    || fail "set SUPABASE_PUBLISHABLE_KEY to the project's publishable key (sb_publishable_...); never a secret key"
  cd app
  flutter build web --release --no-wasm-dry-run --base-href / \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
    --dart-define-from-file=config/auth.json
}

case "${1:-}" in
  install | build) "$1" ;;
  *) fail "usage: scripts/vercel.sh install|build" ;;
esac
