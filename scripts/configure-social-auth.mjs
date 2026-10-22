#!/usr/bin/env node
// Configures Sign in with Google and Apple on the hosted Supabase project via
// the Management API. A provider is enabled only when all of its credentials
// are in the environment; nothing is ever invented. Rerun it any time: it
// converges to the same config. See docs/NEEDS_PETER.md, section 4.
//
// Usage: node scripts/configure-social-auth.mjs [--dry-run]
//
// Environment (keep values outside the repo, e.g. in ~/groceries-ops/env):
//   SUPABASE_ACCESS_TOKEN, SUPABASE_PROJECT_REF (default jdwqrallbpdbshrdhenk)
//   Google: GOOGLE_WEB_CLIENT_ID, GOOGLE_WEB_CLIENT_SECRET,
//           GOOGLE_IOS_CLIENT_ID, GOOGLE_ANDROID_CLIENT_ID (optional)
//   Apple:  APPLE_SERVICES_ID, APPLE_TEAM_ID, APPLE_KEY_ID,
//           APPLE_PRIVATE_KEY_FILE (path to the AuthKey_XXXX.p8)
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';

const env = process.env;
const dryRun = process.argv.includes('--dry-run');
const ref = env.SUPABASE_PROJECT_REF || 'jdwqrallbpdbshrdhenk';
const bundleId = 'com.petertrost.familygroceries';
const mobileCallback = `${bundleId}://login-callback`;
const api = `https://api.supabase.com/v1/projects/${ref}/config/auth`;

if (!env.SUPABASE_ACCESS_TOKEN) {
  console.error('SUPABASE_ACCESS_TOKEN is not set.');
  process.exit(1);
}
const headers = { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' };

const b64url = (data) => Buffer.from(data).toString('base64url');

/** Apple's OAuth client secret: an ES256 JWT, valid for at most 6 months. */
function appleClientSecret() {
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: 'ES256', kid: env.APPLE_KEY_ID }));
  const body = b64url(JSON.stringify({
    iss: env.APPLE_TEAM_ID, iat: now, exp: now + 180 * 24 * 3600,
    aud: 'https://appleid.apple.com', sub: env.APPLE_SERVICES_ID,
  }));
  const key = createPrivateKey(readFileSync(env.APPLE_PRIVATE_KEY_FILE));
  const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key, dsaEncoding: 'ieee-p1363' });
  return { secret: `${head}.${body}.${b64url(sig)}`, expires: new Date((now + 180 * 24 * 3600) * 1000) };
}

const current = await (await fetch(api, { headers })).json();
if (current.message) {
  console.error(`Management API: ${current.message}`);
  process.exit(1);
}

const allowList = new Set((current.uri_allow_list || '').split(',').map((s) => s.trim()).filter(Boolean));
allowList.add(mobileCallback);
const patch = { uri_allow_list: [...allowList].join(',') };
const notes = [];

if (env.GOOGLE_WEB_CLIENT_ID && env.GOOGLE_WEB_CLIENT_SECRET) {
  Object.assign(patch, {
    external_google_enabled: true,
    external_google_client_id: env.GOOGLE_WEB_CLIENT_ID,
    external_google_secret: env.GOOGLE_WEB_CLIENT_SECRET,
    external_google_additional_client_ids: [env.GOOGLE_IOS_CLIENT_ID, env.GOOGLE_ANDROID_CLIENT_ID].filter(Boolean).join(','),
    external_google_skip_nonce_check: false,
  });
  notes.push('Google: enabled');
} else {
  notes.push('Google: left as is (needs GOOGLE_WEB_CLIENT_ID and GOOGLE_WEB_CLIENT_SECRET)');
}

if (env.APPLE_SERVICES_ID && env.APPLE_TEAM_ID && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY_FILE) {
  const { secret, expires } = appleClientSecret();
  Object.assign(patch, {
    external_apple_enabled: true,
    external_apple_client_id: env.APPLE_SERVICES_ID,
    external_apple_additional_client_ids: bundleId,
    external_apple_secret: secret,
  });
  notes.push(`Apple: enabled; the client secret expires ${expires.toISOString().slice(0, 10)}, rerun before then`);
} else {
  notes.push('Apple: left as is (needs APPLE_SERVICES_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_FILE)');
}

const redacted = Object.fromEntries(Object.entries(patch).map(([k, v]) => [k, k.endsWith('_secret') ? '<redacted>' : v]));
console.log(JSON.stringify(redacted, null, 2));
notes.forEach((n) => console.log(n));
if (dryRun) {
  console.log('Dry run: nothing sent.');
  process.exit(0);
}
const res = await fetch(api, { method: 'PATCH', headers, body: JSON.stringify(patch) });
if (!res.ok) {
  console.error(`Management API ${res.status}: ${await res.text()}`);
  process.exit(1);
}
console.log(`Updated auth config of ${ref}.`);
