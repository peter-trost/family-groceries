# Reused from emotely

Source: `trost-systems/emotely`, cloned read-only to
`~/groceries-ops/ref/emotely`. Nothing was pushed to
emotely, and no emotely secrets, bundle ids, project refs or product content
were copied.

Reference commit: `119f780` (default branch head on 2026-10-22).

## Reused in job 1

| Piece | emotely path | Here | Changes |
| --- | --- | --- | --- |
| CI concurrency block | `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | Same expression. |
| `ci-ok` gate job | `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | Same shape; needs `gitleaks, app, functions, database, e2e`. |
| SHA-pinned actions | `.github/workflows/*.yml` | both workflows | Same SHAs for checkout v7, flutter-action v2, setup-cli v3.0.1, setup-node v7, upload-artifact v7.0.2. Added setup-deno v2.0.5 (pinned by SHA the same way). |
| Flutter install in CI | `ci.yml` (`subosito/flutter-action`, `channel: stable`, `cache: true`) | `ci.yml` | Version pinned via `env.FLUTTER_VERSION` instead of a `.fvmrc`. |
| pgTAP job | `ci.yml` `supabase` job | `ci.yml` `database` job | `supabase db start` instead of emotely's per-checkout `stack.sh`; same `supabase test db` and `db lint --fail-on warning`. Typed-schema regeneration dropped (no codegen here). |
| Deploy job | `ci.yml` `supabase-deploy` | `.github/workflows/supabase-deploy.yml` | Own workflow. Skips cleanly when `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` or `SUPABASE_PROJECT_REF` are missing (emotely's fails instead). No `config push` yet, because hosted Auth URLs wait for a web URL. |
| Lint rule set | `apps/mobile/packages/utility/analysis/lib/analysis_options.yaml` | `app/analysis_options.yaml` | Same `package:flutter_agent_lints/experimental.yaml` (Peter's package). emotely's own analyzer plugin is not used, so `flutter analyze --fatal-infos` is enough. |
| l10n setup | `apps/mobile/app/l10n.yaml` | `app/l10n.yaml` | German template (`app_de.arb`) instead of English; same output layout and `nullable-getter: false`. CI checks generated files match the ARB like emotely's `l10n:check`. |
| Supabase init | `apps/mobile/app/lib/main.dart`, `lib/app/environment.dart` | `app/lib/main.dart`, `app/lib/app/environment.dart` | Same rule: defines read only in `environment.dart`, defaulting to production values; names `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY`. PKCE (supabase_flutter default) instead of emotely's implicit flow, because magic links are links here, not typed OTP codes. |
| State and routing | `flutter_bloc`, `go_router`, pure `authRedirect()` in `router.dart` | `app/lib/app/router.dart`, cubits | Same libraries and the same single auth gate. No freezed, get_it or go_router_builder (small app, no codegen). |
| pgTAP test style | `supabase/tests/rls.test.sql` | `supabase/tests/*.test.sql` | Same `pg_temp.login()` / `anon()` helpers and direct `auth.users` inserts. |
| Local auth config | `supabase/config.toml` (`enable_confirmations = false` locally) | `supabase/config.toml` | Same; plus Studio, Storage and Analytics disabled for the shared box. |
| AGENTS.md conventions | `AGENTS.md`, `apps/mobile/AGENTS.md` | `AGENTS.md` (+ `CLAUDE.md` symlink) | Kept: CLAUDE.md symlinks to AGENTS.md, squash-merge with `ci-ok`, lints as errors, defines only in `environment.dart`, auth gate only in the router. |

## Not reused (and why)

- melos workspace, very_good test runner with a 100% coverage gate,
  cognitive-complexity and dedupe tools, ast-grep tripwires, cspell: sized for
  a multi-package monorepo; one app package does not need them yet.
- `stack.sh` per-checkout Supabase stacks: one checkout on this box; plain
  `supabase start` is enough. Worth adopting if several agents ever run
  stacks in parallel here.
- emotely has no gitleaks and no Playwright; both are new here.

## Candidates for job 4 (release)

- `.github/workflows/app-release.yml`: build number `1000 + run number`;
  iOS on `macos-26` with fastlane `match` (git storage, read-only, deploy key
  via `webfactory/ssh-agent`) and an App Store Connect API key; Android
  keystore written from a base64 secret plus `key.properties` from a secret;
  `release` environment.
- Secret names to mirror: `MATCH_DEPLOY_KEY`, `MATCH_PASSWORD`,
  `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
  `APP_STORE_CONNECT_API_KEY_P8`, `ANDROID_KEYSTORE_BASE64`,
  `ANDROID_KEY_PROPERTIES`, `PLAY_SERVICE_ACCOUNT_JSON`.
- `apps/mobile/app/fastlane/` (`Appfile`, `Fastfile`, `Matchfile`,
  `ExportOptions.plist`, `metadata/`), `apps/mobile/app/Gemfile` and the
  `fastlane` Ruby test job in `ci.yml`.

## Reused in job 4

| Piece | emotely path | Here | Changes |
| --- | --- | --- | --- |
| Release workflow | `.github/workflows/app-release.yml` | `.github/workflows/release.yml` | Manual only (`platform` input) instead of on every push; a `secrets` job skips a platform with a notice when its secrets are missing. Same SHA-pinned checkout, flutter-action, setup-ruby, ssh-agent and setup-java, same `release` environment, same `1000 + run number`. No beta promotion, listing, status-badge or Play lock jobs. |
| Secret names | `app-release.yml` | `release.yml` | Same names. Added `APPLE_TEAM_ID` and `MATCH_GIT_URL` (emotely hardcodes both) and the optional `PLAY_RELEASE_STATUS`. |
| Fastfile | `apps/mobile/app/fastlane/Fastfile` | `app/fastlane/Fastfile` | Kept `asc_api_key`, `certificates`, the match + `update_code_signing_settings` + `flutter build ipa` build, and the `flutter` helper with absolute paths. `ios internal` is `ios beta` here. Dropped beta promotion, metadata, data safety, survey signing, TestFlight test info and analytics defines. |
| Appfile, Matchfile | `apps/mobile/app/fastlane/{Appfile,Matchfile}` | `app/fastlane/{Appfile,Matchfile}` | Own bundle ID; team ID and repo URL from the environment. Same git storage, `appstore` type and read-only default. |
| ExportOptions.plist | `apps/mobile/app/fastlane/ExportOptions.plist` | written by `ios beta` to `app/build/ios/ExportOptions.plist` | Same keys; generated so the team ID comes from `APPLE_TEAM_ID` instead of a committed value. |
| Gemfile | `apps/mobile/app/Gemfile` | `app/Gemfile`, `app/Gemfile.lock`, `app/.ruby-version` | fastlane 2.241.1 (emotely 2.240.1), same CocoaPods 1.17.0. No minitest: no Ruby helpers to test. Ruby 3.3 (the version on the build box) instead of 3.4.4. |
| Android release signing | `apps/mobile/app/android/app/build.gradle.kts` | `app/android/app/build.gradle.kts` | Same `key.properties` lookup with debug fallback and the same keystore location in CI. |
| fastlane CI job | `ci.yml` `fastlane` (runs Fastfile helper tests) | `ci.yml` `fastlane` | Runs `bundle exec fastlane lanes` instead, on every PR (no path filter); in `ci-ok`'s needs. |
