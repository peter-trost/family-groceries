# Job 8: who added it, new since you looked, usuals (2026-10-23/24)

PR: https://github.com/trost-systems/family-groceries/pull/17 (branch
`job/8-who-added-usuals`).

## What was built

- **Partner initial.** A partner's item shows their initial; your own
  items show none. Display names come from `household_members` and
  `profiles`, loaded with the catalog. An add by an unknown member reloads
  the catalog. Files: `app/lib/list/model.dart` (`Member`,
  `Catalog.initialOf`), `list_repository.dart` (`fetchCatalog`),
  `list_screen.dart` (`_ItemTile`).
- **"Neu seit du zuletzt geschaut hast".** Partner items added since this
  device last looked are tinted. The app bar says "N neu von Lea". An item
  clears after 3 s at least half on screen while the app shows, and stays
  cleared after a reload. The state is a `SeenMark` (a server-time watermark
  plus ids) stored in DeviceCache `seen.<user>.<household>`, outside the
  list snapshot. A first start highlights nothing that was already there.
- **Usuals and due items.** The new RPC `public.suggest_items`
  (migration `20261023194403_suggest_items.sql`) builds them from
  `item_events` grouped by `item_name_key`, with the last quantity from
  `items`. The app fetches up to 200 once per resync, and again 1.5 s after
  the active names change. It keeps them in the snapshot (offline) and
  matches typed text on the device. Up to 5 chips show while typing, and
  "Brauchen wir wieder?" shows with the field empty. A tap adds the item
  with its quantity and focus stays in the field.
- **Offline snapshot safety.** `ListSnapshot` is version 2 with a
  per-version migrator chain. A v1 snapshot loads with its pending ops, and
  `added_by` is read tolerantly.
- **Web focus fix** (DECISIONS 8.8). A tap on a chip or the send icon
  blurred the field's DOM input, and the engine's deferred `safeBlur` beat
  any refocus. The tap now refocuses after it. The send icon had this bug
  before this job.
- Decisions 8.1 to 8.8 are in `docs/DECISIONS.md`. The threshold for "due"
  is 2 purchases, from 1x to 4x the gap (8.2), and history covers one year
  (8.3).

## How to verify

- `supabase test db` on a reset stack. `suggest_items.test.sql` has 27
  cases with a fixed clock; `rls.test.sql` has the cross-household case.
- `cd app && flutter test` (188 tests).
- `cd e2e && npx playwright test --workers=1 tests/partner-news.spec.ts
  tests/suggestions.spec.ts tests/autofocus.spec.ts` after a web build.
- Real app: `.cursor/skills/verify-family-groceries/features/quick-add.md`
  (`qa-suggest`, `qa-suggest-tap`, `qa-due`, `qa-suggest-offline`) and
  `features/live-sync.md` (`sync-added-by`, `sync-new`).

## Results

- pgTAP 419/419 on a clean stack. On a stack with leftover data, only the
  pre-existing `households.test.sql` case 24 fails (not this job's file).
  The suggest tests now scope their lookups to their own household.
- Flutter: format, `analyze --fatal-infos` and 188 tests green.
- Playwright: autofocus, offline-start, partner-news and suggestions green
  locally (the reviewer reran 6/6). The due-row spec and the full suite run
  in CI on PR #17, and in `scripts/verify.sh` after the rebase onto 02b.
- Real app (Linux debug build under Xvfb, `scripts/fg`, Lea via
  `fg peer`). Screenshots are in `docs/screenshots/job-8/`; the full run is
  in `~/groceries-ops/evidence/job08-proof/`.
  - fg-01: a live partner add is tinted, with "L" and "1 neu von Lea".
  - fg-02: 3 s later it is plain and the "L" stays.
  - fg-03: still plain after a relaunch.
  - fg-04: typing "Br" offers "4 Brötchen" and "Brot".
  - fg-05: backdated history shows "Brauchen wir wieder?".
  - fg-06: the chip added Brötchen with quantity 4, and the next item was
    typed without a tap. In the DB, Brötchen has quantity `4` and Milch has
    `2 l`.
- Measured `suggest_items` cost: 0.34 s for 6000 events and 3000 rows,
  down from 26.6 s in the first version.

## Missing or blocked

- Nothing is blocked on Peter.
- The merge waits for 02b (#16), as the brief requires. Then: rebase,
  `scripts/verify.sh`, CI green, then merge under the merge lock.
