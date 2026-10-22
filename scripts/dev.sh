#!/usr/bin/env bash
# Local development: Supabase stack + Flutter web dev server on http://127.0.0.1:3000.
# Usage: scripts/dev.sh [--stop]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ "${1:-}" == "--stop" ]]; then
  (cd "$REPO_ROOT" && supabase stop)
  exit 0
fi

supabase_up
log "Supabase API $SUPABASE_URL, Mailpit http://127.0.0.1:54324"
cd "$REPO_ROOT/app"
# shellcheck disable=SC2046
exec flutter run -d web-server --web-hostname 127.0.0.1 --web-port "${WEB_PORT:-3000}" $(flutter_defines)
