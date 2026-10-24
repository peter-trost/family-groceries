# Quick add

Opening the app puts the cursor in the add field with the list visible beneath it, so a user can type an item and press Enter without tapping anything. Focus stays in the field for the next item. Ticking an item removes it from the list with an undo snackbar. Ticked items move to "Zuletzt gekauft", where one tap puts them back. While typing, up to five chips under the field offer what the household bought or added before, with the quantity it last had. With the field empty, a "Brauchen wir wieder?" row offers what is due again. A chip tap adds the item and leaves the cursor in the field.

## Sub-features

- `qa-autofocus` puts the cursor in the add field ("Was fehlt?") when the app opens on the list screen.
- `qa-enter` adds the typed item on Enter and clears the field.
- `qa-keep-focus` keeps focus in the field, so the next item needs no tap.
- `qa-quantity` splits a leading number into the quantity ("2 Äpfel" shows "Äpfel" with "2").
- `qa-duplicate` refuses an item already on the list with "<name> steht schon auf der Liste".
- `qa-send-button` adds through the send icon ("Hinzufügen") instead of Enter.
- `qa-tick-undo` ticks an item off, shows "<name> abgehakt" with "Rückgängig", and undo restores it.
- `qa-delete` deletes an item with a left swipe ("<name> gelöscht", undo).
- `qa-readd` puts an item from "Zuletzt gekauft" back on the list ("<name> steht wieder auf der Liste").
- `qa-suggest` shows up to 5 chips (key `suggestion-<name>`, label "<quantity> <name>", semantics "Vorschlag: <quantity> <name>") for usuals whose name, or a word of it, starts with the typed text. Items already on the list are left out.
- `qa-suggest-tap` adds a chip's item with its last quantity, clears the field and keeps focus in it, so Enter adds the next item.
- `qa-due` shows "Brauchen wir wieder?" and chips for due items while the field is empty: at least 2 purchases on different days, and the usual gap since the last one has passed (up to 4 times the gap; DECISIONS 8.2).
- `qa-suggest-offline` keeps the suggestions in the list snapshot, so the chips work without a connection.

## How to get to it (user POV)

- Open the app while signed in to a household. The list screen is the home screen.
- Type in the field at the top and press Enter, or tap the send icon at the field's right end.
- Tick the checkbox in front of an item.
- Swipe an item to the left.
- Expand "Zuletzt gekauft" at the bottom of the list and tap an entry or its "+" button.
- Type the start of something bought before ("Mi") and tap a chip under the field.
- Open the app with the field empty and tap a chip in the "Brauchen wir wieder?" row.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md`; peter signed in (`fg doctor` shows `peter.marionette ... screen list`).
- None of the test items are active: `fg db query "update items set status = 'bought' where status = 'active' and name in ('Milch', 'Äpfel')" --write`.

- **Open the app.** Quit and reopen it. Run `fg restart`. On linux, if `fg find --key login-email` returns a match, run `fg login peter` (see Gotchas). Then run `fg wait --key add-item-field`. The list screen shows. Run `fg screenshot --name qa-autofocus-opened`: the field has a cursor and a highlighted border.
- **Type without tapping.** Type into whatever has focus and press Enter. Run `fg type --input Milch --submit` (no matcher means the focused field). `fg wait --text Milch` succeeds, and the field is empty again. If the field had no focus, `type` fails with `no_focus`. That failure means `qa-autofocus` is broken.
- **Add the next item.** Run `fg type --input "2 Äpfel" --submit`. `fg find --text Äpfel` returns one row, and `fg find --text 2` returns its quantity.
- **Duplicate.** Run `fg type --input milch --submit`. `fg wait --contains "steht schon auf der Liste"` matches, and `fg db query "select count(*) from items where status = 'active' and name ilike 'milch'"` returns 1.
- **Send icon.** Run `fg type --key add-item-field --input Brot`, then `fg tap --x 384 --y 88`. That is the send icon at the field's right end on the 412-wide window. The icon is not listed by `fg find`, so derive it from `fg find --key add-item-field` (right edge minus 24, vertical middle). `fg wait --text Brot` succeeds.
- **Tick and undo.** Run `fg tap --row Milch --type Checkbox`, then `fg wait --text Milch --gone`. The snackbar "Milch abgehakt" shows. Run `fg tap --text Rückgängig` and `fg wait --text Milch`.
- **Delete.** Run `fg swipe --row Brot --direction left`, then `fg wait --text Brot --gone`. Within a few seconds, `fg db query "select count(*) from items where name = 'Brot'"` returns 0.
- **Re-add from history.** Tick Milch again, then run `fg tap --text "Zuletzt gekauft"` and `fg tap --row Milch --type IconButton`. `fg wait --contains "steht wieder auf der Liste"` matches, and Milch is back in its category.
- **Suggestions while typing.** Buy something first: `fg type --key add-item-field --input "2 l Milch" --submit`, `fg tap --row Milch --type Checkbox`, `fg wait --text Milch --gone`. Then run `fg type --key add-item-field --input Mi`. `fg wait --key suggestion-Milch` succeeds within about 2 s (the usuals refresh 1.5 s after the list changes), and the chip reads "2 l Milch". Take `fg screenshot --name qa-suggest`.
- **Tap a chip.** Run `fg tap --key suggestion-Milch`, then `fg wait --text Milch`. The field is empty and still focused: `fg type --input Brot --submit` (no matcher, so it fails with `no_focus` if the chip took focus) succeeds and `fg wait --text Brot` matches. `fg db query "select name, quantity from items where status = 'active' and name = 'Milch'"` returns quantity `2 l`.
- **Due again.** Give an item two purchases a week apart: buy "4 Brötchen" as above, then `fg db query "update item_events set created_at = now() - interval '7 days' - case action when 'added' then interval '1 hour' else interval '0' end where item_name = 'Brötchen'" --write` and `fg db query "insert into item_events (household_id, item_id, action, item_name, created_at) select household_id, item_id, action, item_name, created_at - interval '7 days' from item_events where item_name = 'Brötchen'" --write`. Change the list once (tick any item) or `fg restart` so the usuals reload. With the field empty, `fg wait --text "Brauchen wir wieder?"` matches and `fg wait --key suggestion-Brötchen` succeeds. `fg tap --key suggestion-Brötchen` adds Brötchen with quantity `4`, and `fg type --input Butter --submit` still reaches the field.
- **Proof.** Record across the add: `fg record start --name qa-enter` before typing and `fg record stop` after the wait. Take `fg screenshot --name qa-after` and run a `fg db query` showing the rows and their status.

## Gotchas

- Autofocus happens on open only. After a dialog, the menu or a tick, nothing has focus, and `fg type` without a matcher fails with `no_focus`. Use `--key add-item-field` from then on, and use `fg restart` to prove autofocus again.
- On the linux surface a relaunched app comes back signed out (since 2026-10-23, job 4's device cache). supabase_flutter (`SharedPreferences`) and the app's offline cache (`SharedPreferencesAsync`) rewrite the same `shared_preferences.json` at sign-in, and the session is lost. Android and iOS keep the two in separate stores, so this is expected to be Linux-only (inferred, not tested). Reported on the jobs board. The list screen still opens fresh after `fg login`, which is what autofocus acts on.
- On Linux there is no soft keyboard. "Keyboard up on open" can only be proven on the android surface with `fg screenshot --native`.
- The UI is optimistic: an item vanishes before the server has it. Assert stored state with `fg db query`, and repeat the query if it lags for a second or two.
- `--row Milch` picks the first row showing exactly "Milch". With Milch both on the list and in "Zuletzt gekauft", it targets the list row.
- Button labels (Rückgängig, Speichern) do not show in `fg find`, but `fg tap --text` reaches them. Wait for snackbars with `--contains` on their message text.
- Items from earlier runs stay in "Zuletzt gekauft". `fg up --fresh` clears everything.
- Suggestions come from the history, so earlier runs' purchases show up as chips too. `fg up --fresh` clears the history with the items.
- A chip for an item already on the list never shows; tick it first. Names compare case-insensitively on the device, and by `item_name_key` on the server.
- `fg find` lists each chip's key (`suggestion-<name>`), not the row around them. Wait for the due row by its text "Brauchen wir wieder?".
- One purchase is never due, and neither are purchases on the same day: backdate the history as above instead of ticking twice.
