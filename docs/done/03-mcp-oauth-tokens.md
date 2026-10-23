# Job 3: MCP server, OAuth 2.1, personal access tokens (2026-10-22)

Branch `job/3-mcp-oauth-tokens`. Design, client setup and sources:
`docs/MCP.md`. Decisions: `docs/DECISIONS.md` 3.1–3.13.

## What was built

- **MCP server** (`supabase/functions/mcp/`). It speaks MCP over streamable
  HTTP with `@modelcontextprotocol/server` 2.3.1, both the 2026-07-28
  revision and the 2025 revisions (`initialize`). Tools: `list_items`
  (optional store or category filter), `add_items` (one or many, classified
  by `classify_item`, no duplicates), `tick_items`, `move_item` (category
  and/or store), `list_categories`, `list_stores`. Each tool has an input
  schema and German descriptions. Names match loosely ("kuehlregal",
  "drogerie", a unique part of a name).
- **Authorization per the MCP spec**, with Supabase Auth's OAuth 2.1 server as
  the authorization server. The function serves Protected Resource Metadata
  at `/functions/v1/mcp/.well-known/oauth-protected-resource` and answers
  with `401` plus `WWW-Authenticate: Bearer resource_metadata=…`. It
  validates JWTs via JWKS (ES256): issuer, signature, expiry,
  `aud = authenticated`, role, and a `client_id` claim. Every tool runs in a
  database transaction as the user, so RLS and the triggers apply as in the
  app.
- **Shared auth for job 4** (`supabase/functions/_shared/auth.ts`,
  `_shared/db.ts`). `authenticate(req)` returns `{userId, householdId, via}`
  for an OAuth token, a PAT or an app session. `asUser(userId, tx => …)`
  runs one transaction as that user.
- **Personal access tokens** (migration `*_personal_access_tokens.sql`). The
  table stores a SHA-256 hash and a 4-character hint.
  `create_personal_access_token` returns the token once, and
  `authenticate_personal_access_token` resolves a hash for edge functions. A
  token is revoked one-way, dies when its creator leaves the household, and
  each user may hold at most 20 active tokens.
- **App** (Flutter web, mobile):
  - The consent page `/oauth/consent` shows the client name, the signed-in
    account, the household, what the client may do and the scopes, with
    "Erlauben" and "Ablehnen".
  - A signed-out user goes through sign-in (or onboarding) and lands back on
    the consent page (`next` in `authRedirect`, same-origin consent URLs
    only).
  - A new settings screen, "Zugänge" (in the menu), holds the MCP URL with a
    copy button and the tokens: create (shown once, copy), list (hint,
    created, last used) and revoke with confirmation. It also lists
    connected OAuth apps, which can be disconnected there.
- **Local stack config.** `[auth.oauth_server]` is enabled with dynamic
  registration and path `/oauth/consent`. `[functions.mcp]` has
  `verify_jwt = false`. The edge runtime policy is `oneshot` (DECISIONS
  3.11).
- **Hosted project.** The Management API enabled the OAuth server, dynamic
  registration and the path `/oauth/consent`. JWT signing was already ES256.
- **Docs.** `docs/MCP.md` covers the endpoint, the tools, and connecting
  Claude, Claude Code, ChatGPT, MCP Inspector or a script, with OAuth or a
  PAT. It also holds the auth design, the research findings with links, and
  the tests.

## How to verify

```bash
scripts/verify.sh --screenshots docs/screenshots/job-3     # every CI gate incl. Playwright
cd e2e && npx playwright test tests/mcp.spec.ts            # only the MCP flows
```

To use the MCP Inspector against the local stack, create a token in the app
under Zugänge, then run:

```bash
npx @modelcontextprotocol/inspector --cli http://127.0.0.1:54321/functions/v1/mcp \
  --transport http --header "Authorization: Bearer fgp_…" --method tools/list
```

## Test results (local `scripts/verify.sh`, port block 546xx, rebased on #6)

| Suite | Result |
| --- | --- |
| gitleaks (history and tree) | no leaks |
| pgTAP | 76/76 (16 new for PATs: hashing, one-time plaintext, owner-only, cross-household, one-way revoke, leaving the household) |
| `db lint` | clean |
| Deno | 21/21 (auth: signature, expiry, audience, issuer, role, PAT, no household; handler: PRM, 401/403 challenges, session refusal, Origin, CORS; name matching) |
| Flutter analyze / test | clean / 100 passed (router `next` cases, consent page, settings) |
| Playwright | 31/31 (6 new MCP tests) |
| MCP Inspector 2.12.0 CLI (`--cli`, PAT) | `tools/list` gave 6 tools; `add_items` put Zahnpasta under 👶 Drogerie and 6 Bier under Getränke; `list_items store=dm` worked |

The Playwright MCP tests (`e2e/tests/mcp.spec.ts`) drive the official MCP SDK
client (`@modelcontextprotocol/client` 2.3.1) and the Flutter web build:

1. **OAuth flow.** 401 and the header, then metadata, then AS discovery, then
   dynamic registration, then the authorization URL with S256 and
   `resource`. The browser consent page shows client and account; after
   Erlauben, the state is checked, the code is exchanged and the token
   carries the client's `client_id`. Then initialize, tools/list, add (with
   classification and no duplicate), move (category and store) and tick.
   Each effect shows up live in the signed-in app within 3 s, and the grant
   appears under Zugänge.
2. **Deny.** Ablehnen returns `access_denied`.
3. **Signed out.** Sign-in on the way to consent returns to the consent page.
4. **PAT.** A token created in the app works in both protocol eras, shows as
   "Zuletzt benutzt", and after revoking in the app gets `401` with
   `error="invalid_token"`.
5. **Wrong household.** Another household's PAT lists nothing; ticking or
   moving the other household's item by id fails; the item is unchanged.
6. **App session tokens, forged JWTs and made-up PATs** all get `401`.

Screenshots are in `docs/screenshots/job-3/`. The token in
`mcp-05-pat-created.png` belonged to a throwaway local stack and was revoked
by the same test.

## Found and fixed along the way

- **Edge runtime 503s.** Under `supabase start`, one worker is reused until its
  1 s CPU budget runs out, and requests in flight then fail after about 13 s.
  This was found by a timing fetch in the tests and the edge runtime log.
  Fixed with `policy = "oneshot"` (DECISIONS 3.11).
- **DNS.** Deno refuses the local DB host `supabase_db_<project>` because of
  the underscore; `_shared/db.ts` maps it to the `db` alias.
- **Playwright redirect hops.** Route handlers don't see redirect hops, so the
  test rewrites the authorize response's Location to map the configured Site
  URL onto the test server.
- **SDK v2 OAuth providers** must persist `discoveryState` next to the code
  verifier; the test provider does this, as real hosts do.

## Missing or blocked

- **Hosted endpoint not deployed.** The DB password is missing, so neither
  migrations nor functions are on `jdwqrallbpdbshrdhenk`
  (`NEEDS_PETER.md` sections 1 and 5).
- **Hosted OAuth needs a public web app.** The consent page lives at
  `<Site URL>/oauth/consent`, and the Site URL is still `localhost:3000`
  (`NEEDS_PETER.md` sections 2, 3 and 5). PATs work without it.
- **Not tested against real Claude or ChatGPT accounts.** That needs the
  hosted endpoint and their accounts. The same flow runs in e2e with the
  official MCP SDK client.
- **RFC 8707 audience.** Supabase never puts `resource` into `aud`, so tokens
  are bound by issuer, signature and `client_id` instead (DECISIONS 3.2).
- **Client ID Metadata Documents**, preferred by the 2026-07-28 spec, are not
  supported by Supabase. Clients use dynamic registration.
- **`add_items`** uses the items insert path (trigger and `classify_item`)
  until job 2's `public.add_items` lands. The switch is one function,
  `addItems()` in `mcp/list.ts`.
