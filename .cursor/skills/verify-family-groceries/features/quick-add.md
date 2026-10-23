# Quick add

Opening the app puts the cursor in the add field with the list visible beneath it, so a user can type an item and press Enter without tapping anything. Focus stays in the field for the next item. Ticking an item removes it from the list with an undo snackbar. Ticked items move to "Zuletzt gekauft", where one tap puts them back.

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

## How to get to it (user POV)

- Open the app while signed in to a household. The list screen is the home screen.
- Type in the field at the top and press Enter, or tap the send icon at the field's right end.
- Tick the checkbox in front of an item.
- Swipe an item to the left.
- Expand "Zuletzt gekauft" at the bottom of the list and tap an entry or its "+" button.

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
- **Proof.** Record across the add: `fg record start --name qa-enter` before typing and `fg record stop` after the wait. Take `fg screenshot --name qa-after` and run a `fg db query` showing the rows and their status.

## Gotchas

- Autofocus happens on open only. After a dialog, the menu or a tick, nothing has focus, and `fg type` without a matcher fails with `no_focus`. Use `--key add-item-field` from then on, and use `fg restart` to prove autofocus again.
- On Linux there is no soft keyboard. "Keyboard up on open" can only be proven on the android surface with `fg screenshot --native`.
- The UI is optimistic: an item vanishes before the server has it. Assert stored state with `fg db query`, and repeat the query if it lags for a second or two.
- `--row Milch` picks the first row showing exactly "Milch". With Milch both on the list and in "Zuletzt gekauft", it targets the list row.
- Button labels (Rückgängig, Speichern) do not show in `fg find`, but `fg tap --text` reaches them. Wait for snackbars with `--contains` on their message text.
- Items from earlier runs stay in "Zuletzt gekauft". `fg up --fresh` clears everything.
