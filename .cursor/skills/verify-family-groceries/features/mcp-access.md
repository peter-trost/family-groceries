# MCP access (Zugänge)

Menü → Zugänge shows the MCP server URL, the user's personal access tokens and the AI apps connected over OAuth. A token is shown once when it is created and works as a bearer token at the MCP endpoint (and the Siri endpoint). Revoking a token or disconnecting an app ends its access on its very next request, even though an OAuth access token is valid for an hour.

## Sub-features

- `mcp-url` shows the endpoint `<API URL>/functions/v1/mcp` with a copy button.
- `mcp-pat-create` creates a named token ("Token erstellen"), shows `fgp_…` once, then lists it as `<name> …<last 4>` after "Fertig".
- `mcp-pat-revoke` revokes a token ("<name> widerrufen", then "Widerrufen"); the next MCP call with it gets 401.
- `mcp-apps` lists each OAuth app the user approved, with the date and the scopes.
- `mcp-disconnect` disconnects an app ("<app> trennen", then "Trennen"); the next MCP call with its unexpired access token gets 401.

## How to get to it (user POV)

- On the list screen, tap the menu (tooltip "Menü"), then "Zugänge".
- An app appears under "Verbundene Apps" after the user approves it on the consent page (`/oauth/consent`, web only). On the Linux surface there is no consent page, so the journey grants the app over HTTP as a precondition.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md`; peter signed in on the list. One client is enough.
- For `mcp-apps` and `mcp-disconnect`: an approved OAuth client. `journeys/mcp-disconnect.sh` registers one dynamically and approves it as peter over HTTP: authorize, GET the authorization, POST the consent, then exchange the code with PKCE.

- **Open.** Run `fg tap --tooltip Menü`, `fg wait --text Zugänge`, `fg tap --text Zugänge`. `fg wait --text "Verbundene Apps"` succeeds.
- **Disconnect.** Run `fg tap --tooltip "<app> trennen"`, `fg wait --text "<app> trennen?"`, `fg tap --text Trennen` and `fg wait --text "<app>" --gone`. A `tools/list` POST to the MCP URL with the app's access token now returns 401. `fg db query "select count(*) from auth.sessions where oauth_client_id = '<client id>'"` returns 0.
- **Create a token.** Run `fg tap --text "Token erstellen"`, `fg wait --label Name`, `fg type --label Name --input Siri`, `fg tap --text Erstellen`. `fg wait --contains fgp_` returns the token. It reaches MCP (200). Then run `fg tap --text Fertig`.
- **Revoke a token.** Run `fg tap --tooltip "Siri widerrufen"`, `fg wait --text "Token widerrufen?"`, `fg tap --text Widerrufen`, `fg wait --tooltip "Siri widerrufen" --gone`. The token now gets 401 from MCP. `fg db query "select revoked_at from personal_access_tokens where name = 'Siri'"` is not null.
- **Proof.** Run `journeys/mcp-disconnect.sh`. It prints `PASS` with both status codes and the minutes the OAuth token had left, and saves `mcp-01-connected`, `mcp-02-disconnected` and `mcp-03-token-revoked` plus a recording.

## Gotchas

- Wait for the menu entry and for each dialog's title before tapping. Taps sent during the open animation fail with `not_found`.
- Button labels inside dialogs ("Trennen", "Widerrufen", "Erstellen") are not listed by `fg find`. `fg tap --text` still finds them.
- The created token appears in `fg wait --contains fgp_` output. Keep that output out of committed logs.
- GoTrue only approves an authorization after the user has read it (GET `/auth/v1/oauth/authorizations/<id>`). A consent POST without it returns `oauth_authorization_not_found`.
- Grants pile up across runs (`fg up` keeps data). Use unique app names, as the journey does, or `fg up --fresh`.
