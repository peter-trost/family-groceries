# Releases

The Release workflow builds the app and uploads it to TestFlight (iOS) and to
the Play internal track (Android). It runs only when started by hand. The
one-time store setup is in [`NEEDS_PETER.md`](NEEDS_PETER.md#job-4-release).

## Run a release

1. Open the Actions tab, select **Release**, then select **Run workflow**.
2. Pick `platform`: `both`, `ios` or `android`.

The `secrets` job checks the secrets of each selected platform. A platform
with missing secrets is skipped with a notice that names them, and the run
stays green. Nothing is uploaded on a push or a pull request.

## Lanes

Run lanes from `app/` with `bundle exec fastlane <platform> <lane>`. The
Fastfile is `app/fastlane/Fastfile`.

| Lane | What it does |
| --- | --- |
| `ios certificates` | Creates or renews the App Store distribution certificate and provisioning profile in the match repo. Run it once, by hand, on a Mac. |
| `ios beta` | Installs the certificate and profile from match (read-only), switches the Runner target to manual signing, runs `flutter build ipa` and uploads the IPA to TestFlight. Does not wait for Apple's processing. |
| `android internal` | Runs `flutter build appbundle` and uploads the AAB to the Play `internal` track. Uploads no listing, changelog or images. |

`bundle exec fastlane lanes` lists the lanes; CI's `fastlane` job runs it to
check that the Gemfile.lock installs and the Fastfile parses.

## Secrets and variables

Add these to the `release` environment (Settings, Environments, `release`).
Values marked "variable" may also be secrets; the workflow reads either.

| Name | Kind | Used by | Value |
| --- | --- | --- | --- |
| `APPLE_TEAM_ID` | variable | iOS | The 10-character Apple Developer team ID. |
| `MATCH_GIT_URL` | variable | iOS | SSH URL of the private certificates repo. |
| `MATCH_DEPLOY_KEY` | secret | iOS | Private SSH key; its public half is a deploy key on the certificates repo. |
| `MATCH_PASSWORD` | secret | iOS | Passphrase that encrypts the certificates repo. |
| `APP_STORE_CONNECT_API_KEY_ID` | secret | iOS | Key ID of the App Store Connect API key. |
| `APP_STORE_CONNECT_ISSUER_ID` | secret | iOS | Issuer ID shown above the API keys list. |
| `APP_STORE_CONNECT_API_KEY_P8` | secret | iOS | Full text of the `AuthKey_<id>.p8` file. |
| `ANDROID_KEYSTORE_BASE64` | secret | Android | The upload keystore, base64-encoded. |
| `ANDROID_KEY_PROPERTIES` | secret | Android | The `key.properties` file (format below). |
| `PLAY_SERVICE_ACCOUNT_JSON` | secret | Android | JSON key of the Google Cloud service account that Play Console allows to release. |
| `PLAY_RELEASE_STATUS` | variable, optional | Android | `draft` while Play still treats the app as a draft; unset means `completed`. |

The build needs no Supabase defines: `app/lib/app/environment.dart` defaults
to the production URL and publishable key. Both lanes pass
`--dart-define-from-file=config/auth.json`, the public Google and Apple
sign-in client IDs (see `docs/AUTH.md`); an empty value hides that button.

## Build numbers and versions

The build number is `1000 + GITHUB_RUN_NUMBER` of the Release workflow, the
same scheme as emotely. Both stores need a number that only increases, and
the run number does that without a commit. The version name (`0.1.0`) comes
from `version` in `app/pubspec.yaml`; change it there for a new version.

## Android signing

`app/android/app/build.gradle.kts` signs release builds with the key named in
`app/android/key.properties`:

```properties
storeFile=../upload-keystore.jks
storePassword=<store password>
keyAlias=upload
keyPassword=<key password>
```

`storeFile` resolves from `app/android/app`, so `../upload-keystore.jks` is
`app/android/upload-keystore.jks`; that is where the workflow writes the
keystore. Without `key.properties`, release builds sign with the debug key, so
local `flutter build apk --release` works without secrets. `key.properties`
and keystores are in `.gitignore`.

Play App Signing holds the app signing key. The keystore here is the upload
key only; Google can reset a lost upload key.

## iOS signing

[match](https://docs.fastlane.tools/actions/match/) keeps the distribution
certificate and the App Store profile, encrypted with `MATCH_PASSWORD`, in a
private git repo. The workflow loads `MATCH_DEPLOY_KEY` into an SSH agent so
match can clone it. `app/fastlane/Matchfile` is read-only by default, so a CI
run never creates certificates. The Xcode project keeps automatic signing for
local development; `ios beta` switches to manual signing for the release
build only and writes the export options to `build/ios/ExportOptions.plist`.

`Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false`, so TestFlight
does not ask the export compliance question for each build.

## Build locally

Android, from `app/`:

```bash
flutter build apk --release --dart-define-from-file=config/auth.json        # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release --dart-define-from-file=config/auth.json  # build/app/outputs/bundle/release/app-release.aab
```

Add `--build-number=<n>` to match a store build. To check which key signed a
build, run `keytool -printcert -jarfile <aab>` or
`apksigner verify --print-certs <apk>`.

iOS builds need macOS and Xcode. On a Mac with the match secrets in the
environment, `BUILD_NUMBER=<n> bundle exec fastlane ios beta` builds and
uploads; `flutter build ipa` alone builds with automatic signing.

Ruby for the lanes: `app/.ruby-version` names the version CI uses. Run
`bundle install` in `app/` once.

## App icon

`scripts/icons.py` (Python 3 with Pillow) draws the icon and writes every
size: `app/assets/icon/icon.png` (1024 px source), the iOS `AppIcon` set, the
Android launcher and adaptive icon mipmaps, and the web icons and favicon.
Change the drawing there and rerun `python3 scripts/icons.py`.
