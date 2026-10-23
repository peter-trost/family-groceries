# Job 4: Siri endpoint, in-app dictation, release setup, final pass

PR: https://github.com/peter-trost/family-groceries/pull/5

## What was built

- **Voice endpoint** (`supabase/functions/voice/`). `POST /functions/v1/voice`
  with `{"text": "Milch, zwei Gurken und Klopapier"}` and a Bearer token
  (personal access token, app session or OAuth token, via job 3's
  `authenticate()`). It splits the sentence, adds the items through job 2's
  `add_items` as the caller (RLS, classifier memory, store memory, duplicate
  check), and answers `Hinzugefügt: Milch, 2 Gurken, Klopapier.`
  `?format=text` returns only that sentence, for Siri. Items already on the
  list are named ("Schon auf der Liste: Milch."). Errors come back as German
  sentences with a matching status (400, 401, 403, 405, 413, 422, 500).
  `mode: "parse"` only splits, for the app's mic.
- **German splitter** (`parse.ts`, 181 table cases). Separators (comma, und, sowie, noch,
  auch, außerdem, plus, `+`, `;`, `:`), filler before and after items (bitte,
  wir brauchen, kannst du, schreib auf, auf meine Einkaufsliste, nicht
  vergessen, ist alle, …, generated from a small grammar), number words
  (zwei, zwölf, fünfundzwanzig, zweimal, halber), digits (1,5, 1.000, 3x),
  units (kg, Kilo, g, l, Packung, Dose, Kasten, Flasche, Bund, …), articles,
  amounts after the item ("Eier zehn Stück", "Äpfel, ein Kilo"), and numbers
  that belong to the name (Windeln Größe 4, Mehl Typ 405, Milch 1,5 %).
- **Siri Shortcut guide in German** (`docs/SIRI_SHORTCUT.md`): token in the
  app, then Text diktieren → Inhalte von URL abrufen (POST, JSON,
  Authorization header) → Text sprechen, the phrase "Hey Siri,
  Einkaufsliste", what to say, and what each error sentence means.
- **In-app dictation.** A mic button next to the add field (iOS and Android)
  listens in de-DE with `speech_to_text`, shows the words while you speak,
  sends the sentence to the voice splitter and adds each entry through the
  app's optimistic ops. Offline, the sentence stays in the field. Web hides
  the mic (the browser API is not on-device). German permission strings in
  `Info.plist`; `RECORD_AUDIO` on Android.
- **Release setup**, adapted from emotely (`docs/REUSED_FROM_EMOTELY.md`):
  `app/fastlane` lanes `ios beta` (match, App Store Connect API key,
  TestFlight) and `android internal` (Play internal track), build number
  1000 + run number; Android release signing from `key.properties` with a
  debug fallback; `.github/workflows/release.yml`, manual, each platform
  skipping with a notice until its secrets exist; a fastlane parse job in
  CI; a new app icon (`scripts/icons.py`). `docs/RELEASE.md` explains it.
- **Web deploy** (`.github/workflows/web-deploy.yml`): GitHub Pages, manual,
  skips until Pages is enabled. The app takes a `WEB_BASE_PATH` so sign-in
  and invite links work under `/family-groceries`.

## Final pass: issues found and fixed

- **Android release builds had no INTERNET permission** (Flutter's template
  grants it only to debug builds), so a store build could not reach
  Supabase. Fixed; `aapt2 dump permissions` on the release APK shows it.
- **Offline cold start (issue #3).** The app now keeps the last list and the
  pending changes on the device per user and household. A start without
  network opens the list immediately; changes made offline survive app
  restarts and sync later. An expired token refreshed offline no longer
  signs the user out. Sign-out wipes the cache.
- **MCP duplicates.** MCP's `add_items` compared names without plural
  folding, so "Gurke" from Claude landed next to "2 Gurken" from Siri. It
  now uses `item_key` like `add_items`. A new e2e case fails on the old code.
- **Splitter gaps** from a 759-sentence adversarial pass: questions and modal
  verbs ("Kannst du Milch aufschreiben?"), "auf meine Einkaufsliste",
  "Bring Milch mit", sizes read as quantities, decimal commas, "2 Stk.",
  "1.000 g". All covered by table tests now.
- **Web sub-path links.** Sign-in redirects and invite links dropped a
  GitHub Pages sub-path; they now use `WEB_BASE_PATH`.
- **Joining another household by code crashed** (reported by job 05): the
  dialog disposed its text controller during its exit animation. The dialog
  now owns the controller; a widget test fails on the old code.
- **`scripts/lib.sh`** exports `MAILPIT_URL`, so e2e on any port block reads
  the right mailbox.

## How to verify

```bash
scripts/verify.sh --screenshots docs/screenshots/job-4
cd supabase/functions && deno test voice   # the sentence table
```

By hand against the local stack:

```bash
curl -s -X POST "$SUPABASE_URL/functions/v1/voice?format=text" \
  -H "Authorization: Bearer <fgp_ token from Menü, Zugänge>" \
  -H 'content-type: application/json' -d '{"text": "Milch, zwei Gurken und Klopapier"}'
```

## Test results (local `scripts/verify.sh`, 2026-10-23, rc 0)

| Suite | Result |
| --- | --- |
| gitleaks, full history and working tree | no leaks |
| pgTAP | 378/378 |
| `supabase db lint --fail-on warning` | no findings |
| Deno (`supabase/functions`) | 220 passed (voice: 181 splitter cases, 18 handler tests), plus 3 in a second suite |
| Flutter analyze | no issues |
| Flutter unit and widget tests | 156/156 (155 in the verify run, plus the join-dialog test added after it) |
| Playwright, whole suite | 45/45 |

The Playwright suite covers every scenario the spec's Verification section
names: two-browser live sync, autofocus, classifier learning (app, and via
Siri: add, move, delete, say again → learned category), store ordering and
item-to-store memory, the MCP OAuth flow (discovery, registration, consent
with PKCE, tools changing the list live) and the PAT test (create, use,
revoke → 401), and the Siri endpoint over HTTP with a PAT (add, revoke →
401, another household untouched, plural-aware duplicates shared with MCP).
New in this job: `voice.spec.ts` (7 tests) and `offline-start.spec.ts` (2).

Also proven on the box: `flutter build apk --release` (58.9 MB, label
"Einkauf", INTERNET and RECORD_AUDIO declared); `flutter build appbundle`
signed with a throwaway upload key from `/tmp` (cert shown by `keytool`,
then deleted); `bundle exec fastlane lanes`; actionlint on every workflow;
the Pages build served under `/family-groceries/` with deep links and a
magic link that keeps the sub-path.

Flakes seen only under heavy box load (load average above 100 while every
job's stack ran): Mailpit, provider sign-in and one edit test timed out;
each passed when rerun alone and in the final full run.

Screenshots: `docs/screenshots/job-4/` (`voice-*`, `offline-01-*`, plus the
whole suite's shots from the final run).

## Missing or blocked (needs Peter)

Everything below is implemented up to the step that needs an account, a
secret or a dashboard. `docs/NEEDS_PETER.md` has the exact steps.

1. **Deploy to the hosted project** (section 1): migrations and the edge
   functions (`health`, `mcp`, `voice`). The box has an access token but no
   database password, and a production deploy is Peter's call.
2. **Auth URLs** (section 2) and **web hosting** ("Job 4: web hosting"):
   enable Pages, run Web deploy, set Site URL and redirect URLs.
3. **Sign in with Google and Apple** (section 4, job 1b): provider
   credentials, then `app/config/auth.json`.
4. **MCP on the hosted project** (section 5, job 3): needs 1 and 2.
5. **Siri** ("Job 4: Siri"): after 1, create a token in the app and build
   the Shortcut from `docs/SIRI_SHORTCUT.md`.
6. **TestFlight and Play** ("Job 4: release"): App Store Connect app
   record, API key, match repo and deploy key, `fastlane ios certificates`
   once on a Mac; Play Console app, upload keystore, first AAB by hand,
   service account. Then run the Release workflow. iOS was not built here
   (Linux has no Xcode).

Not tested here, by necessity: real Siri dictation and the mic on a real
iPhone or Android phone (no device on the box; the mic flow is covered by
widget tests with a fake recognizer, the endpoint by HTTP tests).

## Whole project

| Job | What | Notes |
| --- | --- | --- |
| 1 | Foundation: tooling, CI, schema and RLS, auth, household, realtime list | `DONE_SUMMARY.md`, "Job 1" |
| 1b | Sign in with Google and Apple | [`01b.md`](01b.md) |
| 2 | Classifier with learning, categories, stores and store memory | [`02.md`](02.md) |
| 3 | MCP server, OAuth 2.1 consent, personal access tokens | [`03-mcp-oauth-tokens.md`](03-mcp-oauth-tokens.md) |
| 4 | Siri endpoint, in-app dictation, release, final pass | this file |

Open GitHub issues: none (issue #3 is closed by this PR).
