# Voice (Siri endpoint and in-app dictation)

A spoken sentence such as "Milch, zwei Gurken und Klopapier" becomes separate list items. Siri sends it through a Shortcut to the voice endpoint with a personal access token and speaks the German answer ("Hinzugefügt: Milch, 2 Gurken, Klopapier."). In the iOS and Android app, the microphone next to the add field listens in German on the device only, shows the words while the user speaks, and adds what the server's splitter makes of the sentence. Items already on the list are named, not doubled.

## Sub-features

- `voice-add` adds the items of a sentence and answers with JSON: `speech`, `items` (name, quantity, category, `alreadyOnList`) and `truncated`.
- `voice-siri-text` answers with the spoken sentence only (`?format=text`, `text/plain`), which the Shortcut reads aloud.
- `voice-duplicate` names items already on the list ("Schon auf der Liste: Milch.") and adds nothing for them.
- `voice-errors` answers every failure with a German sentence and a status: 401 bad or revoked token, 403 no household, 400 no text, 405 not POST, 413 too long, 422 nothing understood.
- `voice-truncate` takes at most 30 items and says so ("Mehr als dreißig auf einmal gehen nicht …").
- `voice-parse` splits without adding (`"mode": "parse"`, answer "Verstanden: …"), which the app's microphone uses.
- `voice-token` works with a personal access token from Menü → Zugänge, which Siri uses, and stops working once it is revoked.
- `voice-mic` is the microphone button (key `dictation-button`, tooltip "Diktieren", "Diktat beenden" while listening, hint "Ich höre zu …"). It shows on iOS and Android only.
- `voice-mic-offline-only` refuses to listen when the device can't recognize German offline and says why ("… fehlt hier die deutsche Offline-Spracherkennung …"). It never falls back to a server recognizer.

## How to get to it (user POV)

- Siri: "Hey Siri, Einkaufsliste", then the sentence. The Shortcut (docs/SIRI_SHORTCUT.md) POSTs `{"text": "<dictated text>"}` to `/functions/v1/voice?format=text` with `Authorization: Bearer fgp_…`.
- App: on the list screen, tap the microphone in the add field and speak. Tap it again to stop early.
- Any HTTP client: `POST <API URL>/functions/v1/voice` with a session JWT or a personal access token.

## Driving it with fg

Preconditions:

- Baseline from `features/README.md`; peter signed in on the list. One client is enough. Mark earlier test items bought, or start from `fg up --fresh`.

- **Add.** Run `fg fn call voice --body '{"text":"Milch, zwei Gurken und Klopapier"}'`. The result has status 200 and `speech` "Hinzugefügt: Milch, 2 Gurken, Klopapier.", with Gurken's quantity "2". `fg wait --text Klopapier` succeeds on peter's app within a second, without any tap.
- **Siri text and duplicate.** Run `fg fn call voice --path '?format=text' --body '{"text":"Milch und Brot"}'`. The content type is `text/plain; charset=utf-8` and the body is "Hinzugefügt: Brot. Schon auf der Liste: Milch.". `fg db query "select count(*) from items where name = 'Milch' and status = 'active'"` stays 1.
- **Parse only.** Run `fg fn call voice --body '{"text":"zwei Kilo Äpfel bitte","mode":"parse"}'`. The speech is "Verstanden: 2 kg Äpfel." and no Äpfel row exists.
- **Errors.** `fg fn call voice --as anon --path '?format=text' --body '{"text":"Milch"}'` gives 401 with the token sentence. `--body '{"text":"bitte danke"}'` gives 422 `nothing_understood`. `--body '{"text":""}'` gives 400 `no_text`. `fg fn call voice` without a body (GET) gives 405 `method`.
- **Truncate.** Send 31 comma-separated items with `"mode":"parse"`. The answer has 30 `items`, `truncated: true`, and the speech ends with "Mehr als dreißig auf einmal gehen nicht; sag den Rest bitte noch einmal."
- **Token.** Create a token named Siri as in `features/mcp-access.md` (Create a token), then run `fg fn call voice --bearer <fgp_…> --path '?format=text' --body '{"text":"Kaffee"}'`. It answers 200 "Hinzugefügt: Kaffee.". Revoke the token (Revoke a token). The same call now answers 401.
- **Microphone (android surface only).** Run `fg find --key dictation-button`, then `fg tap --key dictation-button`. If the device has offline German, `fg wait --text "Ich höre zu …"` succeeds. Otherwise `fg wait --contains "deutsche Offline-Spracherkennung"` succeeds and the button stays "Diktieren". `fg screenshot --native` shows the permission prompt on first use.
- **Proof.** `fg screenshot --name voice-<sub-feature>` after each app step, and the `fg fn call` JSON plus a `fg db query` of the rows for each endpoint step.

## Gotchas

- On the linux surface there is no microphone button (`fg find --key dictation-button` counts 0). That is intended: Linux has no on-device recognizer. Report `voice-mic` and `voice-mic-offline-only` as not drivable on linux, not as verified.
- On the shared build box the android surface is unavailable (KVM marker), so the microphone can only be proven on a real device. The widget and unit tests in `app/test/list/dictation_test.dart` and `device_dictation_test.dart` cover the wiring.
- The emulator's Google recognizer often has no offline German. The refusal message is then the expected result, not a failure.
- `fg fn call voice` writes items; use `--dry-run` to see the request without sending it.
- The created token appears in `fg wait --contains fgp_` output. Keep it out of committed logs and pass it with `--bearer`, never in a file.
- 403 needs a signed-in user without a household. The seeded users both have one; `supabase/functions/voice/handler_test.ts` covers the case.
