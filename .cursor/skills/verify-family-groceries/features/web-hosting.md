# Hosted web app

Anyone opens the production web app on Vercel and gets the sign-in page. Deep links such as `/oauth/consent` (MCP connections), `/join/CODE` (invites) and `/settings` boot the app on that route. "Mit Google anmelden" leads to Google's sign-in for the hosted Supabase project, and "Mit Apple anmelden" to Apple's for the Services ID `com.petertrost.familygroceries.web`. Each push to `main` deploys to production. Branches get preview URLs.

## Sub-features

- `web-spa-routes` serves `index.html` with `Cache-Control: no-cache` for every extensionless path, and answers 404 for a missing file such as `/does-not-exist.js`.
- `web-cache` makes `flutter_bootstrap.js`, `flutter_service_worker.js` and `version.json` `no-cache`, and other files `max-age=0, must-revalidate`.
- `web-google` takes the Google button to `accounts.google.com` with the web client ID from `app/config/auth.json`.
- `web-apple` takes the Apple button to `appleid.apple.com` with the Services ID.
- `web-build` runs `vercel.json`'s install and build commands in Amazon Linux 2023 from a fresh clone.

## How to get to it (user POV)

- Open the production URL (`docs/NEEDS_PETER.md`, section "Job 7: web hosting on Vercel") in a browser.
- Follow an MCP client's "connect" link, which lands on `<url>/oauth/consent?authorization_id=...`.
- Open an invite link `<url>/join/CODE`.

## Driving it with fg

Preconditions:

- No `fg` stack is needed: the checks run against the hosted project. Install the e2e dependencies once with `(cd e2e && npm ci)`.

- **Routes, headers and both providers.** Run `node e2e/web-smoke.mjs <production-url> <dir>`. Every line starts with `ok`, and the exit code is 0. `<dir>` then holds `1-sign-in.png` (Google and Apple buttons on `/oauth/consent`), `2-google-consent.png` (Google's "Anmeldung" page, "Weiter zu jdwqrallbpdbshrdhenk.supabase.co") and `3-apple-sign-in.png` (Apple's page naming "Einkauf Web").
- **The build Vercel runs.** Run `scripts/vercel-local.sh /tmp/fg-vercel-out`. It ends with `output: /tmp/fg-vercel-out`. To check the providers against that output, start `node e2e/serve.mjs /tmp/fg-vercel-out 55081`, then run `SMOKE_BROWSER_ONLY=1 node e2e/web-smoke.mjs http://127.0.0.1:55081 <dir>`. `e2e/serve.mjs` has no Vercel header rules, so the HTTP checks are skipped.

## Gotchas

- The smoke test stops at the providers' sign-in pages and never signs in. A full Google or Apple round trip needs a real account, so it is a manual step (`docs/NEEDS_PETER.md`, section 4, step 18).
- Previews are behind Vercel Authentication (302 to vercel.com). Pass a share link from the Vercel dashboard as the URL (`<preview>/?_vercel_share=...`); the smoke test reuses its cookie. Production is public.
- On a preview URL or on localhost, the provider round trip ends on the production Site URL unless that origin is in the hosted redirect list. Reaching the provider page does not depend on it.
- `scripts/vercel-local.sh` builds the committed `HEAD` and ignores uncommitted changes, like Vercel does.
