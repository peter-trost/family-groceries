# Done summary

- Job 1b, Sign in with Google and Apple: [docs/done/01b.md](docs/done/01b.md)
- Job 2, classifier and stores: [docs/done/02.md](docs/done/02.md)
- Job 3, MCP server, OAuth 2.1, personal access tokens: [docs/done/03-mcp-oauth-tokens.md](docs/done/03-mcp-oauth-tokens.md)
- Job 4, Siri endpoint, in-app dictation, release setup, final pass (whole-project overview and everything that needs Peter): [docs/done/04-voice-release.md](docs/done/04-voice-release.md)
- Job 5, verification skill and the fg CLI: [docs/done/05-verification-skill.md](docs/done/05-verification-skill.md)
- Job 3b, MCP follow-ups: [docs/done/03b.md](docs/done/03b.md)

## Job 1: foundation (2026-10-22)

PR: https://github.com/peter-trost/family-groceries/pull/1

### What was built

- **Toolchain.** `scripts/bootstrap.sh` installs Docker, the Supabase CLI
  2.121, Flutter 3.47.7 stable, Deno 2.9, gitleaks 8.30, Playwright with
  Chromium, and with `--android` the Android SDK. It also fixes this VM's
  stale `iptables-legacy` FORWARD DROP rule, which silently blocked traffic
  between Supabase containers. `scripts/dev.sh` starts the local stack and
  the web dev server; `scripts/verify.sh` runs every CI gate locally.
- **Schema and RLS** (`supabase/migrations/20261022150000_foundation.sql`).
  Tables: households, household_members (one household per user), invites
  (8-character codes, 14 days), profiles, categories (10 route categories
  plus the fallback "Sonstiges"), stores (dm, Lidl, Edeka) with
  store_category_order, items, item_events. Household creation seeds them.
  Every table is members-only. The RPCs are `create_household`,
  `create_invite`, `join_household` and `leave_current_household`. The
  classifier hook is `classify_item(household, name)`, a keyword stub that
  job 2 replaces. Realtime publishes items, categories, stores, store order
  and households.
- **App** (`app/`). Sign-in with email and password, or with a magic link.
  After sign-in the user creates a household or joins one with a code or a
  `/join/<code>` link. The list screen opens with the "Was fehlt?" field
  focused and the list beneath it. Enter adds an item and keeps focus.
  Items are grouped in route order. Ticking an item offers undo, and ticked
  items appear under "Zuletzt gekauft" for a one-tap re-add. Items can be
  edited (name, quantity, category) and deleted with undo. Duplicates are
  refused. Changes sync live through Realtime. Writes are optimistic,
  idempotent ops that are retried while offline, and the app resyncs on
  reconnect and on resume. All UI strings are German, in `app/l10n/app_de.arb`.
- **CI** (`.github/workflows/ci.yml`). The jobs are gitleaks (full history
  and working tree), Flutter (l10n check, format, analyze, test, web build),
  Deno (fmt, lint, test), pgTAP with `db lint`, and Playwright e2e on a
  local Supabase stack in CI. A `ci-ok` gate job sits on top.
  `supabase-deploy.yml` deploys from main and skips cleanly without secrets.
- **Docs.** `docs/SPEC.md`, `docs/DECISIONS.md` (22 decisions),
  `docs/NEEDS_PETER.md`, `docs/REUSED_FROM_EMOTELY.md`, `AGENTS.md` (with a
  `CLAUDE.md` symlink) and `README.md`.
- **pstack.** `/setup-pstack` was run non-interactively and wrote
  `~/.cursor/rules/pstack-models.mdc`; see DECISIONS #19.

### How to verify

```bash
scripts/bootstrap.sh
scripts/verify.sh --screenshots docs/screenshots/job-1
```

### Test results (local `scripts/verify.sh`, and CI on PR #1)

| Suite | Result |
| --- | --- |
| gitleaks: full history and working tree | no leaks |
| pgTAP (`supabase/tests`) | 44/44, including the cross-household denial suite |
| `supabase db lint --fail-on warning` | no findings |
| Deno (`supabase/functions`) | 2/2 |
| Flutter analyze (flutter_agent_lints, experimental) | no issues |
| Flutter unit and widget tests | 45/45 |
| Playwright e2e on the Flutter web build and the local stack | 11/11 |

The Playwright tests cover:

- autofocus on open, with the list visible beneath the field;
- add, tick, undo, re-add from history, and persistence across a reload;
- grouping in route order;
- duplicates;
- edit and delete with undo;
- two-browser live sync between two users who share a household through an
  invite code: an add, tick, edit and delete each show up in the other
  browser within 2 s;
- joining through an invite link;
- an offline tick and add that sync after reconnecting;
- RLS across households through the UI, the REST API, RPCs and Realtime;
- sign-in with a password, with a wrong password, and with a magic link
  read from Mailpit.

`flutter build apk --release` works on this box and produced a 56.5 MB APK
signed with the debug key.

Screenshots are in `docs/screenshots/job-1/`.

### Found and fixed along the way

- Flutter web, with semantics on, blurred the add field on Enter. After
  that the field was dead: a second Enter did nothing. Experiments with
  three variants showed the fix: handle a hardware Enter in
  `Focus.onKeyEvent`.
- After a tick, the first tap on the add field took no text. The cause was
  that the focused checkbox element was removed with its row. Fix:
  `ExcludeFocus` around the checkbox.
- Deleting a household cascaded into history writes that pointed at the
  deleted household. Fix: the history trigger skips cascaded deletes.

- The first CI run on `main` failed in e2e: `address already in use` on
  port 54324. Supabase's 543xx ports sit inside the runner's ephemeral port
  range. The follow-up PR narrows that range before the stack starts
  (`job/1-foundation-ci-ports`).
- PR #1 was squash-merged at 18:03 UTC by another process on the
  `petertrost-bot` account (commit author `bot@petertrost.com`), before this
  job's own merge call. The merged tree is the verified head `96c1dc1`.

### Missing or blocked

- **Remote deploy.** `~/groceries-ops/env` is empty, so there is no
  `SUPABASE_ACCESS_TOKEN`. Migrations are not on `jdwqrallbpdbshrdhenk` yet.
  The deploy workflow is ready; the exact steps are in
  `docs/NEEDS_PETER.md`, sections 1 and 2.
- **Hosted Auth URLs and web hosting.** These wait for a public web URL;
  see `docs/NEEDS_PETER.md`, section 3.
- **Offline cold start.** Launching the app offline shows a spinner until
  the network returns; there is no local copy of the list yet. This is a
  deliberate scope call (DECISIONS #11), tracked in issue #3.
- **Repository moved.** The repo now lives at
  `peter-trost/family-groceries`; the GitHub redirect showed this on the
  first push. `~/groceries-ops/COMMON.md` still names `petertrost-bot`.

### Review 0 fixes (branch `job/1-foundation-review-fixes`)

Must fix:

1. **`classify_item` leaked across households.** Fixed by migration
   `20261022190000_classify_item_members_only.sql`: a signed-in caller who
   is not a member of the household gets `not_a_member` (42501). Service
   role and the database itself still classify (MCP and Siri in jobs 3–4),
   and member inserts are unaffected. New pgTAP cases: denied for another
   household, allowed for the own household, denied for anon, allowed
   without a user. Proven to catch the bug: with the fix migration removed,
   test 16 fails; with it, all pass. The Playwright RLS test also calls the
   RPC as the outsider and expects `not_a_member` with no data.
2. **Merge author email.** `main`'s squash commits `26e9d06` and `13dfe23`
   have `bot@petertrost.com`, the account's default email. History is not
   rewritten. GitHub refuses the noreply address as a squash-merge
   `--author-email` (tried: "Invalid email address"), so the new
   `scripts/merge-pr.sh` squashes the PR locally into one commit authored
   `341616691+petertrost-bot@users.noreply.github.com` with the trailers,
   and rebase-merges it once `ci-ok` passes, which keeps the author.
   AGENTS.md and COMMON.md point at it. PR #4 is landed with it. Recorded in
   DECISIONS #24.
   Slip: a failed branch checkout left the shell on `main`, and commit
   `008e2b0` (only `scripts/merge-pr.sh`) was pushed to `main` directly,
   bypassing a PR. It was a fast-forward, not a force-push; it is left in
   place and noted in DECISIONS #24.

Nice to have, also done:

- The add field caps names at 120 characters and the edit sheet caps the
  quantity at 40, so a long paste is trimmed instead of rejected. Covered by
  a widget test.
- pgTAP now covers `join_household`'s destructive path: a sole member who
  joins elsewhere loses their old household and its list, and a household
  with other members survives.
- Offline cold start is ticketed as issue #3.
- COMMON.md has a note about the repo's new owner.
- DECISIONS #26 records that the repo carries no pstack config.
- DECISIONS #27 explains why Node 20 stays on the box.

Results after the fixes (local `scripts/verify.sh`): pgTAP 54/54, Flutter
46/46, Playwright 11/11, gitleaks clean, `db lint` clean.

## Job 3: MCP server, OAuth 2.1, personal access tokens

See [docs/done/03-mcp-oauth-tokens.md](docs/done/03-mcp-oauth-tokens.md).
