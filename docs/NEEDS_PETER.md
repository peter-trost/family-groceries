# Needs Peter

Steps that cannot be done from the build box. Everything around them is
implemented.

## 1. Remote Supabase deploy (job 1)

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

Dashboard, Authentication, URL Configuration:

- Site URL: the public web app URL once it is hosted (for example
  `https://peter-trost.github.io/family-groceries`).
- Redirect URLs: that URL with `/**`, plus `http://127.0.0.1:3000/**` and
  `http://localhost:3000/**` for local web testing against the hosted project.

Magic links and sign-up confirmation mails redirect there. Email
confirmation is on by default for hosted projects: new users confirm their
address before the first sign-in, and the app tells them so.

## 3. Web hosting (optional, free)

The web app has no public URL yet. GitHub Pages on this public repo is free;
say the word and a later job adds the Pages workflow (needs the SPA
fallback: a copy of `index.html` as `404.html`).

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
3. **Optional:** if a browser-based MCP client on another site should connect,
   set the edge function secret `MCP_ALLOWED_ORIGIN_HOSTS` to its hostname(s),
   comma-separated (`supabase secrets set MCP_ALLOWED_ORIGIN_HOSTS=…`).
