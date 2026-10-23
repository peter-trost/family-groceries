# MCP server

The shopping list is available to AI assistants (Claude, ChatGPT, any MCP
client) through a Model Context Protocol server. It runs as the Supabase edge
function `mcp` and speaks MCP over streamable HTTP.

| | |
| --- | --- |
| Endpoint (hosted) | `https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/mcp` |
| Endpoint (local stack) | `http://127.0.0.1:54321/functions/v1/mcp` |
| Protected Resource Metadata | `<endpoint>/.well-known/oauth-protected-resource` |
| Authorization server | Supabase Auth, `https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1` |
| Credentials | OAuth 2.1 access token, or a personal access token (`fgp_…`) |
| Protocol versions | 2026-07-28 (`server/discover`) and 2025-11-25 down to 2024-11-05 (`initialize`) |

The app shows the endpoint under **Menü → Zugänge → MCP-Server**, with a copy
button. The hosted endpoint goes live once the function is deployed (see
`NEEDS_PETER.md`, section 5).

## Tools

All tools act on the signed-in user's household only. Items, categories and
stores can be named loosely: case, umlauts and emoji are ignored ("kuehlregal"
finds "Kühlregal", "drogerie" finds "👶 Drogerie"), and a unique part of a
name is enough. An id works too.

| Tool | Input | What it does |
| --- | --- | --- |
| `list_items` | `store?`, `category?` | Open items in aisle order. With `store`: that store's items plus untagged ones, in that store's order. |
| `add_items` | `items: [{name, quantity?, category?, store?}]` (1–50) | Adds items. Each one goes through `classify_item`, like items added in the app. Names already on the list come back under `alreadyOnList` instead of being duplicated. |
| `tick_items` | `items: [name or id]` (1–50) | Ticks items off; they move to "Zuletzt gekauft". Unresolvable names come back under `notFound` with the reason. |
| `move_item` | `item`, `category?`, `store?` (`null` removes the store) | Changes category and/or store. A category change is a correction the classifier learns from. |
| `list_categories` | none | Categories in aisle order. |
| `list_stores` | none | Stores. |

Results are JSON text. Errors that the assistant can fix (unknown or
ambiguous names) come back as tool errors (`isError: true`) with a German
message that lists the valid options.

Changes made through MCP reach the app through Realtime like any other change:
an item added by an assistant appears on both phones within seconds (the
e2e test allows 3 s).

## Connecting a client

Two ways to authenticate:

- **OAuth (recommended).** The client discovers everything from the endpoint
  URL, registers itself (dynamic client registration) and opens the app's
  consent page. You sign in, see the client's name and what it may do, and
  tap **Erlauben**. Disconnect it later under **Zugänge → Verbundene Apps**.
- **Personal access token.** For clients without OAuth support, scripts and
  the Siri shortcut. Create one under **Zugänge → Token erstellen**. It is
  shown once; copy it then. Send it as `Authorization: Bearer fgp_…`. Revoke
  it under **Zugänge**; requests with it get `401` immediately.

### Claude (claude.ai, Desktop, mobile)

Add a custom connector with the endpoint URL and no client ID or secret.
Claude registers itself and opens the consent page. Not tested from this box
(it needs a Claude account and the hosted endpoint); the e2e test runs the
same flow with the official MCP SDK client.

### Claude Code

```bash
claude mcp add --transport http einkauf https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/mcp
# then run /mcp in Claude Code and choose "Authenticate"
```

With a personal access token instead:

```bash
claude mcp add --transport http einkauf https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/mcp \
  --header "Authorization: Bearer fgp_…"
```

### ChatGPT

Create a custom connector with the endpoint URL and OAuth authentication. If
ChatGPT asks for a client ID, leave it empty so it registers itself; the
server supports dynamic client registration. This path is not tested from
this box (it needs a ChatGPT account and the hosted endpoint).

### MCP Inspector and scripts

```bash
# Interactive UI, OAuth or a bearer header
npx @modelcontextprotocol/inspector

# CLI with a personal access token
npx @modelcontextprotocol/inspector --cli <endpoint> --transport http \
  --header "Authorization: Bearer fgp_…" --method tools/list
npx @modelcontextprotocol/inspector --cli <endpoint> --transport http \
  --header "Authorization: Bearer fgp_…" \
  --method tools/call --tool-name add_items --tool-arg 'items=[{"name":"Milch"}]'
```

Any other client works if it supports streamable HTTP and either the MCP
authorization flow or a custom `Authorization` header.

## How authentication works

```
client                         mcp function                Supabase Auth            app (/oauth/consent)
  | POST /mcp (no token)           |                            |                           |
  |------------------------------->| 401 WWW-Authenticate:      |                           |
  |<-------------------------------| Bearer resource_metadata=… |                           |
  | GET …/.well-known/oauth-protected-resource                  |                           |
  |------------------------------->| {resource, authorization_servers: [<project>/auth/v1]} |
  | GET /.well-known/oauth-authorization-server/auth/v1 -------->|                           |
  | POST /auth/v1/oauth/clients/register (DCR) ----------------->|                           |
  | browser: /auth/v1/oauth/authorize?…&code_challenge=…&resource=<endpoint>                 |
  |------------------------------------------------------------>| 302 <site>/oauth/consent?authorization_id=…
  |                                                             |-------------------------->|
  |                                                             |   approve (signed-in user) |
  | browser: redirect_uri?code=…&state=… <---------------------------------------------------|
  | POST /auth/v1/oauth/token (code + code_verifier) ----------->| ES256 access token        |
  | POST /mcp  Authorization: Bearer <token>                     |                           |
  |------------------------------->| verify via JWKS, then run the tool as the user         |
```

The function (`supabase/functions/mcp/handler.ts`):

1. Serves Protected Resource Metadata (RFC 9728) at
   `<endpoint>/.well-known/oauth-protected-resource` (and
   `<endpoint>/oauth-protected-resource`, the path Supabase's own helper uses).
   An edge function cannot serve the root `/.well-known/…` path, so clients
   find the document through the `WWW-Authenticate` header, which the MCP
   specification lists first.
2. Answers requests without a valid credential with `401` and
   `WWW-Authenticate: Bearer resource_metadata="…", scope="openid email"`,
   plus `error="invalid_token"` when a token was sent but rejected. A valid
   user without a household gets `403`.
3. Rejects browser requests whose `Origin` is not the project's host,
   localhost, or listed in the `MCP_ALLOWED_ORIGIN_HOSTS` secret
   (comma-separated hostnames).
4. Authenticates (`supabase/functions/_shared/auth.ts`, shared with the Siri
   endpoint):
   - **OAuth access token.** A JWT verified against the project's JWKS
     (ES256 or RS256), with `iss` equal to the project's Auth URL,
     `aud = "authenticated"`, an unexpired `exp`, `role = "authenticated"`
     and a `client_id` claim. That claim marks a token issued to an OAuth
     client.
   - **App session token** (no `client_id`). Accepted by `authenticate()`
     for the app's own calls (the voice endpoint), but refused by the MCP
     endpoint, so a token issued to the app cannot be replayed at it.
   - **Personal access token** (`fgp_` + 43 base64url characters). Its
     SHA-256 hash is looked up with
     `public.authenticate_personal_access_token`. The lookup fails when the
     token is revoked or its creator has left the household, and it records
     `last_used_at`.
5. Runs every tool in one database transaction as the user
   (`supabase/functions/_shared/db.ts`, `asUser`): role `authenticated` and
   `request.jwt.claims.sub` = the user. Row level security, the items
   triggers and `classify_item` therefore behave exactly as they do for the
   app. Another household's rows are invisible. The function never writes
   with the service role.

Personal access tokens live in `public.personal_access_tokens` (migration
`*_personal_access_tokens.sql`). Only the hash is stored, plus the last four
characters for the list in the app. `create_personal_access_token(p_name)`
returns the plaintext once. Clients can read their own rows except the hash,
and can only set `revoked_at`, which a trigger keeps from being cleared. At
most 20 active tokens exist per user.

## Configuration

**Local stack** (`supabase/config.toml`):

```toml
[auth.oauth_server]
enabled = true
authorization_url_path = "/oauth/consent"
allow_dynamic_registration = true

[functions.mcp]
verify_jwt = false   # the function checks OAuth tokens and PATs itself
```

The CLI signs tokens with a built-in ES256 key, so the JWKS path is the same
as in production. Supabase redirects the browser to
`<site_url>/oauth/consent`. Locally that is the web dev server (`scripts/dev.sh`).

**Hosted project** `jdwqrallbpdbshrdhenk`, set on 2026-10-22 through the
Management API (`PATCH /v1/projects/{ref}/config/auth`):
`oauth_server_enabled = true`, `oauth_server_allow_dynamic_registration = true`,
`oauth_server_authorization_path = "/oauth/consent"`. The project already
signs with an ES256 key (`in_use`; the legacy HS256 key is
`previously_used`). The consent page needs the web app at the project's Site
URL; until the web app is hosted, the Site URL is `http://localhost:3000`
(`NEEDS_PETER.md`).

## Research notes (2026-10-22)

Sources read for this design:

- Supabase OAuth 2.1 server:
  [getting started](https://supabase.com/docs/guides/auth/oauth-server/getting-started),
  [OAuth flows](https://supabase.com/docs/guides/auth/oauth-server/oauth-flows),
  [MCP authentication](https://supabase.com/docs/guides/auth/oauth-server/mcp-authentication),
  [token security](https://supabase.com/docs/guides/auth/oauth-server/token-security).
- Supabase guide for MCP servers on edge functions:
  [BYO MCP](https://supabase.com/docs/guides/ai-tools/byo-mcp).
- Management API: [OpenAPI document](https://api.supabase.com/api/v1-json).
- MCP specification, latest revision 2026-07-28:
  [authorization](https://modelcontextprotocol.io/specification/latest/basic/authorization),
  [authorization server discovery](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/authorization-server-discovery),
  [security considerations](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/security-considerations),
  [streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http),
  [versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning),
  and the previous [2025-11-25 transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).
- Source code: [supabase/auth](https://github.com/supabase/auth),
  [supabase/cli](https://github.com/supabase/cli),
  [supabase-flutter](https://github.com/supabase/supabase-flutter),
  [supabase-js](https://github.com/supabase/supabase-js).

Findings that shaped the implementation. Each was checked against the local
stack or the hosted project, not only the docs:

- **Endpoints.** Under `<project>/auth/v1`: `oauth/authorize`, `oauth/token`,
  `oauth/userinfo`, `oauth/clients/register` (only with dynamic registration
  on), `.well-known/jwks.json`, `.well-known/openid-configuration`,
  `.well-known/oauth-authorization-server`. The hosted project also answers
  the RFC 8414 path-inserted URL
  `/.well-known/oauth-authorization-server/auth/v1`; the local stack does not
  (404), so local clients fall back to `/auth/v1/.well-known/openid-configuration`.
- **Consent.** `oauth/authorize` redirects to
  `<site_url><authorization_path>?authorization_id=…`. The page calls
  `GET /oauth/authorizations/{id}` and `POST …/{id}/consent`
  (`{"action":"approve"|"deny"}`) with the user's session. Both return a
  `redirect_url` that the page must navigate to; `gotrue` 2.27.3 (Dart)
  exposes them as `auth.oauth.getAuthorizationDetails`,
  `approveAuthorization` and `denyAuthorization`, plus `listGrants` and
  `revokeGrant` for the settings screen. A consent call with an `Origin`
  header must come from the Site URL or an allowed redirect URL.
- **Tokens.** ES256 JWTs with `iss = <project>/auth/v1`,
  `aud = "authenticated"`, `role = "authenticated"`, `client_id` and `scope`.
  Supported scopes: `openid email profile phone offline_access`; Supabase
  rejects any other scope, so the server advertises no custom scopes.
- **Audience.** Supabase accepts the RFC 8707 `resource` parameter, checks
  that the token request repeats it, but never puts it into `aud`. A strict
  `aud == <endpoint>` check is therefore impossible without a custom access
  token hook. The MCP spec allows "otherwise verify"; the function requires
  the project's issuer and signature plus a `client_id` claim.
- **MCP 2026-07-28 is a breaking revision.** It drops `initialize` and
  sessions, adds `server/discover`, and requires `MCP-Protocol-Version`,
  `Mcp-Method` and `Mcp-Name` headers. Deployed clients mostly still speak
  2025-11-25. The function uses `createMcpHandler` from
  `@modelcontextprotocol/server` 2.3.1, which serves both eras from one tool
  definition and answers `GET`/`DELETE` with `405` (stateless).
- **Client registration.** The 2026-07-28 spec prefers Client ID Metadata
  Documents and keeps dynamic registration for backwards compatibility.
  Supabase supports pre-registration and dynamic registration only, so
  clients that need CIMD cannot connect yet.

## Tests

- `supabase/tests/personal_access_tokens.test.sql` (pgTAP): hashing, one-time
  plaintext, owner-only visibility, cross-household isolation, one-way revoke,
  token death on leaving the household.
- `supabase/functions/_shared/auth_test.ts`, `mcp/handler_test.ts`,
  `mcp/list_test.ts` (Deno): signature, expiry, audience, issuer and role
  checks; PAT lookup; 401/403 challenges; Origin rules; name matching.
- `e2e/tests/mcp.spec.ts` (Playwright with the MCP SDK client against the
  local stack and the Flutter web build):
  - the full OAuth flow: 401 → metadata → discovery → dynamic registration →
    PKCE through the consent page → token → tools, with the changes
    appearing live in the app;
  - deny returns `access_denied`;
  - a signed-out user signs in on the way and lands back on the consent page;
  - a PAT created in the app works over both protocol eras, and after
    revocation gets `401`;
  - another household's token can neither see nor change the list;
  - app session tokens and forged tokens get `401`.
