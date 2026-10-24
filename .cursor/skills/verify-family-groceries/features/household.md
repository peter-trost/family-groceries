# Household

A list belongs to a household. A new user creates one on the welcome screen or joins one with an invite code. A member invites someone from the list menu ("Mitglied einladen"), which shows an 8-character code. A member can switch to another household with a code ("Anderem Haushalt beitreten").

## Sub-features

- `hh-create` creates a household from the welcome screen, with a name or the default "Unser Haushalt", and seeds its categories.
- `hh-invite` shows an invite code (8 characters from A–Z and 2–9, valid 14 days) with a copy button.
- `hh-join-welcome` joins a household with a code from the welcome screen.
- `hh-join-menu` switches a member to another household with a code from the list menu, after a warning.
- `hh-invalid-code` rejects a wrong code with "Dieser Code ist ungültig oder abgelaufen."
- `hh-isolation` keeps one household's items invisible to members of another.
- `hh-members` loads the members' display names with the list, so items show who added them; a new member's initial appears with their first item (recipe in `features/live-sync.md`, `sync-added-by`).

## How to get to it (user POV)

- Sign up or sign in as a user without a household. The "Willkommen" screen offers "Name des Haushalts" with "Haushalt anlegen", and "Einladungscode" with "Beitreten".
- On the list, open "Menü" (top right), then "Mitglied einladen" or "Anderem Haushalt beitreten".
- Open an invite link (`/join/<code>`). Only the web build has links. The phone apps use the code.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md`. Peter is signed in on the list.
- The lea client hosts a fresh user without a household: run `fg logout --client lea`, then `fg type --key login-email --input hh-$(date +%s)@fg.test --client lea`, `fg type --key login-password --input test-password-123 --client lea`, `fg tap --text Registrieren --client lea` and `fg wait --key household-name --client lea`.

- **Invite.** Run `fg tap --tooltip Menü`, `fg tap --text "Mitglied einladen"` and `fg wait --text Code`. Read the code with `fg find --type Text | jq -r '[.elements[].text | select(test("^[A-Z2-9]{8}$"))][0]'`. Close the dialog with `fg back`.
- **Join from welcome.** Run `fg type --key invite-code --input <code> --client lea` and `fg tap --text Beitreten --client lea`. `fg wait --key add-item-field --client lea` succeeds, and `fg find --text "Familie Test" --client lea` returns the app bar title. `fg db query "select u.email, m.role from household_members m join auth.users u on u.id = m.user_id join households h on h.id = m.household_id where h.name = 'Familie Test'"` lists the new user as `member`.
- **Invalid code.** On a welcome screen, run `fg type --key invite-code --input ZZZZZZZZ --client lea` and `fg tap --text Beitreten --client lea`. `fg wait --contains "ungültig oder abgelaufen" --client lea` succeeds.
- **Create.** On a welcome screen (another fresh user), run `fg type --key household-name --input "WG Test" --client lea` and `fg tap --text "Haushalt anlegen" --client lea`. `fg wait --text "WG Test" --client lea` succeeds, and `fg db query "select count(*) from categories c join households h on h.id = c.household_id where h.name = 'WG Test'"` returns 11.
- **Join from the menu.** As a member of another household, run `fg tap --tooltip Menü --client lea`, `fg wait --text "Anderem Haushalt beitreten" --client lea`, `fg tap --text "Anderem Haushalt beitreten" --client lea`, `fg wait --label Einladungscode --client lea`, `fg type --label Einladungscode --input <code> --client lea` and `fg tap --text Beitreten --client lea`. The confirm screen shows the code and "Du verlässt deinen aktuellen Haushalt …". Run `fg tap --text Beitreten --client lea` again, then `fg wait --text "Familie Test" --client lea`. The membership query above lists the user in Familie Test.
- **Isolation.** With the fresh user in its own household (after **Create**), add an item there: `fg type --key add-item-field --input Xylophon-WG --submit --client lea`. Then `fg db query "select name from items where name = 'Xylophon-WG'" --as peter` returns no rows, while the same query without `--as` returns one. The pgTAP suite (`supabase/tests/rls.test.sql`) covers writes.
- **Proof.** Screenshot the invite dialog, the welcome screen before joining and the list after joining. Add the `household_members` query output.

## Gotchas

- `hh-join-menu` crashed on main until job 04's fix (2026-10-23): a red error screen after "Beitreten". If it comes back, `fg logs --client lea --grep EXCEPTION` names the cause.
- `--as peter` and `--as lea` mean the seeded users, not whoever is signed in on the client of that name.
- Menus animate open. Tap an entry only after `fg wait --text <entry>`, or the tap can miss.
- Joining a household leaves the previous one. If the leaver was its last member, that household and its list are deleted. Never run the menu join with the seeded lea or peter unless the recipe restores them (`fg up --fresh`).
- The invite dialog lists the code as plain text next to the label "Code". Pick it by its pattern, not by position.
- Labels on buttons ("Beitreten", "Haushalt anlegen") are invisible to `fg find`, but `fg tap --text` reaches them.
- Fresh sign-up users accumulate across runs. Use a timestamp in the email to stay unique.
