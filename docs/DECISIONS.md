# Decisions

Calls made without a human in the loop, with the reason. Peter can overturn
any of them; each entry says what changing it would touch.

## Job 1 (foundation), 2026-10-22

1. **App identifiers.** Bundle id and applicationId
   `com.petertrost.familygroceries`; display name "Einkauf". Changing them
   touches `app/android/app/build.gradle.kts`, the Xcode project and
   `Info.plist`.
2. **One household per user.** `household_members.user_id` is unique.
   Joining another household moves the user; if they were the last member,
   the old household and its list are deleted (the app warns before joining).
   Peter and Lea share one list, so multi-household support would only add
   a switcher nobody needs.
3. **Invites are codes, never sent.** 8 characters from an alphabet without
   look-alikes (no 0/O/1/I), valid 14 days, reusable until then, revocable
   via `revoked_at`. The app shows the code and a `/join/<code>` link to copy.
4. **Fallback category "Sonstiges".** Seeded as an 11th category (sort order
   1000, `seed_key = 'other'`) so every item always has a category and a
   correction can target it. A trigger forbids deleting it.
5. **Seeded rows carry a `seed_key`.** Categories and stores keep a stable
   identity (`produce`, `drugstore`, `dm`, ...) when renamed, so later jobs
   (store layouts, the classifier dictionary) can address them.
6. **Placeholder classifier in Postgres.** `classify_item(household, name)`
   matches about 60 keywords by exact or suffix match ("Vollmilch" ends in
   "milch"), else the fallback. The items insert trigger calls it when no
   category is given. Job 2 replaces the body; callers do not change.
7. **Klopapier/Toilettenpapier go to Haushalt** in the stub (paper goods
   sit with household goods in Lidl and Edeka). Job 2 revisits this with the
   store layouts.
8. **Quantity is free text.** `items.quantity` holds "2", "500 g",
   "3 Dosen". The app parses a leading amount ("2 Gurken") or a trailing
   amount with a unit ("Hack 500 g"); a bare trailing number stays part of
   the name ("Windeln Größe 4").
9. **History.** Ticked items keep `status = 'bought'` with `bought_at` and
   `bought_by`; the app shows the last 20 under "Zuletzt gekauft" for a
   one-tap re-add. Every insert, tick, restore, edit and delete is also
   written to `item_events` by a trigger (append-only for clients).
10. **Optimistic writes as idempotent ops.** The app applies each change
    locally at once, queues it, and replays it until the server answers.
    Client-generated UUIDs make adds idempotent (`upsert ... ignoreDuplicates`).
    Network errors keep the op queued and retry every 3 s; a refused write is
    dropped and reported. On every realtime (re)subscribe and on app resume
    the app refetches and folds pending ops on top.
11. **Cold start needs the network.** The app keeps no local copy of the
    list yet: offline at launch it shows a spinner and retries until online.
    Changes made while online stay queued across connection loss.
    Tracked in https://github.com/peter-trost/family-groceries/issues/3.
12. **Duplicates.** Adding an item whose name matches an active item
    (case-insensitive) does not add a second row; the app says it is
    already on the list.
13. **State management: flutter_bloc cubits, go_router, no codegen.** Same
    libraries as emotely, without freezed/get_it to keep the app small.
14. **Path URLs on web** (`/join/CODE`, later `/oauth/consent`). Static
    hosting needs an SPA fallback to `index.html` (`e2e/serve.mjs` does this).
15. **Semantics always on for web.** `SemanticsBinding.ensureSemantics()`
    makes the DOM accessible to screen readers and to Playwright.
16. **Flutter web focus workarounds**, found by experiment (see the PR):
    the add field handles a hardware Enter in `Focus.onKeyEvent` instead of
    the text-input action, which otherwise blurs the field and leaves it
    unable to take the next item; the tick checkbox is wrapped in
    `ExcludeFocus` because a focused element that disappears with its row
    leaves the field unable to receive text on the next tap.
17. **No web hosting yet.** The hosted Auth site URL and redirect list wait
    for a public web URL (GitHub Pages is the free candidate); see
    `NEEDS_PETER.md`.
18. **Local stack trims.** Studio, Storage and Analytics are disabled in
    `supabase/config.toml` to fit the shared 15 GB box; enable them locally
    when needed.
19. **pstack models.** `/setup-pstack` ran non-interactively on 2026-10-22
    with budget "large": Opus for code and judgment, Sonnet for swarm
    workers and second opinions (Grok slugs do not exist in Claude Code).
    Written to `~/.cursor/rules/pstack-models.mdc`.
20. **Node 20 on this box.** supabase-js needs a WebSocket for realtime in
    Node < 22, so the e2e helpers pass `ws` as the transport. CI uses Node 22.
21. **Repository location.** The repo moved from `petertrost-bot/family-groceries`
    to `peter-trost/family-groceries` (GitHub redirect seen on the first push,
    2026-10-22). The local remote points at the new URL; nothing else in the
    repo names the owner.
22. **Android APK builds on this box.** `scripts/bootstrap.sh --android`
    installs OpenJDK 21 and the Android command-line tools; `flutter build apk
    --release` then produces `app-release.apk` (56.5 MB, 3.6 min cold). It is
    signed with the debug key until job 4 adds release signing via secrets.

## Job 1 review fixes (review 0), 2026-10-22

23. **`classify_item` is members-only for signed-in callers.** It returned
    another household's category ids to anyone who knew that household's id.
    Migration `20261022190000_classify_item_members_only.sql` raises
    `not_a_member` (42501) when `auth.uid()` is set and is not a member.
    Calls without a user (service role for MCP and Siri, the database
    itself) stay allowed; the items trigger runs as the caller, so member
    inserts are unaffected.
24. **Merge author.** The squash commits `26e9d06` (#1) and `13dfe23` (#2) on
    `main` carry `petertrost-bot <bot@petertrost.com>`, the account's default
    email, instead of the required
    `341616691+petertrost-bot@users.noreply.github.com`. `main` is not
    rewritten (no force-push). GitHub rejects the noreply address as a merge
    `--author-email` ("Invalid email address"), so `scripts/merge-pr.sh`
    squashes the PR locally into one commit authored with the noreply address
    and titled "<PR title> (#n)", pushes it to the PR branch, and once
    `ci-ok` passes on it, rebase-merges it. A rebase merge keeps the commit
    author, and one commit keeps `main` as linear as a squash merge.
    One slip while building this: commit `008e2b0` (adds only
    `scripts/merge-pr.sh`) was pushed straight to `main` after a failed
    branch checkout left the shell on `main`. It was a fast-forward, not a
    force-push; it stays, and CI ran on it like any `main` push.
25. **Input length caps in the app.** The add field and the edit sheet cap the
    name at 120 characters and the quantity at 40, matching the table checks,
    so a long paste no longer ends in a server rejection.
26. **No pstack config in the repo.** `/setup-pstack` writes only the
    per-user rule `~/.cursor/rules/pstack-models.mdc` (see #19); the repo
    carries none by design.
27. **Node 20 stays on this box.** Bootstrap does not replace the system
    Node, because other workloads share the box. CI runs Node 22. The
    supabase-js deprecation warning in local Playwright runs is expected.

## Job 1b (Sign in with Google and Apple), 2026-10-22

1. **Flows.** Google is native on iOS and Android, and Apple is native on
   iOS; both use `signInWithIdToken`. Apple on Android and both providers on
   web use the OAuth redirect with PKCE. These are the flows Supabase
   documents. google_sign_in on web cannot hand an ID token to our own
   button. Details in `docs/AUTH.md`.
2. **Nonce check on, one Google nonce per app run.** google_sign_in's
   `initialize` (the only place its nonce goes) may run once per process,
   so Google gets one random nonce per app run and Apple gets a fresh one
   per attempt. `skip_nonce_check` stays false. If real iPhones ever return a
   cached token with an old nonce, the fallback is `skip_nonce_check = true`
   for Google only.
3. **No google_sign_in app package.** The app depends on
   `google_sign_in_platform_interface` plus the Android and iOS
   implementations. The app-facing package would add `google_sign_in_web`,
   which loads Google's script on every page view of the web app (seen in
   the Playwright network log) although web signs in by redirect. Without
   it, no request goes to Google before the user taps the button. The cost
   is the platform interface's slightly lower-level API in
   `plugin_sign_in.dart`.
4. **Configuration is public client IDs in `app/config/auth.json`,** read
   with `--dart-define-from-file`. An empty value hides the button. Secrets
   live only in Supabase. The iOS reversed client ID also has to be in
   `ios/Flutter/Auth.xcconfig` because `Info.plist` is static; a unit test
   keeps the two files in step.
5. **Apple's name.** The app stores it with `updateUser` on the first native
   sign-in. A trigger copies `full_name` into `profiles.display_name` while
   the profile still has the derived name. A failed `updateUser` does not
   fail the sign-in, because the user is already signed in at that point.
6. **Hosted config by script, never invented.** `scripts/configure-social-auth.mjs`
   enables a provider only when its credentials are in the environment.
   Run on 2026-10-22 without provider credentials, it added only the app's
   deep link to the redirect allow list.
7. **Mobile deep link `com.petertrost.familygroceries://login-callback`**
   for Apple on Android and for magic links on the phones. Before this job,
   mobile magic links went to the site URL, which is the web app.
8. **Local test provider.** `[auth.external.keycloak]` in `config.toml`
   points at `e2e/fake-oidc.mjs` on `host.docker.internal:54399`. GoTrue
   runs the same ID-token, nonce and linking code for it as for Google and
   Apple, whose issuers are hard-coded. Its signing key comes from a fixed
   seed, so parallel worktrees can share one running copy. The deploy
   workflow does not push `config.toml`; never enable this provider on the
   hosted project.
9. **Button label "Mit Google anmelden"** as the brief asks. Google's German
   guideline page prefers „Über Google anmelden“ but allows localized
   labels. The Google "G" was cut from Google's 2026 asset kit with Chromium
   (transparent PNG at 1x, 2x and 3x).
10. **Cancel is reported.** A canceled provider dialog or `access_denied` on
    the return URL shows "Anmeldung abgebrochen", as the brief asks.
    Supabase's examples treat it as silent.

## Job 3 (MCP server, OAuth 2.1, personal access tokens), 2026-10-22

Numbered 3.x so parallel jobs don't collide. Details and sources: `docs/MCP.md`.

3.1. **Tools run as the user, not the service role.** `_shared/db.ts` opens one
     Postgres transaction per tool call on `SUPABASE_DB_URL` with role
     `authenticated` and `request.jwt.claims.sub` set to the caller. RLS,
     triggers and `classify_item` (members-only since #4) behave as for the
     app, and a missing household filter cannot leak another household's data.
     The alternative, the service role with explicit `household_id` filters,
     would have made every query a possible leak and given `auth.uid()` no
     value in triggers.
3.2. **Audience check = issuer + signature + `client_id`.** Supabase ignores
     RFC 8707 `resource` for `aud` (always `authenticated`; verified on a real
     token). The MCP endpoint accepts a JWT only with the project's issuer,
     a JWKS signature (ES256/RS256), `role = authenticated` and a `client_id`
     claim, so a token issued to the app is not accepted. `authenticate()`
     still reports app session tokens as `via: 'session'`, because job 4's
     voice endpoint is called by the app itself.
3.3. **Both MCP protocol eras.** The latest spec (2026-07-28) is breaking:
     no `initialize`, no sessions. `@modelcontextprotocol/server` 2.3.1's
     `createMcpHandler` serves it and 2025-era clients from one tool
     definition, stateless, `GET`/`DELETE` → 405. A fresh server per request
     keeps the authenticated caller in a closure, not in shared state.
3.4. **Protected Resource Metadata under the function path.** An edge function
     cannot serve `https://<ref>.supabase.co/.well-known/…`, so the metadata
     lives at `<endpoint>/.well-known/oauth-protected-resource` (and at
     `<endpoint>/oauth-protected-resource`, Supabase's own helper path). The
     `WWW-Authenticate` header points at it, which the spec lists first.
3.5. **Advertised scopes `openid email`.** Supabase rejects custom scopes, and
     the tools need none; household access comes from membership.
3.6. **Origin check with an allowlist.** Browser requests must come from the
     project host, localhost, or `MCP_ALLOWED_ORIGIN_HOSTS`; requests without
     an `Origin` (all native and server-side clients) pass. CORS stays open,
     because no cookies are involved.
3.7. **Personal access tokens.** Format `fgp_` + 32 random bytes, base64url.
     The table stores a SHA-256 hash (no salt or slow hash needed: the token
     has 256 bits of entropy) and the last four characters. A token acts as
     its creator in the household it was created in, and stops working when
     the creator leaves it. At most 20 active tokens per user. Revocation is
     one-way (trigger). Revoked tokens are hidden in the app.
     The cross-household cases for this table live in
     `supabase/tests/personal_access_tokens.test.sql`, not `rls.test.sql`,
     to stay out of other jobs' merge conflicts.
3.8. **Consent survives sign-in.** `authRedirect` carries the consent URL as
     `next` through `/login` and `/welcome`. Only a same-origin
     `/oauth/consent` URL is accepted, so `next` cannot become an open
     redirect.
3.9. **Settings screen "Zugänge"** (menu entry) holds the MCP URL, the tokens
     (create, shown once, revoke) and the OAuth grants (`listGrants`,
     `revokeGrant`), so a connected assistant can be disconnected without
     the dashboard.
3.10. **`add_items` through the items insert path for now.** MCP inserts rows
      without a category, so the items trigger calls `classify_item`. Job 2's
      `public.add_items` RPC replaces this inside `mcp/list.ts` `addItems()`
      once it is on main.
3.11. **Local edge runtime policy `oneshot`.** With `per_worker`,
      `supabase start` reuses one worker until its 1 s CPU soft limit, then
      ends it, and requests in flight fail with 503 after about 13 s (seen as
      "CPU time soft limit reached" in the edge runtime log; it failed one in
      four full e2e runs). `oneshot` starts a worker per request, which
      matches the hosted per-request CPU limit. Three full runs were clean
      afterwards.
3.12. **Local DB host alias.** Under `supabase start`, `SUPABASE_DB_URL` names
      the host `supabase_db_<project>`, which Deno's resolvers reject
      (underscore). `_shared/db.ts` maps it to the container alias `db`.
      Hosted URLs are unaffected.
3.13. **Remote OAuth server enabled through the Management API**
      (`SUPABASE_ACCESS_TOKEN` was available): OAuth server on, dynamic
      registration on, authorization path `/oauth/consent`. The project
      already signed with ES256. Deploying the function and migrations is
      still Peter's step (no DB password on the box), see `NEEDS_PETER.md`.
