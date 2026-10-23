---
name: verify-family-groceries
description: "Drive the real Family Groceries Flutter app (debug build with the Marionette binding, as a headless Linux desktop app or on an Android emulator) against a local Supabase stack, and prove behavior with screenshots, screen recordings and database state. Use before claiming any app, sync, auth, household or classifier change works, to reproduce a bug, or to capture PR evidence. Covers Edge Functions (HTTP) and Postgres/RLS too."
---

# Verify Family Groceries

Prove behavior on the real app, not on a proxy. `fg` is this skill's CLI. It starts an isolated instance (Supabase stack, app clients, Marionette), drives the app like a user, and saves evidence. Every command prints one JSON object. A failure carries `error.code`, `error.message` and `error.hint`, and the hint names the command to run instead.

```bash
scripts/fg help              # all commands; scripts/fg is a symlink to .cursor/skills/verify-family-groceries/fg
scripts/fg help tap          # one command: flags and examples
```

## Surfaces

| Surface | What it is | Use for |
| --- | --- | --- |
| `linux` | The debug app (`app/test_driver/main_marionette.dart`) as a Linux desktop window on its own Xvfb display, 412×892 | Default on boxes where the emulator cannot run. Two clients (peter, lea) at once for live-sync proofs. |
| `android` | The same entrypoint as a debug APK on a headless emulator (AVD `fg-<prefix>`, 2 GB) | Mobile-only behavior: the soft keyboard, deep links, the magic-link return. One emulator per instance; lea then runs on linux. |
| backend | `fg db query`, `fg fn call`, `fg peer`, `fg mail` | Server state, RLS, Edge Functions, a UI-less second client, the local inbox. |
| web (fallback) | `e2e/` Playwright against the web build (`scripts/verify.sh`) | Headless CI checks only. Not a substitute for driving the app here. |

`FG_SURFACE` picks the surface. If unset, it is `android`, unless `~/.config/fg/kvm-broken` exists. On the shared build box that marker exists: starting a KVM guest there crashes the host kernel (`kernel BUG at arch/x86/kvm/x86.c:702`). Never delete the marker to "try again" on that box.

Marionette is debug and profile only. `marionette_flutter` is a dev dependency, and only `app/test_driver/main_marionette.dart` imports it. Release builds compile `lib/main.dart`. Code under `lib/` cannot import a dev dependency: the `depend_on_referenced_packages` lint fails `flutter analyze`, a required CI gate. The entrypoint also throws in release mode. A release build's `libapp.so` contains no Marionette code.

## Launch

```bash
export FG_PORT_PREFIX=548                   # your port block; 543 (the default) is job 1's
scripts/fg setup --dry-run && scripts/fg setup   # once per machine, and after a reboot (re-creates kvm group/permissions)
scripts/fg up --clients peter,lea           # stack + seed + build + both apps + Marionette; idempotent
scripts/fg login peter && scripts/fg login lea
```

`fg up` exits 0 only when the instance is usable: Supabase answers, the migrations are applied, `peter@fg.test` and `lea@fg.test` (password `test-password-123`) can sign in and share the household "Familie Test", and Marionette answers in every client. From an empty machine it runs `supabase start` from a generated workdir (`~/.cache/fg/<prefix>/stack`, ports `<prefix>xx`, project `family-groceries-<prefix>`). The tracked `supabase/config.toml` stays untouched. It seeds through the app's own RPCs and builds the debug app (about 30 s warm). Its JSON names the URLs, users, VM service URIs and the evidence directory. Reruns reuse what runs and is current. A changed `app/` rebuilds and relaunches. `--fresh` resets the database.

Clients start signed out (`fg up` clears their session storage). `fg restart` quits and reopens an app and keeps its stored data. Use it for launch behavior such as autofocus. On the linux surface the session does not survive the relaunch today (`features/auth.md`, Gotchas), so sign in again after it.

## Doctor

```bash
scripts/fg doctor
```

Read-only. Checks Docker, then auth, rest, realtime, functions and Mailpit. It checks that every function in the checkout is served, and that the stack was started with the current `config.toml` (a running stack does not reload either; `fg up` restarts it). It compares the migrations applied with the checkout and checks that both users sign in to one household. Per client it checks that the process is alive, that the build matches the checkout (`<client>.build`), and that Marionette is connected, and it reports which screen shows (`login`, `welcome`, `list`). Exit 1 lists each failed check with its fix. Run it first, and whenever a command fails unexpectedly.

## Drive

Every drive command takes `--client peter|lea` (default peter). Prefer stable handles in this order: ValueKey, label, tooltip, exact text, coordinates.

| Handle | Where |
| --- | --- |
| `--key login-email`, `--key login-password` | Login screen fields |
| `--text Anmelden` / `Registrieren` / `"Anmeldelink per E-Mail senden"` | Login buttons (the app bar also says "Anmelden"; `fg login` presses Enter instead) |
| `--key household-name`, `--key invite-code`, `--text "Haushalt anlegen"`, `--text Beitreten` | Welcome screen (signed in, no household) |
| `--key add-item-field` (label "Was fehlt?") | Add field on the list screen; autofocused on open |
| `--row <item> --type Checkbox` | Tick an item |
| `--text <item>` | Open an item's edit sheet (fields labelled `Name`, `Menge`; `--type "DropdownButton<String>"` for the category; `--text Speichern`) |
| `fg swipe --row <item> --direction left` | Delete an item (undo snackbar) |
| `--tooltip Menü`, then `--text "Mitglied einladen"` / `"Anderem Haushalt beitreten"` / `Abmelden` | List screen menu |

```bash
scripts/fg find --contains Milch            # what is on screen, as JSON (type, key, text, label, tooltip, bounds)
scripts/fg type --input "2 Äpfel" --submit  # into the focused field; umlauts are safe
scripts/fg tap --row Milch --type Checkbox --client lea
scripts/fg wait --text Milch --gone         # never sleep; wait polls (default 15 s) and reports elapsedMs
scripts/fg marionette -- scroll-to --text "Zuletzt gekauft"   # any other Marionette command
```

`find` and `wait` see what Marionette lists: fields, list texts, tooltips and keys. Text inside buttons is not listed, but `tap --text` still finds it. To wait for a dialog, wait for one of its fields or texts instead.

## Evidence

Evidence goes to `$FG_EVIDENCE_DIR/<run>/` (default `~/fg-evidence/<run>`; on the build box use `FG_EVIDENCE_DIR=~/groceries-ops/evidence`). That is outside the repo, and `fg down` never removes it. The run directory starts with `fg up` (or `--run NAME`). `fg env` prints it.

```bash
scripts/fg screenshot --name 02-lea-sees-milch --client lea    # PNG of the app frame
scripts/fg record start --name quick-add                       # WebM via Marionette's screencast
scripts/fg record stop                                         # finalizes; reports path and durationSec
scripts/fg screenshot --native                                 # OS capture (X display / adb screencap)
```

Flutter errors, including the cause behind a red error screen, go to the app log: `scripts/fg logs --client lea --grep EXCEPTION`. The CLI builds with `flutter.inspector.structuredErrors=false` so that they print.

Proof standards:

- Drive the user path (the field, the checkbox, the menu). Do not use RPCs or test hooks for the step under test. Use `db query --write` and `peer` only to set up preconditions.
- Capture the action and the resulting state. Take a screenshot before and after, and a recording across the action.
- Check side effects with a second, read-only view: `fg db query` for rows, the other client for sync, `fg mail` for mail.
- Name the entry point you proved. A skipped entry point is reported as skipped, not as verified through another path.
- A timing from `wait` is an upper bound: the CLI polls every 0.5 s, and each Marionette call takes about 0.2 s.

The reference proof is `journeys/quick-add-live-sync.sh`. It prints `PASS` with timings and the evidence path, or `FAIL: <step>`.

## Backend

```bash
scripts/fg db query "select name, status from items order by created_at desc limit 5"   # read-only rows
scripts/fg db query "select count(*) from items" --as lea          # as lea, through RLS
scripts/fg db query "update items set status = 'bought' where name = 'Milch'" --write --dry-run
scripts/fg fn call health --as anon                                 # Edge Functions over HTTP
scripts/fg peer lea add Butter                                      # REST client as lea
scripts/fg peer lea watch --until Butter --timeout 20               # realtime events as lea
scripts/fg mail --to lea                                            # Mailpit: subjects and auth links
scripts/fg login peter --api                                        # access token for curl
```

## Cleanup

```bash
scripts/fg down --dry-run && scripts/fg down     # recordings finalized, apps, Xvfb, emulator, this stack only
ls "$(scripts/fg env | jq -r .evidenceDir)"      # evidence survives
```

`fg down` stops only what this instance tracks: pids in `~/.cache/fg/<prefix>/state.json`, and the containers of its own project id. It never kills by process name. Run it after every failed attempt too. Use `--keep-stack` to leave Supabase up for the next `fg up`. On a shared box, stop the stack whenever you stop driving.

## Isolation

One instance per port block. `FG_PORT_PREFIX` sets the Supabase ports (`<prefix>21` API, `22` DB, `24` Mailpit), the project id, the state dir, the X displays (`:<prefix>1`, `:<prefix>2`) and the emulator port. `FG_PROJECT_ID`, `FG_AVD`, `FG_EMU_PORT`, `FG_STATE_DIR` and `FG_EVIDENCE_DIR` override single values. Two agents on different prefixes never touch each other's processes. `fg up` refuses a display another live Xvfb holds (`display_taken`). Never drive an instance you did not start.

## Android (not verified on the build box)

On a machine with a working emulator (KVM on Linux, or a Mac): run `fg setup --surface android`, which installs the emulator, the Android 35 Google APIs image for the host CPU (x86_64 or arm64-v8a) and the AVD. Then run `FG_SURFACE=android fg up --clients peter,lea`. The emulator reaches the stack at `10.0.2.2:<prefix>21`. Debug builds allow cleartext HTTP (`app/android/app/src/debug/AndroidManifest.xml`). `fg up` installs the APK, reads the VM service URI from logcat and forwards it with `adb forward`. The build box cannot run the emulator, so these steps have never run end to end. The first Android run must check them: boot, install, logcat URI and forward, Marionette over the forward, `record start` (Marionette falls back to adb reverse), `--native` capture, and opening a magic link with `adb shell am start -a android.intent.action.VIEW -d <link with 10.0.2.2>`.

## Helpers

- `fg` (and `scripts/fg`): the CLI. The source is in `cli/` (Deno). Tests: `cd cli && deno test -A`. CI runs them.
- `journeys/quick-add-live-sync.sh`: the reference end-to-end proof.
- `features/`: one recipe per user-facing feature. Read `features/README.md` first.

When you ship a feature, add or update its `features/<feature>.md` in the same PR, and give new widgets a ValueKey where text is not stable. `/maintain-verification-skill` keeps the map honest.
