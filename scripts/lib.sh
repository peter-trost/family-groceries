# Shared helpers for scripts/*.sh. Source, don't run.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${FLUTTER_DIR:-$HOME/flutter}/bin:$HOME/.deno/bin:$HOME/.local/bin:$PATH"

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$(basename "$0" .sh)" "$*"; }

# Starts the local Supabase stack if it is not running and exports its URL and publishable key.
supabase_up() {
  (cd "$REPO_ROOT" && { supabase status >/dev/null 2>&1 || supabase start; })
  local env
  env="$(cd "$REPO_ROOT" && supabase status -o env 2>/dev/null)"
  SUPABASE_URL="$(sed -n 's/^API_URL="\(.*\)"$/\1/p' <<<"$env")"
  SUPABASE_PUBLISHABLE_KEY="$(sed -n 's/^PUBLISHABLE_KEY="\(.*\)"$/\1/p' <<<"$env")"
  MAILPIT_URL="$(sed -n 's/^MAILPIT_URL="\(.*\)"$/\1/p' <<<"$env")"
  export SUPABASE_URL SUPABASE_PUBLISHABLE_KEY MAILPIT_URL
}

flutter_defines() {
  echo "--dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
}
