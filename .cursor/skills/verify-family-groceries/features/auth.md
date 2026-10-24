# Sign-in

A user signs in with email and password, creates an account with "Registrieren", or asks for a sign-in link by email ("Anmeldelink per E-Mail senden"). Signed-out users only ever see the login screen. Signing out from the menu returns to it.

## Sub-features

- `auth-password` signs in with email and password and lands on the list (or on the welcome screen without a household).
- `auth-wrong-password` keeps the user on the login screen with an error snackbar.
- `auth-signup` creates an account. Locally, email confirmation is off, so the user lands on the welcome screen.
- `auth-magic-send` sends a sign-in link and shows "Wir haben dir einen Anmeldelink geschickt. Öffne ihn auf diesem Gerät."
- `auth-magic-open` signs the user in when the link is opened on the device.
- `auth-signout` signs out from the list menu ("Menü", then "Abmelden") or from the welcome screen's "Abmelden" button.
- `auth-session` keeps the user signed in across an app restart.

## How to get to it (user POV)

- Open the app signed out. The login screen ("Anmelden") shows email and password fields and three buttons.
- Signed in: open the menu at the top right of the list and choose "Abmelden".
- Open the sign-in email on the phone and tap its link.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md`. The lea client is signed out: `fg logout --client lea`.

- **Password sign-in.** Run `fg login lea`. It types into `login-email` and `login-password` and presses Enter. The result is `"screen": "list"`, and `fg find --text "Familie Test" --client lea` returns one element.
- **Wrong password.** Sign out, then run `fg type --key login-email --input lea@fg.test --client lea`, `fg type --key login-password --input falsch123 --submit --client lea` and `fg wait --contains "Anmeldung fehlgeschlagen" --client lea`. `fg find --key login-email --client lea` still returns one element.
- **Sign-up.** Run `fg type --key login-email --input neu-$(date +%s)@fg.test --client lea`, `fg type --key login-password --input test-password-123 --client lea` and `fg tap --text Registrieren --client lea`. Then `fg wait --key household-name --client lea` succeeds: the welcome screen of a user without a household.
- **Magic link, send.** Sign out, then run `fg type --key login-email --input lea@fg.test --client lea` and `fg tap --text "Anmeldelink per E-Mail senden" --client lea`. `fg wait --contains "Anmeldelink geschickt" --client lea` succeeds. `fg mail --to lea --limit 1` shows the subject "Your sign-in link" and one `/auth/v1/verify?...type=magiclink&redirect_to=com.petertrost.familygroceries://login-callback` link.
- **Magic link, open.** Android only: run `adb -s <serial from fg env> shell am start -a android.intent.action.VIEW -d "<link with 127.0.0.1 replaced by 10.0.2.2>"`, then `fg wait --key add-item-field`. On linux, report `auth-magic-open` as not drivable (see Gotchas).
- **Sign-out.** Run `fg logout --client lea`. The result is `"screen": "login"`.
- **Session survives restart.** Signed in, run `fg restart --client lea`, then `fg wait --key add-item-field --client lea`.
- **Proof.** Take `fg screenshot --name auth-<sub-feature>` after each step, and record the mail with `fg mail --to lea > $(fg env | jq -r .evidenceDir)/auth-magic-mail.json`.

## Gotchas

- The app bar title is also "Anmelden", so `fg tap --text Anmelden` is ambiguous. Press Enter in the password field (`--submit`) or use `fg login`.
- `fg login` fails with `not_on_login` when the app is already signed in. Sign out first.
- The magic link redirects to `com.petertrost.familygroceries://login-callback`. The Linux desktop build registers no handler for that scheme, so opening the link cannot sign it in. Android handles the scheme (intent filter). The web build uses an http redirect instead: `e2e/tests/auth.spec.ts` "magic link signs in on this device" covers it in CI.
- The local stack's links point at `127.0.0.1:<prefix>21`. The emulator reaches that as `10.0.2.2:<prefix>21`.
- Sign-up users from these recipes stay in the database until `fg up --fresh`. They do not affect peter or lea.
- After `fg seed`, a running app keeps a session for a deleted user. The next `fg up` relaunches every app started before the seed, signed out; then `fg login` again.
