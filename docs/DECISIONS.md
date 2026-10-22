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
