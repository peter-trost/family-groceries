# Job 4b: voice follow-ups (2026-10-23)

Branch `job/4b-voice-followups`, PR https://github.com/trost-systems/family-groceries/pull/13.
It closes the open edges left after job 4 (PRs #5 and #10): review 1
(`jobs/04-voice-release/review.1.md`) and 05's board note from 09:08.
Decisions are in `docs/DECISIONS.md` under "Job 4b".

## What changed

1. **The Linux app stays signed in after a relaunch.**
   - Cause, confirmed in the plugin source and reproduced: supabase_flutter
     keeps the session through the legacy `SharedPreferences` and the
     offline cache uses `SharedPreferencesAsync`. On Linux both hold their
     own copy of `shared_preferences.json` and rewrite the whole file on
     each write, so a cache write dropped the session.
   - Fix: `DeviceCache.onDevice()` (`app/lib/app/device_cache.dart`) stores
     the cache in `device_cache.json` on Linux. Android, iOS and web ignore
     Linux options (checked in each plugin's source), so their stores and
     keys stay where they were.
   - Test: `app/test/app/device_cache_linux_test.dart` drives the real Linux
     plugins on an in-memory file system and relaunches. It fails on the
     old code (session `null`).
   - Real app: before the fix, `fg restart` came back on the login screen.
     After it, three relaunches in a row stayed on the list, and the files
     hold `flutter.sb-127-auth-token` and `household.`/`list.` keys
     separately.
   - The verify skill no longer signs in again after `fg restart`
     (`journeys/quick-add-live-sync.sh`, SKILL.md, features `auth.md` and
     `quick-add.md`). The journey passed without it.
2. **Dictation stays on the device.**
   - `speech_to_text` listens with `onDevice: true` in de-DE.
   - Before listening, the app asks its own native check
     (`familygroceries/speech`), because the plugin alone falls back to the
     network recognizer on Android:
     - iOS (`AppDelegate.swift`): `SFSpeechRecognizer(de_DE).supportsOnDeviceRecognition`.
     - Android (`MainActivity.kt`): API 31+, `isOnDeviceRecognitionAvailable`,
       and on API 33+ German among the installed on-device languages.
   - Without offline German the mic says so in German and listens to
     nothing: "Diktieren geht nur offline, damit deine Stimme auf dem Gerät
     bleibt. Dafür fehlt hier die deutsche Offline-Spracherkennung. Lade sie
     in den Systemeinstellungen herunter oder tippe den Eintrag ein." The
     same message appears when an Android 12 recognizer reports a missing
     language while listening, or when the check doesn't answer in 5 s.
   - The mic shows on iOS and Android only (it was also on the Linux build,
     where it could only fail).
   - Tests: `app/test/list/device_dictation_test.dart` (the options reach
     the platform as `onDevice: true`, `de_DE`; no listening without
     offline German, without the native check, or when the check hangs;
     `error_language_*` maps to the message) and two new widget tests in
     `dictation_test.dart`. Mutations (`onDevice: false`, skipping the
     check, dropping the timeout) each fail them.
   - CI now compiles the Kotlin and Swift: new `android-build` and
     `ios-build` jobs, both in `ci-ok`. `ios-build` passed on the first
     commit with the Swift.
3. **The offline-start and social-sign-in flakes.**
   - Review 1's three failures had one trigger. mem-guard froze that run
     from 09:30:38 to 09:35:04, and with 3 workers exactly three tests were
     in flight. Each failed after 4.6 to 4.8 minutes on wall-clock timeouts.
   - What made offline-start fragile was a real app delay. postgrest-dart
     2.9 retries every GET three times on network errors (1, 2 and 4 s),
     and `SupabaseClient.from()` ignores `postgrestOptions.retryEnabled`.
     Offline, the session's household lookup and the list fetches each took
     about 7 s to fail: the cached list appeared 7.6 s after an offline
     reload and "Offline:" 7.3 s later, against 10 s expect windows.
   - Fix: SessionCubit opens the device's household before it asks the
     server. 02b found the same retry cause and turned the retries off
     (reads through `client.rest`, #16); this branch is rebased on that and
     dropped its own per-read `.retry(enabled: false)`. Both cubits retry
     on their own every 3 s.
     After: list 0.5 s, banner 0.6 s after an offline reload; the test went
     from 28 s to 9 s. Unit test: "a cached household opens before the
     server is asked" fails on the old code.
   - social-sign-in shared the fake OIDC on 54399 with other jobs; 03b's
     #11 moved it to each checkout's own port. 5 of 5 runs passed here on
     54799.
   - A full run also exposed a lost live update (`voice.spec.ts:152`): the
     catalog reload wrote back the list state from before its fetch. That
     is 02b's fix (`list_cubit.dart`), coordinated on the board.
4. **DONE summary mirror and the trailer.** `docs/done/04-voice-release.md`
   now matches the ops copy byte for byte (it lacked the "Merged as PR
   #10" line). `scripts/merge-pr.sh` ends every squashed message with
   `Co-authored-by: Peter Trost` (COMMON.md) and re-squashes a head that
   doesn't.
5. **Verification map for voice**:
   `.cursor/skills/verify-family-groceries/features/voice.md`. Every recipe
   was run against the local stack with `fg`: add (live on the app in
   293 ms), the Siri text format with a duplicate, parse mode, 401, 400,
   405, 422, the 30-item limit, and a personal access token that answers
   200 and then 401 once revoked.

6. **Review 0 fixes.**
   - The Linux screenshots were retaken from the final code (no mic on
     Linux): `fg up --fresh`, sign in, add Hafermilch, three `fg restart`s,
     each back on the list; `device_cache.json` holds `household.`/`list.`,
     `shared_preferences.json` holds `flutter.sb-127-auth-token`.
   - `fg setup` works on a fresh box: it no longer runs `pkg-config` before
     installing it, and it installs a JDK for the linux surface too
     (`shared_preferences_android`'s `jni` plugin links `libjvm.so` into the
     Linux build). Found when the 21:20 restart wiped both. New CLI test.
   - The mic gate has a test (`ListScreen.dictationFor`: iOS and Android
     apps only, never web).
   - NEEDS_PETER names the phones that can dictate (Android 12+, iPhone with
     the German model) and the Android 12 case to try.

## How to verify

```bash
scripts/verify.sh                                  # every CI gate, e2e included
cd app && flutter test test/app/device_cache_linux_test.dart test/list/device_dictation_test.dart test/list/dictation_test.dart test/session/session_cubit_test.dart
export FG_PORT_PREFIX=<block>; scripts/fg up --clients peter; scripts/fg login peter
scripts/fg restart --client peter && scripts/fg wait --key add-item-field   # still signed in
```

The voice recipes are in `features/voice.md`.

## Results

E2E_STREAK

## Screenshots

- `docs/screenshots/job-4b/linux-relaunch-before-fix.png`: the Linux app
  after `fg restart` on the old code, signed out.
- `docs/screenshots/job-4b/linux-relaunch-after-fix.png`: the same after
  three relaunches with the fix, on the list.
- `docs/screenshots/job-4b/voice-siri-endpoint-adds-live.png`: peter's app
  right after a voice request added "Milch, 2 Gurken, Klopapier".

## Not verified on this box

- The microphone on a real phone: no iOS device, and no Android emulator
  (KVM is locked). The wiring is unit- and widget-tested and both native
  builds compile in CI. `docs/NEEDS_PETER.md` ("Job 4b: the microphone on a
  real phone") lists the two-minute check, and how to install offline
  German if the phone lacks it.
