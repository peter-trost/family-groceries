# Live sync

Two members of one household see each other's changes without reloading. An item added on one phone appears on the other, and an item ticked off on one disappears from the other immediately. Edits and moves sync the same way. Items the partner added carry the partner's initial, and the ones added since this device last looked are tinted, with "N neu von <name>" under the household name, until they have been on screen for 3 seconds.

## Sub-features

- `sync-add` shows an item added by one member on the other member's list.
- `sync-tick` removes an item from the other member's list when one member ticks it.
- `sync-edit` shows a renamed or recategorized item on the other list.
- `sync-delete` removes an item deleted by one member from the other list.
- `sync-reconnect` catches up after the app comes back (resync on resume or relaunch).
- `sync-added-by` shows a small initial (key `added-by-<item id>`, semantics "Von <name> hinzugefügt") on items another member added; none on your own. Two letters when two members share the first one.
- `sync-new` tints partner items added after this device last looked (row name ends in "Neu"), with the subtitle "N neu von <name>" ("N neu" for several partners). An item clears after 3 s at least half on screen while the app shows, and stays cleared after a relaunch. On a first start nothing old is new.

## How to get to it (user POV)

- Peter and Lea each open the app on their own phone, signed in to the same household.
- One of them adds, ticks, edits or deletes an item. The other only looks at the list.

## Driving it with fg

Preconditions:

- `fg up --clients peter,lea`, then `fg login peter` and `fg login lea`. `fg doctor` shows `screen list` for both.
- For `sync-new`, peter's app shows the list (the 3 s clock runs only while the item is on screen).
- Neither test item is active: `fg db query "update items set status = 'bought' where status = 'active' and name in ('Milch', 'Butter')" --write`.

- **One command.** Run `.cursor/skills/verify-family-groceries/journeys/quick-add-live-sync.sh`. It adds Milch on peter through the autofocused field, waits for it on lea, ticks it on lea, waits for it to leave peter, and checks the stored row (bought, by lea). It records both screens and prints `PASS` with both timings and the evidence directory.
- **Add on one, see on the other.** Run `fg type --key add-item-field --input Butter --submit --client lea`. Then run `fg wait --text Butter --client peter --timeout 5`, which succeeds with `elapsedMs`.
- **Tick on one, gone on the other.** Run `fg tap --row Butter --type Checkbox --client peter`. Then `fg wait --text Butter --gone --client lea --timeout 5` succeeds.
- **Edit on one.** On peter, run `fg tap --text Milch` (with Milch on the list), `fg type --label Name --input Hafermilch` and `fg tap --text Speichern`. `fg wait --text Hafermilch --client lea` succeeds.
- **Delete on one.** Run `fg swipe --row Butter --direction left --client lea` with Butter on the list. `fg wait --text Butter --gone --client peter --timeout 10` succeeds.
- **Partner initial and "neu".** With peter's list open, run `fg peer lea add Hafer`, then at once `fg wait --text Hafer` and `fg screenshot --name sync-new-live`: the row is tinted, shows "L", and the title reads "1 neu von Lea". `fg find` lists `added-by-<id>` for the row. Within 3 to 4 s, `fg find --contains neu` returns count 0 and the tint is gone; the "L" stays. Peter's own items have no `added-by-` key.
- **Stays seen.** Run `fg restart` (and `fg login peter` if the login screen shows). `fg wait --text Hafer` matches and `fg find --contains neu` returns count 0.
- **Independent observer.** In a second shell, run `fg peer lea watch --until Butter --timeout 20` before the add. It prints the realtime INSERT and UPDATE events that lea's session receives, with timestamps.
- **Reconnect.** fg cannot take one client offline yet, so `sync-reconnect` is not drivable here. Report it as skipped on this surface. The web e2e test "a tick made while offline syncs when the connection returns" (`e2e/tests/live-sync.spec.ts`) covers it in CI.
- **Proof.** Record both clients (`fg record start --name sync-peter --client peter` and `--name sync-lea --client lea`). Screenshot the observing client after each change, and show the stored row with `fg db query`.

## Gotchas

- Each debug app uses about 650 MB of RAM (JIT), so two need about 1.3 GB plus the stack. One app plus `fg peer` is the light variant, and the only one with the android surface (one emulator).
- `elapsedMs` from `fg wait` is an upper bound: polling every 0.5 s plus about 0.2 s per Marionette call.
- A delete hides the row on the acting client at once (optimistic). The server delete lands about 1 to 3 s later, and only then does the other client drop the row. Use `--timeout 10` for deletes.
- A precondition written with `fg db query --write` also syncs live, because it is a real update. Write preconditions before you start recording.
- Both apps must be signed in to the same household. A client left on another account from an earlier recipe shows a different list. Check the app bar title ("Familie Test").
- The "neu" tint lasts only 3 s on screen. Take its screenshot in the same command chain as the wait, and prove "cleared" with `fg find --contains neu` (count 0) rather than a sleep.
- "New since you looked" is per device: an item lea adds while peter's app is closed is new when it opens; the Playwright spec `e2e/tests/partner-news.spec.ts` drives that path with two browser contexts.
