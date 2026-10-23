# Job 5: verification skill and the fg CLI (2026-10-23)

Branch `job/5-verification-skill`. Skill: `.cursor/skills/verify-family-groceries/`
(also `.claude/skills/verify-family-groceries`). Decisions: `docs/DECISIONS.md`
5.1–5.10.

## What was built

- **The skill** (`SKILL.md`). It covers launch, doctor, drive, evidence,
  backend, cleanup and isolation for the real app. It is written for an
  agent that has never seen the repo, and `AGENTS.md` (= `CLAUDE.md`) points
  to it.
- **`fg`, one agent CLI** (`scripts/fg` → the skill's `fg`, Deno source in
  `cli/`). Commands: `setup`, `up`, `restart`, `down`, `doctor`, `env`,
  `seed`, `login`, `logout`, `find`, `tap`, `type`, `press`, `back`, `swipe`,
  `wait`, `marionette`, `screenshot`, `record start|stop`, `logs`,
  `db query`, `fn call`, `peer`, `mail`, plus placeholders `trace` and
  `memory` for the profiling job. Every command prints one JSON object.
  Errors carry a code and a hint that names the command to run instead.
  State-changing commands take `--dry-run`, and `fg help <command>` shows
  flags and examples. Help, flag checks and dry-run come from one command
  table, so a new command cannot skip them.
- **The real app as the surface.** The Flutter debug build with LeanCode's
  Marionette binding (`app/test_driver/main_marionette.dart`;
  `marionette_flutter` 0.7.0 as a dev dependency, so it never reaches a
  release build). On this box the app runs as a Linux desktop app on Xvfb,
  because the Android emulator crashes the host kernel here (below). Two app
  instances (peter, lea) are two real clients for live-sync proofs. The
  Android path (emulator, APK, logcat VM service URI, `adb forward`) is
  implemented, but has not been run.
- **From empty to usable in one command.** `fg up --clients peter,lea` runs
  Supabase from a generated workdir (port block `FG_PORT_PREFIX`, project
  `family-groceries-<prefix>`; the tracked `config.toml` stays untouched),
  then seeds `peter@fg.test` and `lea@fg.test` in "Familie Test" through
  the app's RPCs. It builds the debug app when the source changed, launches
  both clients and waits for Marionette. Measured from an empty state dir:
  59 s.
- **Doctor** (read-only). It checks Docker, then auth, rest, realtime,
  functions and Mailpit. It checks that every function in the checkout is
  served and that the stack runs the current `config.toml`. It compares the
  migrations applied with the checkout, and checks that both users sign in
  to one household. Per client
  it checks that the process is alive, that the build matches the checkout,
  and that Marionette is connected, and it reports the screen.
- **Evidence** goes to `$FG_EVIDENCE_DIR/<run>/`: PNG screenshots from
  Marionette and WebM recordings from Marionette's screencast, with
  `--native` for X11 or adb capture. `fg down` removes only what the
  instance started (tracked pids, its own project id) and keeps the
  evidence.
- **Feature map** (`features/`). It holds the index and five recipes for
  the features on main: quick add, live sync, sign-in, household,
  classifier. Every command in them was run against the app on this box.
- **Reference journey** `journeys/quick-add-live-sync.sh`.
- **Minimal product changes** (all for driving the app):
  - ValueKeys `login-email`, `login-password`, `household-name`,
    `invite-code` and `add-item-field`. These are the text fields Marionette
    cannot reach by text. Buttons are reached by their label.
  - `app/linux/`, the Linux desktop target with a phone-sized window.
  - Cleartext HTTP in the Android debug manifest only.
- **CI**: the CLI's 17 tests, fmt and lint run in the `functions` job and in
  `scripts/verify.sh`.

## How to verify

```bash
export FG_PORT_PREFIX=548                 # any free block; 543 is job 1's
scripts/fg setup --dry-run               # what this machine still needs
scripts/fg up --clients peter,lea && scripts/fg doctor
.cursor/skills/verify-family-groceries/journeys/quick-add-live-sync.sh
scripts/fg down && ls "$(scripts/fg env | jq -r .evidenceDir)"
cd .cursor/skills/verify-family-groceries/cli && deno test -A
```

## Results

- Proof run from empty (`~/groceries-ops/evidence/proof-20261023-0741/`,
  copied to `docs/screenshots/job-5/`):
  - `fg up` took 59 s, then `fg doctor` was healthy with all 16 checks.
  - Peter reopened the app and typed into the focused field without a tap:
    "Milch" was added. A second Enter added "2 Äpfel" (focus kept).
  - Lea's app showed Milch within 267 ms. Lea ticked it, and it left Peter's
    list within 296 ms. Both are upper bounds from 0.5 s polling.
  - The stored row is `bought`, by lea@fg.test.
  - Recordings: 5.6 s each. After `fg down`, no process or container of the
    instance was left, and the evidence was still there.
- `scripts/verify.sh` (ports 548xx, before the rebases) passed: gitleaks,
  pgTAP and db lint, 21 Deno function tests, 16 fg CLI tests, 100 Flutter tests, the web build
  and 31 Playwright tests.
- After rebasing onto jobs 2 and 4, a second local `verify.sh` failed 7
  voice tests with "Function not found". My stack had started before
  `voice` existed, and a running stack does not pick up new functions or
  config. `fg doctor` now probes every function and compares the stack's
  start signature, and `fg up` restarts a stale stack. A third run passed
  everything except 3 social sign-in tests, which failed because job 04's
  e2e run held the shared fake OIDC port 54399 at the same time. Rerun
  alone, all 8 social sign-in tests passed. Posted on the board.
- A release build (`flutter build linux --release`) contains no Marionette
  code: 0 matching strings in `libapp.so`, against 460 in the debug kernel.

## Found while building

- **The Android emulator cannot run on this box.** Creating a KVM vCPU hits
  `kernel BUG at arch/x86/kvm/x86.c:702` (`vmx_vcpu_create`). I stopped
  after three oopses, and `~/.config/fg/kvm-broken` now makes `fg` refuse
  the emulator here. Posted on the board.
- **App bug on main, now fixed by job 04.** List menu →
  "Anderem Haushalt beitreten" → code → "Beitreten" shows Flutter's red
  error screen, and the user stays in the old household.
  `showJoinCodeDialog` disposes its `TextEditingController` while the
  dialog's exit animation still builds the TextField. I reproduced it with
  `fg` and in a plain widget test. Screenshot:
  `docs/screenshots/job-5/bug-join-from-menu.png`. It is posted on the
  board. Job 04 fixed it in #5, and `fg` confirmed the fix after the
  rebase: the join now reaches the confirm screen and moves the user.

- **Linux surface: sessions do not survive a relaunch** since job 4's
  offline cache. supabase_flutter (`SharedPreferences`) and `DeviceCache`
  (`SharedPreferencesAsync`) rewrite the same `shared_preferences.json` on
  Linux at sign-in, and the session is lost. Android and iOS keep the two
  APIs in separate stores and web uses localStorage, so the shipped
  platforms should be unaffected (inferred, not tested). The journey signs
  in again after the relaunch; posted on the board with a suggested fix
  (give the cache its own file on Linux).

## Missing or blocked

- The Android surface has not been verified on a real emulator. That needs
  a machine with a working emulator: `docs/NEEDS_PETER.md` §6.
- The keyboard-up part of autofocus is Android or iOS only, and so is
  completing a magic link inside the app (the custom-scheme redirect). The
  Linux surface cannot show either. The recipes mark them, and the web e2e
  covers the magic link.
- `fg trace` and `fg memory` are placeholders for the profiling job.
- Not mapped: Google and Apple sign-in (01b) and MCP, consent and tokens
  (03) are on main but were outside this seed. Stores (02) and voice (04)
  are in flight. The board asks each owner to add its `features/*.md`.

## Review 0 fixes (2026-10-23)

- **Must fix:** `features/README.md` told agents to require `"healthy": true`
  from `fg doctor`. That field existed only on success, while every other
  command signals success with `"ok": true`. Doctor now uses only the common
  contract: `"ok": true` with exit 0, or `"ok": false` with `error.code`
  `unhealthy` and `error.checks` (each failed check has a `fix`). The
  README and SKILL.md say so, and a test pins the failure shape.
- `fg db query` without `--write` now rejects any statement that is not a
  query (`delete`, `update`, …) with code `read_only` and a hint to add
  `--write`, before reaching the database. Previously a `delete` came back
  as a syntax error. The read-only session still catches writes hidden in
  a `WITH`.
- `fg down` names `evidenceDir` only when that directory exists (`null`
  otherwise), so it no longer points at an old run.
- SKILL.md says where review evidence goes: `docs/screenshots/<job>/` in
  the PR, with the full run kept in `$FG_EVIDENCE_DIR`.
- Verified: 20 CLI tests (the new `read_only` test fails with the guard
  removed). Live on ports 548xx: `fg up` → `fg doctor` (`ok: true`, 18
  checks) → `fg db query "delete from items"` (`read_only`) →
  `journeys/quick-add-live-sync.sh` PASS (lea 259 ms, gone on peter
  1053 ms) → `fg down` (evidence kept in
  `~/groceries-ops/evidence/review0-1135/`).
