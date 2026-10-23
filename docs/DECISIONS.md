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

## Job 2 (classifier and stores), 2026-10-22

28. **One item key for the classifier and both memories.** `public.item_key(name)`
    lowercases the name and folds umlauts and accents (`ä` and `ae` both become
    `a`). It turns `ß` into `ss`, drops quantities with units and percentages,
    and turns punctuation into spaces. Then it stems each word by stripping one
    plural ending (`-n` after e/l/r, then `-e`, then `-s`). So "2 kg Äpfel" and
    "Aepfel" share the key `apfel`, and so do Gurke and Gurken. Plurals in
    `-er` (Eier, Kräuter) are not reduced, so the dictionary lists both forms.
    The key is a matching key, never shown.
29. **Pipeline order: memory, dictionary, fallback.** `classify_item` checks
    the household's learned memory by exact key first. Then it checks the
    dictionary, and the first rule that matches wins:
    1. A multi-word phrase found in the name.
    2. The whole name is a term.
    3. A frozen marker. "TK", or a word starting with Tiefkühl, tiefgekühlt
       or gefroren, sends the item to Tiefkühl, so TK-Spinat is not produce.
    4. Per word, the longest term the word ends with (compound heads:
       Vollmilch → milch).
    5. The longest term of four or more letters the word starts with.

    When matches tie, the later word wins, because the head of a German
    noun phrase comes last. Terms under three letters (ei, öl) only match
    whole words. Anything else goes to "Sonstiges". Pet food is Haushalt.
30. **Learning lives in a trigger, not in the callers.** An `UPDATE` that
    changes `items.category_id` is a correction. It goes into
    `category_memory` keyed by item key and category, with a count, and the
    latest correction wins. The edit sheet's category picker and drag between
    groups both write that column, and so will MCP's move tool. Edits that
    keep the category teach nothing. Moves caused by deleting a category teach
    nothing either (a transaction-local `family_groceries.learning = off`).
31. **Dictionary as a TSV plus a generated migration.** The reviewable file is
    `supabase/classifier/dictionary.tsv`. `generate.ts` writes it into a
    migration, and a Deno test in CI fails if the newest
    `*_classifier_dictionary*.sql` migration differs from the TSV. To change
    the dictionary: edit the TSV, create a new migration, and run the
    generator on it. A migration already on `main` is never edited.
32. **Tea and coffee are Vorrat; plant milks are Kühlregal.** This follows
    where Lidl and Edeka shelve them: coffee and tea sit with the dry goods,
    oat and soy drinks sit next to milk. Ready-to-drink tea (Eistee) is
    Getränke. Baby food jars and porridge are 👶 Drogerie, like the baby aisle.
33. **Klopapier stays in Haushalt** (#7 revisited). Toilet paper sits with the
    paper goods in Lidl and Edeka, and dm shows Haushalt in its view, so
    untagged toilet paper still appears when shopping at dm.
34. **Store layouts.** The defaults come from store reports and are documented
    with sources in `docs/STORE_LAYOUTS.md`. Every store has a row for every
    category, with a `hidden` flag for categories the store does not carry.
    dm hides produce, bakery, chilled, meat and frozen. A new category goes
    after the last shown category in each store, or just before Sonstiges
    when Sonstiges is the last shown one.
35. **Store views.** A store view shows the items tagged to that store plus
    the untagged ones, in the store's order. An untagged item in a category
    the store hides is left out. A footer counts these items and can show
    them. An item tagged to the store always shows. Items tagged to another
    store never show.
36. **Item→store memory.** It is learned from two things. Ticking an item off
    inside a store view tags the item with that store. Choosing a store in
    the edit sheet tags it by hand. Both write `items.store_id`, and the
    trigger records it, latest wins. A new item with no store gets the
    remembered store. Setting "Alle Geschäfte" in the edit sheet clears the
    memory, which means the item can be bought anywhere again. An item typed
    inside a store view is tagged with that store, so it stays visible where
    it was typed. Typing it in "Alle" leaves the memory in charge. A consequence: an
    untagged item ticked off at Lidl is a Lidl item from then on. It no longer
    shows in the Edeka or dm view until someone retags it in the edit sheet
    (or sets "Alle Geschäfte").
37. **The store picker resets to "Alle" on launch.** Planning at home happens
    in "Alle", and the picker is one tap away in the store. It sits under the
    add field and never takes focus, so autofocus on open is unchanged.
38. **Deleting a category moves its items** (active and bought) to a category
    the user picks, by default Sonstiges, which cannot be deleted. The
    category's learned corrections go with it. Its seed identity passes to the
    target (`categories.absorbed_seed_keys`), so dictionary hits for a deleted
    "Tiefkühl" land where its items went instead of in Sonstiges.
39. **`add_items` is the shared add path for MCP and Siri** (announced on the
    job board). Each entry may carry a quantity, which `public.parse_entry`
    parses with the same rules as the app's `parseEntry`. An entry whose item
    key is already active returns the existing row instead of a duplicate.
    `p_store` tags the new items. Without it, the remembered store applies.

## Job 4 (voice and release), 2026-10-22

<!-- job4-voice -->
- **Voice splitting lives in the `voice` edge function** (`parse.ts`), not
  in SQL: a token-based splitter with table-driven Deno tests (about 200
  sentences, plus a 759-sentence adversarial pass). Siri and the in-app
  mic share it; the app calls it with `mode: "parse"` and adds the entries
  through its own optimistic ops, so dictated items behave like typed ones
  (instant, offline-queued, duplicates refused).
- **Siri gets plain text.** `?format=text` answers with the sentence only,
  so the Shortcut is exactly Diktieren → Inhalte von URL abrufen → Text
  sprechen with no dictionary step. Errors also come back as German
  sentences with a matching HTTP status, so Siri speaks them too.
- **The voice function checks its own bearer token** (`verify_jwt = false`):
  PATs are not JWTs. It accepts PATs and app session JWTs through the shared
  `authenticate()` and writes as the user (role `authenticated`), so RLS,
  triggers and the classifier run exactly as for the app.
- **Items already on the list are not added twice** and Siri names them
  ("Schon auf der Liste: Milch."). An amount said after a comma joins the
  item before it ("Äpfel, ein Kilo" → 1 kg Äpfel).
- **"Kein Zucker" becomes "Zucker".** Leading "kein/keine" is dropped,
  because "Wir haben keine Milch mehr" is how people say it; a negative
  entry on a shopping list is not a real use.
- **No mic on web.** The browser's Web Speech API sends audio to Google's
  servers and is not on-device; typing is the web fallback. iOS and
  Android use the platform recognizer through `speech_to_text` in de-DE
  (free, no API key). On-device recognition is not forced, so devices
  without a German offline model still work.
- **The Android release build declares INTERNET.** Flutter's template grants
  it only to debug and profile builds; a release APK could not reach
  Supabase without it.
- **Shortcut name "Einkaufsliste"**, as the brief asks. If Siri routes that
  to Reminders' grocery list, `docs/SIRI_SHORTCUT.md` suggests
  "Einkauf notieren".
- **The list is cached on the device** (closes #3, supersedes #11). A
  versioned `ListSnapshot` (catalog with stores and layouts, server rows,
  pending `ItemOp`s) lives in shared preferences per user and household,
  next to each user's last household. A start without network opens that
  household and its list with the offline indicator; the usual resync and
  flush take over once Supabase answers, and replayed ops are harmless
  because they are idempotent (#10). A change to the queue is saved at
  once, server churn 300 ms after it settles. Signing out drops the whole
  cache; a household switch or leaving drops the user's other lists, and a
  list only saves while it is the user's current household, so a closing
  list cannot write a stale copy back. An access token that expired while
  offline no longer signs the user out: the failed refresh is retried by
  supabase_flutter, which keeps the session.

- **Duplicates compare `item_name_key`, the memory keeps `item_key`**
  (review 0). `item_key` drops every number, so "Windeln Größe 5" counted as
  already on the list after "Größe 4". `add_items` and MCP now compare
  `item_name_key` (`item_key` plus the numbers left in the name); the
  classifier and store memory still use `item_key`, so sizes share a
  learned category. Migration `20261023070910_item_name_key.sql`.
- **More than 30 items in one sentence**: the first 30 are added and Siri
  says the rest was not taken ("Mehr als dreißig auf einmal gehen nicht …");
  the JSON answer has `truncated: true`.

<!-- job4-release -->
- **Releases are manual.** The Release workflow runs only from the Actions
  tab, not on every merge like emotely: two users do not need a build per
  merge, and each run costs macOS minutes. Build numbers stay
  `1000 + run number`.
- **Missing release secrets skip, not fail.** Same rule as the Supabase
  deploy workflow: until Peter finishes the store setup, a run is green and
  names the missing secrets in a notice.
- **Team ID and match repo URL come from the environment**
  (`APPLE_TEAM_ID`, `MATCH_GIT_URL`), so the public repo holds no account
  identifiers and the export options are generated by the lane.
- **Release signing falls back to the debug key** when
  `android/key.properties` is absent, so local release builds need no
  secrets. Proven on the box with a throwaway keystore under `/tmp`.
- **The icon is generated** by `scripts/icons.py` (white basket on the theme
  green `#2E7D32`), including an Android adaptive icon with a monochrome
  layer, instead of adding `flutter_launcher_icons` to `pubspec.yaml`.
- **iOS builds are unverified on this box.** Linux cannot run Xcode; the iOS
  lane is checked only by `fastlane lanes` parsing it and by mirroring
  emotely's working lane.

## Job 5 (verification skill), 2026-10-23

5.1. **Primary surface is the Linux desktop debug app, not the Android
     emulator, on the build box.** Creating a KVM vCPU on this VM hits
     `kernel BUG at arch/x86/kvm/x86.c:702` (`vmx_vcpu_create`; three oopses,
     kernel tainted). Retrying risks the shared host, so
     `~/.config/fg/kvm-broken` records it and `fg` refuses the emulator while
     the marker exists. The same Flutter app (same widget tree, the same
     Marionette binding) runs as a Linux desktop window on Xvfb. It is real
     native Flutter, not a browser. Android stays fully implemented in `fg`
     for machines with a working emulator and is listed as unverified.
5.2. **`app/linux/` added** (`flutter create --platforms linux`, application
     id `com.petertrost.familygroceries`, phone-sized 412×892 window). Needed
     for 5.1; it also makes the app runnable as a desktop app.
5.3. **Marionette entrypoint `app/test_driver/main_marionette.dart`;
     `marionette_flutter` is a dev dependency.** Same pattern as
     flutter_driver's `test_driver/app.dart`. Code under `lib/` cannot import
     it (`depend_on_referenced_packages` fails `flutter analyze`). Release
     builds use `lib/main.dart`; a release `libapp.so` has no Marionette
     strings (checked). The entrypoint throws if built in release mode.
5.4. **One CLI (`scripts/fg` → `.cursor/skills/verify-family-groceries/fg`,
     Deno) instead of markdown recipes.** Deno is already in the toolchain
     and CI. Commands are one table (help, flags, `--dry-run`, JSON errors
     generated from it), and every process call goes through an injectable
     shell, so the CLI's own tests run without a stack (16 tests in CI).
5.5. **Supabase runs from a generated workdir** (`~/.cache/fg/<prefix>/stack`:
     config.toml with the port lines and project id rewritten, symlinks to
     migrations, functions and tests). Parallel agents never edit the tracked
     `config.toml` to get their own instance.
5.6. **Seeded users** `peter@fg.test` and `lea@fg.test` (password
     `test-password-123`, local only) in "Familie Test", created through the app's
     own RPCs (`create_household`, `create_invite`, `join_household`).
5.7. **Second client is a second real app** (two Linux instances, about
     650 MB each) with separate session storage via `XDG_*` dirs. `fg peer`
     (REST and Realtime as a user) is the light alternative, and the only
     one when the primary client is the emulator.
5.8. **Debug builds allow cleartext HTTP**
     (`app/android/app/src/debug/AndroidManifest.xml`) so the emulator can
     reach `http://10.0.2.2:<port>`. Release keeps Android's block.
5.9. **`flutter.inspector.structuredErrors=false` in fg builds.** Otherwise
     debug builds send Flutter errors only to the VM service, and `fg logs`
     would show nothing for a red error screen.
5.10. **Minimal ValueKeys** only where Marionette cannot reach a field by
      text: `login-email`, `login-password`, `household-name`, `invite-code`,
      `add-item-field`. Buttons are reached by their text; keyless fields by
      label (`fg type --label`).

## Job 3b (MCP follow-ups), 2026-10-23

3b.1. **Disconnect = session check per request.** Supabase's OAuth server
      cannot revoke an issued access token: its discovery document has no
      revocation or introspection endpoint. `revokeGrant` does delete the
      client's `auth.sessions` rows. `authenticate()` now accepts a JWT only
      while `auth.sessions` has its `session_id` for that user and
      `oauth_client_id`, and answers `401 invalid_token` otherwise. That is
      one primary-key lookup per request, run in parallel with the
      household lookup. Asking `/auth/v1/user` would also notice the missing
      session, but costs an HTTP round trip through Auth. Shorter token
      lifetimes would only shrink the window. App session tokens get the
      same check, so signing out also ends the voice endpoint's access.
3b.2. **MCP `add_items` calls `public.add_items` once per item.** That keeps
      the per-item `store` and the order of results. An explicit `quantity`
      overwrites the parsed one (an update that teaches nothing). An
      explicit `category` is applied as an update after the add, so the
      items trigger learns it. The tool tells assistants to send it only
      when the user names a category, so it is the user's correction.
      Supersedes 3.10.
3b.3. **Each checkout's e2e run uses its own port block.** `e2e/stack.ts`
      reads the URL, key and Mailpit URL from the environment or from
      `supabase status` and throws when one is missing, with no 543xx
      default. The web server port defaults to `<API port prefix>80`
      (54321 → 54380, 54621 → 54680). Before, all checkouts used 3100 with
      `reuseExistingServer`, so one job could test another job's build.
      `config.toml` allows loopback redirects on any port for this. The
      fake identity provider runs on the port of the Keycloak URL in the
      checkout's `config.toml` (`<prefix>99`). Before, every job used 54399
      with `reuseExistingServer`, and a run failed when the job owning the
      server finished (seen here: `ECONNREFUSED 127.0.0.1:54399` in 6
      id-token tests).
3b.4. **Playwright runs one worker locally** (CI keeps 2). With 3 workers,
      mem-guard paused this job for 45 s during a run (low RAM), and the
      paused MCP request timed out the test.

## Job 7 (Vercel hosting, auth config, API-only deploy), 2026-10-23

7.1. **Vercel hosts the web app** (Peter's decision, 2026-10-23 10:58,
     instead of GitHub Pages). A Git-linked Vercel project builds every push
     from `vercel.json`; production is `main`. The app is served at the
     domain root, so `WEB_BASE_PATH` and the Pages workflow are gone.
7.2. **The Flutter SDK lives in `node_modules/.flutter`.** Vercel's build
     cache keeps only `node_modules/**`. The SDK is a shallow clone of the
     version in `ci.yml` (one source for CI and Vercel); the pub cache sits
     next to it. Measured in Amazon Linux 2023 (`scripts/vercel-local.sh`):
     cold install 50 s, cached install 20 s, build 35 s. SDK plus pub cache
     are 1.55 GB uncompressed against Vercel's 1.5 GB cache limit; whether
     the compressed cache fits is unknown until the first Vercel builds. If
     it does not, every build pays the 50 s cold install.
7.3. **SPA rewrite for extensionless paths only.** `/oauth/consent`,
     `/join/CODE` and `/settings` serve `index.html`; a missing `.js` or
     `.png` stays a 404 instead of HTML that the browser would try to run.
7.4. **Cache headers.** Flutter's output is not content-hashed
     (`main.dart.js` keeps its name), so every file revalidates
     (`max-age=0, must-revalidate`, Vercel serves ETags), and the app routes,
     `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`,
     `version.json` and `manifest.json` are `no-cache`.
7.5. **The Vercel build refuses a wrong key.** `SUPABASE_URL` must be
     `https://<ref>.supabase.co` and `SUPABASE_PUBLISHABLE_KEY` must start
     with `sb_publishable_`; a missing or secret-looking value fails the
     build instead of shipping the compiled-in defaults.
7.6. **Edge function import maps via `config.toml`.** `supabase functions
     deploy --use-api` bundles only the uploaded files and never saw
     `supabase/functions/deno.json`, so bare imports (`jose`,
     `@modelcontextprotocol/server`) failed. Each `[functions.<name>]` now
     sets `import_map = "./functions/deno.json"`: one map shared with
     `deno test`/`lint`, no per-function copies to drift.
     `supabase/deploy/config_test.ts` fails for a function directory without
     it (checked: it fails on the old config).
7.7. **Migrations deploy through the Management API**
     (`supabase/deploy/migrate.ts`). This box and an API-only workflow have
     no Postgres connection. Each pending migration runs with its
     `supabase_migrations.schema_migrations` row (repo version and name) in
     one transaction, so `supabase migration list` and `db push` see the same
     history. Checked against the local database: a migration that fails
     leaves neither its objects nor its row, and the CLI lists an applied one.
     It stops on drift: a remote version missing locally, or a pending
     migration older than the newest remote one (rename it, as
     COORDINATION.md says).
7.8. **The Supabase deploy workflow fails without credentials.** It needs
     only `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` (no database
     password, no Docker) and ends with a smoke test of `health` and the MCP
     metadata. Before, missing secrets skipped every step and the run showed
     green in 6 s.
7.9. **Production redirect list has no localhost entries.** Earlier notes
     suggested `http://localhost:3000/**`; local development uses the local
     stack, and a localhost redirect on production would hand tokens to
     whatever runs on that port. `supabase/deploy/auth_urls.ts` sets the
     Site URL, the redirect list and the consent path and keeps entries added
     by hand.
## Job 2b (follow-ups to jobs 2 and 5), 2026-10-23

2b.1. **Bags and brand names have dictionary entries.** `-tüte` and
      `-beutel` are Haushalt (Mülltüten, Gefriertüten, Zipbeutel); Teebeutel,
      Windelbeutel and Filtertüten stay where explicit entries put them.
      Common cleaning and drugstore brands (Somat, Frosch, Lenor, Elmex,
      Blend-a-med, Penaten) stand for their product. `kleber` is listed so
      Sekundenkleber stops matching `leber` (Fleisch). Briefmarken stays
      Sonstiges: stamps have no supermarket aisle, as the dictionary test
      already said. Kaffeefilter and Filtertüten sit with the coffee
      (Vorrat), Hustenbonbons with sweets. Found with a sweep of 345 common
      non-food items through `classify_item`; 45 of the fixes are rows in
      `supabase/tests/classifier_dictionary.test.sql`.
2b.2. **The classifier folder has its own `deno.json`.** CI and
      `scripts/verify.sh` run `deno fmt --check && deno lint && deno test`
      inside `supabase/classifier`, the same command a developer runs there.
2b.3. **Screenshots wait for two identical frames.** Flutter animates on
      its canvas, which Playwright's `animations: 'disabled'` cannot reach.
      The grey Edeka chip in job 2's `06-store-dm.png` was the chip's
      deselect animation, not hover: the dm chip was mid fade-in in the same
      frame. `screenshot()` (e2e helpers) now polls until two frames 100 ms
      apart agree (2 s cap).
2b.4. **Each resync keeps its own ack map.** The list opens with two
      resyncs at once (start, and the channel's first `subscribed`). They
      shared one nullable map; the first to finish nulled it and the other
      threw, so the list showed Offline until the next write (3/3 menu joins
      on the web build, 2/3 creates on the Linux app). A resync that answers
      now also brings the list back online, but only while the realtime
      channel is subscribed, so a dead channel still shows Offline.
2b.5. **No postgrest GET retries.** postgrest 2.9.1 retries each GET three
      times (1 + 2 + 4 s), invisibly. The session and list cubits already
      retry every 3 s and writes are idempotent ops retried until acked, so
      the library retries only delayed an offline cold start (7.7 s to the
      cached list, 15 s to the Offline indicator; now 0.7 s). The option
      only reaches `client.rest` (`client.from` builds its query builder
      without it), so the app reads and writes through `client.rest`.
2b.6. **e2e tests close the contexts they open.** Specs open one context
      per user with `browser.newContext()` and the browser lives for the
      worker, so every earlier test's app kept running: 48 renderers and
      9.4 GB RSS by the end of a one-worker run. That load was the "OAuth e2e
      flake" (a consent test waited 34 s for its first page) and much of the
      box's memory pressure. `e2e/tests/fixtures.ts` extends `test` with an
      auto fixture that closes them; `conventions.spec.ts` fails if a spec
      imports `test` from `@playwright/test` directly. mcp.spec's
      `retries: 1` (job 4) is gone.
2b.7. **A catalog reload awaits before it reads the state.**
      `emit(state.copyWith(catalog: await fetch()))` evaluated `state` before
      the await and wrote the old pending ops and server rows back. An add
      acked during the fetch came back as pending forever (1 in 20 runs of
      offline-start), and an op queued during it could vanish unsent.
2b.8. **The web bootstrap reloads once a boot asset load fails.** Chromium
      aborts in-flight requests with `ERR_NETWORK_CHANGED` when the host's
      interfaces change; Chromium declines to make that configurable. One
      aborted `canvaskit.js` or `main.dart.js` left a blank page with no
      error. `app/web/flutter_bootstrap.js` reloads, at most twice per tab
      session (sessionStorage), and catches a failed `main.dart.js` with a
      capture-phase listener because the loader's callback mode ignores the
      script tag's error. On this box Docker bridges from other jobs' stacks
      trigger it; for users a Wi-Fi or VPN switch during load does.
2b.9. **The list resyncs when Realtime says it is live.** Realtime confirms
      the channel join before its Postgres listener runs and announces it
      later with a `system` event ("Subscribed to PostgreSQL", 2.5 s after
      the join on this stack). A change in between was never delivered, so
      an item added by voice or MCP right after the list opened stayed
      missing (seen in a full e2e run, and around the local stack's periodic
      "tenant terminated: rebalancing"). `watch()` now reports that event as
      online, which resyncs. `realtime_client` already turns a `system`
      error into `channelError`, which shows Offline.

## Job 4b (voice follow-ups), 2026-10-23

4b.1. **DeviceCache writes its own file on Linux** (`device_cache.json`, via
      `SharedPreferencesLinuxOptions`). supabase_flutter keeps the session
      through the legacy `SharedPreferences`, the cache uses
      `SharedPreferencesAsync`, and on Linux both plugins hold their own
      in-memory copy of `shared_preferences.json` and rewrite the whole file
      on each write, so a cache write dropped the session (relaunch came back
      signed out). Android, iOS and web ignore Linux options, so their stores
      and keys are unchanged. Not migrated: Linux is a debug target, and the
      household/list keys left in the old file are a cache that refills on
      the next online start.
4b.2. **Dictation is on-device only** (spec), superseding the job 4 note
      "on-device recognition is not forced". `speech_to_text` 7.5 with
      `onDevice: true` is strict on iOS (`requiresOnDeviceRecognition`) but on
      Android silently uses the network recognizer when on-device
      recognition is unavailable, and on iOS it answers a device without
      on-device German twice. So the app asks first, over its own channel
      `familygroceries/speech` (`MainActivity.kt`, `AppDelegate.swift`): iOS
      `SFSpeechRecognizer(de_DE).supportsOnDeviceRecognition`; Android API 31+
      `isOnDeviceRecognitionAvailable` and, on 33+, German among the installed
      on-device languages. Without it the mic explains in German that the
      offline German recognizer is missing and listens to nothing. An Android
      12 device without German reports `error_language_*` once listening
      starts; that gets the same message. Not 7.6.0-beta.4's
      `hasOnDeviceSupport`: a beta, and its Android answer ignores the
      language.
4b.3. **The mic shows on iOS and Android only.** Linux and web have no
      on-device recognizer; the Linux build used to show a button that could
      only fail.
4b.4. **CI compiles the native code** (`android-build`: debug APK on
      Ubuntu; `ios-build`: simulator debug build on macOS, free for public
      repositories). The app now has its own Kotlin and Swift, and nothing
      compiled them before.
4b.5. **Offline start: cache first, and list reads fail fast.** Review 1's
      offline-start failure was the cached list missing 10 s after an offline
      reload. Measured: the list appeared 7.6 s after the reload and
      "Offline:" 7.3 s later. postgrest-dart 2.9 retries every GET three
      times on network errors (1, 2 and 4 s), and `SupabaseClient.from()`
      ignores `postgrestOptions.retryEnabled` (supabase 2.16.5), so the
      session's household lookup and the list fetches each took about 7 s to
      fail. Now SessionCubit opens the device's household before it asks the
      server, and the list reads and the household lookup use
      `.retry(enabled: false)`: ListCubit and SessionCubit retry on their own
      every 3 s. After: list 0.5 s, banner 0.6 s after an offline reload.
4b.6. **Review 1's three e2e failures had one trigger.** The run (09:27 to
      09:37) was frozen by mem-guard from 09:30:38 to 09:35:04 (SIGSTOP,
      `mem-guard.log`), and with 3 workers exactly three tests were in
      flight; each failed after 4.6 to 4.8 minutes on wall-clock timeouts.
      Fixes for what made them fragile: 4b.5 for offline-start, 3b.3 (own
      fake OIDC port) for social-sign-in, and one worker locally (3b.4).
4b.7. **merge-pr.sh ends the squashed message with Peter's trailer**
      (COMMON.md: every commit message ends with it) and re-squashes a head
      that doesn't. Before, the Claude trailer came last.
4b.8. **The ops DONE_SUMMARY.md is a copy of `docs/done/<job>.md`**
      (COORDINATION.md), byte for byte; the root `DONE_SUMMARY.md` only links
      it. Job 4's repo copy gained the "Merged as PR #10" line its ops copy
      already had.
