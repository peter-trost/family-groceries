# Needs Peter

Steps that cannot be done from the build box. Everything around them is
implemented.

## Status after job 7 (2026-10-23)

Done from the box (details in the sections below):

- Remote project `jdwqrallbpdbshrdhenk`: all migrations applied, edge
  functions `health`, `mcp` and `voice` deployed, Google and Apple sign-in
  enabled. The "Supabase deploy" workflow redeploys from every push to
  `main` over the Management API and fails red when a credential is
  missing (section 1).
- Web app on Vercel, built from every push (section "Job 7: web hosting on
  Vercel"). Site URL, redirect URLs and the OAuth consent path point at
  it (section 2).
- `app/config/auth.json` and `app/ios/Flutter/Auth.xcconfig` carry the real
  client IDs (section 4, step 15).

Still yours:

- Section 4, step 7: an Android OAuth client for the release keystore's
  SHA-1 (today only the build box's debug key has one, so Google sign-in
  works in debug APKs only).
- Section 4, step 13: renew the Apple client secret before it expires
  (set up on 2026-10-23 per the board, valid 180 days, so renew by
  2027-04-21 at the latest).
- Section 4, steps 16 and 18: the Xcode capability check and trying
  sign-in on your phones.
- Optional: delete the repo secret `SUPABASE_DB_PASSWORD`; nothing reads it
  any more.
- Job 4: release and Siri sections, job 5: Android verification run.

## 1. Remote Supabase deploy (job 1)

Done (job 7). The repo has the secret `SUPABASE_ACCESS_TOKEN` and the
variable `SUPABASE_PROJECT_REF`. The workflow applies migrations through
the Management API (`supabase/deploy/migrate.ts`), deploys the functions
with `supabase functions deploy --use-api` and smoke-tests them; it needs
no database password and no direct Postgres connection. From any machine:

```bash
set -a; source ~/groceries-ops/env; set +a
export SUPABASE_PROJECT_REF=jdwqrallbpdbshrdhenk
deno run --allow-read --allow-env --allow-net --config supabase/deploy/deno.json supabase/deploy/migrate.ts
supabase functions deploy --use-api --project-ref "$SUPABASE_PROJECT_REF"
```

The original steps below are kept for reference.

No `SUPABASE_ACCESS_TOKEN` was available, so migrations are not yet on
`jdwqrallbpdbshrdhenk`. Pick one:

**A. GitHub Actions (recommended).** In the repo settings, add:

- Secret `SUPABASE_ACCESS_TOKEN`: a personal access token from
  https://supabase.com/dashboard/account/tokens
- Secret `SUPABASE_DB_PASSWORD`: the project's database password
- Variable `SUPABASE_PROJECT_REF`: `jdwqrallbpdbshrdhenk`

Then run the "Supabase deploy" workflow (Actions tab, Run workflow). It links
the project, runs `supabase db push` and deploys the edge functions. Without
the secrets the workflow skips and stays green.

**B. From the box.** Put the two values in `~/groceries-ops/env`, then:

```bash
set -a; source ~/groceries-ops/env; set +a
supabase link --project-ref jdwqrallbpdbshrdhenk
supabase db push
supabase functions deploy
```

## 2. Auth URLs on the hosted project

Done (job 7, 2026-10-23, Management API via `supabase/deploy/auth_urls.ts`):

- Site URL: `https://family-groceries-pied.vercel.app`
- Redirect URLs: `https://family-groceries-pied.vercel.app/**`,
  `https://family-groceries-*-peter-trost.vercel.app/**` (Vercel previews
  of this team), `com.petertrost.familygroceries://login-callback`. No
  localhost entries on production (DECISIONS 7.9).
- OAuth server: enabled, authorization path `/oauth/consent`, so MCP
  clients land on `https://family-groceries-pied.vercel.app/oauth/consent`.

To change the URL later, rerun
`deno run --allow-env --allow-net supabase/deploy/auth_urls.ts <new-url> --preview <pattern>`
with `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` set, and update
`appUrl` in `app/lib/app/environment.dart`. The original steps:

Dashboard, Authentication, URL Configuration:

- Site URL: the public web app URL once it is hosted (for example
  `https://peter-trost.github.io/family-groceries`).
- Redirect URLs: that URL with `/**`, plus `http://127.0.0.1:3000/**` and
  `http://localhost:3000/**` for local web testing against the hosted project.

Magic links and sign-up confirmation mails redirect there. Email
confirmation is on by default for hosted projects: new users confirm their
address before the first sign-in, and the app tells them so.

## 3. Web hosting (optional, free)

Superseded (job 7): the web app is on Vercel; see "Job 7: web hosting on
Vercel".

The web app has no public URL yet. GitHub Pages on this public repo is free;
say the word and a later job adds the Pages workflow (needs the SPA
fallback: a copy of `index.html` as `404.html`).

Update (job 4): the Pages workflow exists; see "Job 4: web hosting" below.

## 4. Sign in with Google and Apple (job 1b)

The app, the Supabase config and a configuration script are ready. Both
providers stay hidden in the app and disabled on Supabase until these
steps give them credentials. Background: `docs/AUTH.md`.

Collect the values in `~/groceries-ops/env` (outside the repo) as you go.
The variable names are in `.env.example`.

### Google Cloud Console (https://console.cloud.google.com)

1. Create a project, or pick an existing one, for example "Family Groceries".
2. Go to **Google Auth Platform → Branding** (formerly "OAuth consent
   screen"). Enter the app name "Einkauf", your support email and the
   developer contact. Under **Authorized domains**, add `supabase.co`.
3. Under **Audience**, choose **External**. While the app is in "Testing",
   add your Google address and Lea's under **Test users**. Alternatively,
   press **Publish app**. Only the non-sensitive scopes `openid`, `email` and
   `profile` are used, so publishing needs no Google verification.
4. Under **Data Access**, add the scopes `openid`,
   `.../auth/userinfo.email` and `.../auth/userinfo.profile`.
5. Under **Clients → Create client → Web application**, name it
   "Einkauf Web (Supabase)". Add
   **Authorized redirect URI** `https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/callback`.
   Once the web app is hosted, also add its origin under **Authorized
   JavaScript origins**. Copy the **Client ID** (`GOOGLE_WEB_CLIENT_ID`) and
   the **Client secret** (`GOOGLE_WEB_CLIENT_SECRET`, a secret).
6. Under **Clients → Create client → iOS**, set the bundle ID to
   `com.petertrost.familygroceries`. Copy the **Client ID**
   (`GOOGLE_IOS_CLIENT_ID`).
7. Under **Clients → Create client → Android**, set the package name to
   `com.petertrost.familygroceries` and enter the SHA-1 fingerprint of a
   signing certificate. Create one Android client per certificate:
   - This build box's debug keystore (`~/.android/debug.keystore`):
     `4B:41:A1:23:70:B5:26:8F:01:53:98:97:C7:B5:28:79:FA:07:EB:F1`
   - Your Mac's debug keystore, if you build debug APKs there:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
   - The release keystore from job 4:
     `keytool -list -v -keystore <release.jks> -alias <alias>`
   - If the app ever ships through Google Play with Play App Signing, add
     the **App signing key certificate** SHA-1 from Play Console → Test and
     release → App integrity.

   Copy one Android client ID as `GOOGLE_ANDROID_CLIENT_ID`. The app never
   uses it; Google matches the app by package name and SHA-1.

### Apple Developer (https://developer.apple.com/account, team of peter@petertrost.com)

8. Go to **Certificates, Identifiers & Profiles → Identifiers → App IDs**,
   then to `com.petertrost.familygroceries`, or register that ID. Tick
   **Sign in with Apple** (as a primary App ID) and save. Note the **Team ID**
   (top right, `APPLE_TEAM_ID`).
9. Go to **Identifiers → + → Services IDs**. Use description "Einkauf Web"
   and identifier `com.petertrost.familygroceries.web` (`APPLE_SERVICES_ID`).
   Enable **Sign in with Apple → Configure**. Set the primary App ID to
   `com.petertrost.familygroceries`, the domain to
   `jdwqrallbpdbshrdhenk.supabase.co`, and the return URL to
   `https://jdwqrallbpdbshrdhenk.supabase.co/auth/v1/callback`.
10. Go to **Keys → +**. Name it "Einkauf Sign in with Apple", tick **Sign in
    with Apple**, configure it with the primary App ID, register it and
    download `AuthKey_<KEYID>.p8` **once**. Keep it outside the repo, for
    example `~/groceries-ops/AuthKey_<KEYID>.p8`. Note the **Key ID**
    (`APPLE_KEY_ID`) and set `APPLE_PRIVATE_KEY_FILE` to the file's path.
11. Optional: under **Services → Sign in with Apple for Email
    Communication**, register `jdwqrallbpdbshrdhenk.supabase.co`. Only needed
    if mails ever go to private relay addresses.

### Supabase (from this box or your Mac)

12. With the values in the environment, run:

    ```bash
    set -a; source ~/groceries-ops/env; set +a
    node scripts/configure-social-auth.mjs --dry-run   # shows what changes, secrets redacted
    node scripts/configure-social-auth.mjs
    ```

    The script enables Google once `GOOGLE_WEB_CLIENT_ID` and
    `GOOGLE_WEB_CLIENT_SECRET` are set. The client ID list is web first, then
    iOS and Android. It enables Apple once the Services ID, Team ID, Key ID
    and `.p8` file are set. The client ID list is the Services ID, then the
    bundle ID, and the client secret is generated from the `.p8`. To do the
    same by hand, use Dashboard → Authentication → Sign In / Providers →
    Google / Apple, with the same values in the same order. Leave "Skip
    nonce check" off.
13. **Every 5 months**, rerun step 12 for Apple: the Apple client secret
    expires after 6 months, and web and Android Apple sign-in stop working
    then. The script prints the expiry date. Native iOS sign-in keeps
    working without it.
14. When the web app has a public URL (section 3), add `<url>/**` to
    Authentication → URL Configuration → Redirect URLs. The app's deep link
    `com.petertrost.familygroceries://login-callback` was added there on
    2026-10-22.

### The app

15. Put the public values into `app/config/auth.json` and commit them
    (client IDs are public):

    ```json
    { "GOOGLE_WEB_CLIENT_ID": "<web client id>",
      "GOOGLE_IOS_CLIENT_ID": "<ios client id>",
      "SIGN_IN_WITH_APPLE": "true" }
    ```

    In `app/ios/Flutter/Auth.xcconfig`, set `GOOGLE_REVERSED_CLIENT_ID` to
    the iOS client ID with its dot-separated parts reversed. For
    `123-abc.apps.googleusercontent.com`, that is
    `com.googleusercontent.apps.123-abc`. `flutter test` fails if the two
    files disagree.
16. In Xcode, check that the Runner target shows the **Sign in with Apple**
    capability. It comes from `Runner/Runner.entitlements`. Automatic signing
    regenerates the provisioning profile with it.
17. GitHub: nothing is needed for sign-in. Client IDs live in
    `app/config/auth.json`; secrets live only in Supabase. Job 4's release
    workflow builds with `--dart-define-from-file=config/auth.json`.
18. Try it once: Google and Apple on the iPhone, Google and Apple on an
    Android phone, and both on the web app. Then sign in with the same email
    by password or magic link and check that you land in the same household.

## 5. MCP server on the hosted project (job 3)

Done from the box through the Management API on 2026-10-22: OAuth 2.1 server
enabled, dynamic client registration enabled, authorization path
`/oauth/consent`. JWT signing already used an ES256 key (`in_use`).

Still needed:

1. **Deploy the migrations and the `mcp` function** (section 1 above). The
   deploy workflow and `supabase functions deploy` include `mcp`. Check
   afterwards:
   `curl https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/mcp/.well-known/oauth-protected-resource`
   returns JSON with `"resource"`.
2. **Host the web app and set the Site URL** (sections 2 and 3). The OAuth
   server sends the browser to `<Site URL>/oauth/consent`; today that is
   `http://localhost:3000`, so OAuth connections from Claude or ChatGPT only
   work once the web app is public. Personal access tokens work without it.
   If the web app is served under a sub-path (GitHub Pages:
   `/family-groceries`), set the authorization path to
   `/family-groceries/oauth/consent` in Dashboard → Authentication → OAuth
   Server (or `oauth_server_authorization_path` via the API).
   After deploying (job 3b): connect a client, then disconnect it under
   Menü → Zugänge. Its next MCP call must get `401`. The function reads
   `auth.sessions` through `SUPABASE_DB_URL` for this; a `500` instead
   would mean the hosted database role lacks that read.
3. **Optional:** if a browser-based MCP client on another site should connect,
   set the edge function secret `MCP_ALLOWED_ORIGIN_HOSTS` to its hostname(s),
   comma-separated (`supabase secrets set MCP_ALLOWED_ORIGIN_HOSTS=…`).

## Job 4: web hosting

Superseded (job 7): GitHub Pages and `web-deploy.yml` were replaced by
Vercel and removed.

`.github/workflows/web-deploy.yml` builds the web app against the production
project and publishes it to GitHub Pages (free for public repos), at
`https://peter-trost.github.io/family-groceries/`. It runs only by hand and
skips with a notice until Pages is on. The build sets the base path, so
sign-in links, invite links and deep links (`/join/CODE`,
`/oauth/consent`) work under `/family-groceries`.

1. Repo Settings, Pages, Build and deployment, Source: **GitHub Actions**.
2. Actions tab, **Web deploy**, Run workflow. The run prints the URL.
3. Supabase Dashboard, Authentication, URL Configuration:
   - Site URL: `https://peter-trost.github.io/family-groceries`
   - Redirect URLs: add `https://peter-trost.github.io/family-groceries/**`
4. For MCP OAuth, keep the authorization path at `/oauth/consent`
   (Authentication, OAuth Server). Supabase appends it to the Site URL, and
   this Site URL already ends in `/family-groceries`, so the consent page is
   `https://peter-trost.github.io/family-groceries/oauth/consent`. Section 5,
   step 2's sub-path variant is for a Site URL without the path; use one or
   the other, not both.

Run the workflow again after each release you want on the web; it does not
deploy on every merge.

## Job 4: Siri

1. Deploy the edge functions (section 1). The `voice` function is part of
   `supabase functions deploy`; `supabase/config.toml` already sets
   `verify_jwt = false` for it, because Siri sends a personal access token,
   not a JWT. Check it with:

   ```bash
   curl -s -X POST 'https://jdwqrallbpdbshrdhenk.supabase.co/functions/v1/voice?format=text' \
     -H 'Authorization: Bearer nope' -d 'Milch'
   # -> Der Zugriffstoken fehlt oder ist ungültig. …
   ```

2. On your iPhone, follow `docs/SIRI_SHORTCUT.md` (German): create a token
   in the app under Menü, Zugänge, then build the three-action Shortcut
   "Einkaufsliste". Lea does the same on her phone with her own token.

The Shortcut itself needs no Apple account setting, but creating the token
needs a running app on the hosted project: the TestFlight or Play build
(job 4 release section below) or the web app once it is hosted (section 3).

## Job 4b: the microphone on a real phone

This box has no iOS device and no Android emulator (KVM is locked), so the
on-device check ran only in unit and widget tests and through the iOS and
Android compile jobs in CI. On the first build on your phone:

1. Tap the microphone next to "Was fehlt?", allow microphone and speech
   recognition, and say "Milch, zwei Gurken und Klopapier". Expect the
   words in the field, then "Hinzugefügt: Milch, 2 Gurken, Klopapier."
2. If instead you see "Diktieren geht nur offline … fehlt hier die deutsche
   Offline-Spracherkennung …", the phone has no offline German model.
   iPhone: Einstellungen › Allgemein › Tastatur › Diktieren on, with German
   among the keyboards (iOS downloads the model). Android: Einstellungen ›
   System › Sprachen › Spracheingabe (Google) › Offline-Spracherkennung ›
   Deutsch. Then try again.
3. Which phones can dictate: iPhones with iOS 13 or later and the German
   model; Android 12 (API 31) or later with Google's on-device recognizer.
   Android 11 and older always show the message above, because they have
   no on-device recognizer the app can require. On Android 12 the app can't
   ask for the language in advance, so a phone without offline German shows
   the message once you start speaking; please try that too if you have
   such a phone.

## Job 4: release

The Release workflow and the fastlane lanes are in place
([`RELEASE.md`](RELEASE.md)). Until the secrets below exist, the workflow
skips both platforms and stays green. All secrets and variables go into one
GitHub environment.

### Create the `release` environment

Repo Settings, Environments, New environment, name `release`. Optionally
limit deployment branches to `main`. The `gh` commands below write into it;
run them from a clone of the repo.

### iOS

1. **Register the bundle ID.** developer.apple.com, Certificates, Identifiers
   & Profiles, Identifiers, add an App ID: `com.petertrost.familygroceries`,
   description "Einkauf". No extra capabilities are needed.
2. **Create the app record.** App Store Connect, Apps, New App: platform iOS,
   name "Einkauf" (the name must be unique on the App Store; pick a variant
   such as "Einkauf Familie" if it is taken, the home-screen name stays
   "Einkauf"), primary language German, bundle ID
   `com.petertrost.familygroceries`, SKU `family-groceries`.
3. **Team ID.** developer.apple.com, Account, Membership details, Team ID:

   ```bash
   gh variable set APPLE_TEAM_ID --env release --body <TEAM_ID>
   ```

4. **App Store Connect API key.** App Store Connect, Users and Access,
   Integrations, App Store Connect API, Team Keys, generate a key with the
   Admin role (match needs it to create the certificate). Download
   `AuthKey_<KEY_ID>.p8`; Apple offers the download once.

   ```bash
   gh secret set APP_STORE_CONNECT_API_KEY_ID --env release --body <KEY_ID>
   gh secret set APP_STORE_CONNECT_ISSUER_ID --env release --body <ISSUER_ID>
   gh secret set APP_STORE_CONNECT_API_KEY_P8 --env release < AuthKey_<KEY_ID>.p8
   ```

5. **match repo and deploy key.** Create an empty private repo, for example
   `peter-trost/family-groceries-certificates`. Then:

   ```bash
   ssh-keygen -t ed25519 -N "" -C family-groceries-match -f match_deploy_key
   gh repo deploy-key add match_deploy_key.pub --allow-write \
     --repo peter-trost/family-groceries-certificates --title release-ci
   gh secret set MATCH_DEPLOY_KEY --env release < match_deploy_key
   gh variable set MATCH_GIT_URL --env release \
     --body git@github.com:peter-trost/family-groceries-certificates.git
   openssl rand -base64 32   # keep this in your password manager
   gh secret set MATCH_PASSWORD --env release --body '<that passphrase>'
   rm match_deploy_key match_deploy_key.pub
   ```

   Write access lets the next step push the certificates with the same key;
   CI only reads.
6. **Create the certificate and profile once**, on a Mac with Xcode and Ruby
   (the version in `app/.ruby-version`), with SSH access to the match repo:

   ```bash
   cd app
   bundle install
   export APPLE_TEAM_ID=<TEAM_ID> \
     MATCH_GIT_URL=git@github.com:peter-trost/family-groceries-certificates.git \
     MATCH_PASSWORD='<passphrase>' \
     APP_STORE_CONNECT_API_KEY_ID=<KEY_ID> \
     APP_STORE_CONNECT_ISSUER_ID=<ISSUER_ID> \
     APP_STORE_CONNECT_API_KEY_P8="$(cat AuthKey_<KEY_ID>.p8)"
   bundle exec fastlane ios certificates
   ```

   Apple allows only a few distribution certificates per team. If the lane
   reports the limit, revoke an unused one in the developer portal and rerun.
7. Run the Release workflow with `platform: ios`. The build shows up in
   TestFlight after Apple's processing (10 to 30 minutes). Add yourself and
   Lea as internal testers in App Store Connect, TestFlight.

### Android

1. **Create the app.** Play Console, Create app: name "Einkauf", default
   language German, app, free. Accept the declarations.
2. **Create the upload keystore** and keep it with its passwords in your
   password manager:

   ```bash
   keytool -genkeypair -v -keystore upload-keystore.jks -storetype PKCS12 \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

3. **Store it as secrets.** `key.properties` uses the passwords you chose:

   ```bash
   base64 -w0 upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64 --env release
   # macOS: base64 -i upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64 --env release
   printf 'storeFile=../upload-keystore.jks\nstorePassword=%s\nkeyAlias=upload\nkeyPassword=%s\n' \
     '<store password>' '<key password>' | gh secret set ANDROID_KEY_PROPERTIES --env release
   ```

4. **Upload the first AAB by hand.** The Play API cannot upload to an app
   that has no release yet. Build one signed with the upload key: copy
   `upload-keystore.jks` to `app/android/` and write the same `key.properties`
   to `app/android/key.properties` (both are git-ignored), then

   ```bash
   cd app && flutter build appbundle --release --build-number=1000
   ```

   In Play Console, Testing, Internal testing, create a release, accept Play
   App Signing, upload `build/app/outputs/bundle/release/app-release.aab`,
   add yourself and Lea as testers and roll it out. Delete the two files from
   `app/android/` afterwards.
5. **Service account.** In Google Cloud console, pick or create a project,
   enable the "Google Play Android Developer API", create a service account
   (no project roles needed) and add a JSON key. In Play Console, Users and
   permissions, invite the service account's email, give it access to the
   Einkauf app with "Release to testing tracks" (and "View app information"),
   and save.

   ```bash
   gh secret set PLAY_SERVICE_ACCOUNT_JSON --env release < service-account.json
   rm service-account.json
   ```

6. Run the Release workflow with `platform: android`. If Play rejects the
   upload with "Only releases with status draft may be created on draft
   app", set `gh variable set PLAY_RELEASE_STATUS --env release --body draft`
   and roll the draft out by hand in Play Console until the app leaves draft.

## Job 5: Android verification run

1. **Run the Android surface once on a machine where the emulator works**
   (your Mac, or a Linux host with working KVM). The build box cannot: a
   KVM guest there crashes the host kernel (see DECISIONS 5.1), so `fg`
   drives the Linux desktop build instead. On that machine:
   `scripts/fg setup --surface android`, then
   `FG_SURFACE=android scripts/fg up --clients peter,lea`, `scripts/fg doctor`
   and `.cursor/skills/verify-family-groceries/journeys/quick-add-live-sync.sh`.
   Those steps have never run end to end (SKILL.md, section "Android").
2. **Optional, for whoever runs the VM host:** nested KVM on this box oopses
   in `vmx_vcpu_create` (dmesg, 2026-10-23 05:53–06:03). Once the host is
   fixed, delete `~/.config/fg/kvm-broken` on the box to re-enable the
   emulator.

## Job 7: web hosting on Vercel

Done. The Vercel project `peter-trost/family-groceries` (created by
Engineering Lead on 2026-10-23) is linked to this repo and builds every
push from `vercel.json`:

- Production: `https://family-groceries-pied.vercel.app` (branch `main`).
  The plain `family-groceries.vercel.app` belongs to someone else.
- Previews: `https://family-groceries-git-<branch>-peter-trost.vercel.app`,
  behind Vercel Authentication (team default, unchanged).
- Project settings: root directory empty (repo root), framework "Other",
  no install, build or output overrides, Node 22.x. Environment variables
  for Production and Preview, both public values:
  `SUPABASE_URL=https://jdwqrallbpdbshrdhenk.supabase.co` and
  `SUPABASE_PUBLISHABLE_KEY=sb_publishable_YMFUFoZ-smly3zDIYTIFRw_vRt6UBk5`.
  The build fails if either is missing or the key is not a publishable key.
- Check a deployment with `node e2e/web-smoke.mjs <url> <screenshot-dir>`
  (after `cd e2e && npm ci`): SPA routes, cache headers, and the Google and
  Apple buttons reaching the providers' sign-in pages.

Nothing is needed from you here. Optional: a custom domain (Vercel,
Domains). If you add one, rerun `auth_urls.ts` with it and change `appUrl`.
