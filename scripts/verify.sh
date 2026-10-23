#!/usr/bin/env bash
# Runs every check CI runs, against the local Supabase stack.
# Usage: scripts/verify.sh [--screenshots <dir>] [--skip-e2e]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

SKIP_E2E=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --screenshots) export SCREENSHOT_DIR="$(realpath -m "$2")"; shift 2 ;;
    --skip-e2e) SKIP_E2E=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

log "secret scan (gitleaks, full history + working tree)"
(cd "$REPO_ROOT" && gitleaks git --no-banner --redact . && gitleaks dir --no-banner --redact .)

log "database: reset, pgTAP, lint"
supabase_up
(cd "$REPO_ROOT" && supabase db reset >/dev/null && supabase test db && supabase db lint --local --fail-on warning)

log "edge functions: deno fmt/lint/test"
(cd "$REPO_ROOT/supabase/functions" && deno fmt --check && deno lint && deno test --allow-env --allow-net \
  && deno fmt --check ../classifier && deno lint ../classifier && deno test --allow-read ../classifier)

log "deploy tooling: deno fmt/lint/test"
(cd "$REPO_ROOT/supabase/deploy" && deno fmt --check && deno lint && deno test --allow-read)

log "fg verification CLI: deno fmt/lint/test"
(cd "$REPO_ROOT/.cursor/skills/verify-family-groceries/cli" && deno fmt --check && deno lint && deno test --allow-all)

log "flutter: l10n, format, analyze, test"
(
  cd "$REPO_ROOT/app"
  flutter pub get >/dev/null
  flutter gen-l10n >/dev/null
  git diff --exit-code -- lib/l10n
  dart format --output=none --set-exit-if-changed lib test
  flutter analyze
  flutter test
)

if [[ $SKIP_E2E == 1 ]]; then
  log "skipping e2e"
  exit 0
fi

log "flutter web build against the local stack"
# shellcheck disable=SC2046
(cd "$REPO_ROOT/app" && flutter build web --release --no-web-resources-cdn --no-wasm-dry-run $(flutter_defines) --dart-define-from-file=config/e2e.json >/dev/null)

log "playwright e2e"
(cd "$REPO_ROOT/e2e" && { [[ -d node_modules ]] || npm ci; } && npx playwright test)

log "all checks passed"
