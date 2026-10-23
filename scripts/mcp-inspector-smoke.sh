#!/usr/bin/env bash
# Smoke test of the local MCP endpoint with the official MCP Inspector CLI: a throwaway user and
# household, a personal access token, every tool once, then revocation.
# Usage: scripts/mcp-inspector-smoke.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
supabase_up

INSPECTOR=@modelcontextprotocol/inspector@2.12.0
ENDPOINT="$SUPABASE_URL/functions/v1/mcp"
email="inspector-$(date +%s)@example.test"

api() { # api <method> <path> [json] [bearer]
  curl -sS -X "$1" "$SUPABASE_URL$2" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
    -H "content-type: application/json" ${4:+-H "authorization: Bearer $4"} ${3:+-d "$3"}
}
json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(eval("("+s+")"+process.argv[1])))' "$1"; }

session="$(api POST /auth/v1/signup "{\"email\":\"$email\",\"password\":\"inspector-pass-123\"}" | json .access_token)"
api POST /rest/v1/rpc/create_household '{}' "$session" >/dev/null
pat="$(api POST /rest/v1/rpc/create_personal_access_token '{"p_name":"Inspector"}' "$session" | json '[0].token')"
log "user $email, token fgp_…${pat: -4}, endpoint $ENDPOINT"

inspect() {
  log "inspector: $*" >&2
  npx -y "$INSPECTOR" --cli "$ENDPOINT" --transport http --header "Authorization: Bearer $pat" "$@"
}

status() { # status [bearer]: the endpoint's status line and challenge for tools/list
  curl -sS -o /dev/null -D - -X POST "$ENDPOINT" -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' ${1:+-H "authorization: Bearer $1"} \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | grep -iE '^(HTTP|www-authenticate)'
}

log "no token -> 401 with the metadata pointer"
status

inspect --method tools/list | json '.tools.map(t => t.name).join(", ")'
inspect --method tools/call --tool-name add_items \
  --tool-arg 'items=[{"name":"Hafermilch"},{"name":"2 Gurken"},{"name":"Zahnpasta","store":"dm"}]'
inspect --method tools/call --tool-name add_items --tool-arg 'items=[{"name":"Gurke"}]'
inspect --method tools/call --tool-name move_item --tool-arg item=hafermilch --tool-arg category=Getränke
inspect --method tools/call --tool-name tick_items --tool-arg 'items=["Gurken"]'
inspect --method tools/call --tool-name list_items --tool-arg store=dm
inspect --method tools/call --tool-name list_categories | head -c 400
echo
inspect --method tools/call --tool-name list_stores

log "revoke the token, then the same call again"
api PATCH "/rest/v1/personal_access_tokens?name=eq.Inspector" "{\"revoked_at\":\"$(date -u +%FT%TZ)\"}" "$session"
status "$pat" | tee /dev/stderr | grep -q '^HTTP/1.1 401' || { echo "revoked token still works" >&2; exit 1; }
if inspect --method tools/list; then
  echo "revoked token still works" >&2
  exit 1
fi
log "revoked token refused; smoke test passed"
