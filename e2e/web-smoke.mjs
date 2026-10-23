// Smoke test for a deployed web app (Vercel production or a local copy of its output):
// SPA routing and cache headers over HTTP, then the real sign-in page up to Google's consent
// screen in Chromium. Exits non-zero on the first failed check.
// Usage: node e2e/web-smoke.mjs <base-url> [screenshot-dir]
// SMOKE_BROWSER_ONLY=1 skips the HTTP checks (for e2e/serve.mjs, which has no Vercel rules).
import { mkdirSync } from 'node:fs';
import { chromium } from '@playwright/test';

const [url, shots = '/tmp/fg-web-smoke'] = process.argv.slice(2);
if (!url) {
  console.error('usage: node e2e/web-smoke.mjs <base-url> [screenshot-dir]');
  process.exit(2);
}
mkdirSync(shots, { recursive: true });

// A protected Vercel preview opens with a share link (<url>/?_vercel_share=...); it sets a cookie.
const base = new URL(url).origin;
let cookie = '';
if (new URL(url).searchParams.has('_vercel_share')) {
  const res = await fetch(url, { redirect: 'manual' });
  cookie = res.headers.getSetCookie().map((c) => c.split(';')[0]).join('; ');
}

function check(ok, message) {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${message}`);
  if (!ok) process.exit(1);
}

async function head(path) {
  const res = await fetch(new URL(path, base), { redirect: 'manual', headers: cookie ? { cookie } : {} });
  return { status: res.status, type: res.headers.get('content-type') ?? '', cache: res.headers.get('cache-control') ?? '', body: await res.text() };
}

const httpChecks = !process.env.SMOKE_BROWSER_ONLY;
for (const path of httpChecks ? ['/', '/oauth/consent', '/join/ABC123', '/settings'] : []) {
  const r = await head(path);
  check(r.status === 200 && r.type.startsWith('text/html') && r.body.includes('flutter_bootstrap.js'), `${path} serves index.html (${r.status}, ${r.type})`);
  check(/no-cache/.test(r.cache), `${path} Cache-Control: ${r.cache}`);
}
for (const path of httpChecks ? ['/flutter_bootstrap.js', '/flutter_service_worker.js', '/version.json'] : []) {
  const r = await head(path);
  check(r.status === 200 && /no-cache/.test(r.cache), `${path} ${r.status}, Cache-Control: ${r.cache}`);
}
if (httpChecks) {
  const js = await head('/main.dart.js');
  check(js.status === 200 && js.type.includes('javascript') && /max-age=0/.test(js.cache), `/main.dart.js ${js.status}, ${js.type}, Cache-Control: ${js.cache}`);
  const missing = await head('/does-not-exist.js');
  check(missing.status === 404, `/does-not-exist.js is a 404, not index.html (${missing.status})`);
}

const browser = await chromium.launch();
try {
  const context = await browser.newContext({ viewport: { width: 420, height: 860 }, locale: 'de-DE' });
  if (cookie) {
    await context.addCookies(cookie.split('; ').map((c) => {
      const [name, ...value] = c.split('=');
      return { name, value: value.join('='), url: base };
    }));
  }
  const page = await context.newPage();
  await page.goto(new URL('/oauth/consent?authorization_id=smoke', base).href);
  const google = page.getByRole('button', { name: 'Mit Google anmelden' });
  await google.waitFor({ timeout: 60_000 });
  check(true, 'deep link /oauth/consent boots the app and shows the sign-in page');
  check(await page.getByRole('button', { name: 'Mit Apple anmelden' }).isVisible(), 'Apple button is visible');
  await page.screenshot({ path: `${shots}/1-sign-in.png` });

  await google.click();
  await page.waitForURL(/accounts\.google\.com/, { timeout: 30_000 });
  const url = new URL(page.url());
  check(url.hostname === 'accounts.google.com', `Google sign-in reached ${url.hostname}${url.pathname}`);
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.screenshot({ path: `${shots}/2-google-consent.png` });
  const clientId = url.searchParams.get('client_id') ?? new URLSearchParams(url.searchParams.get('continue') ?? '').get('client_id');
  console.log(`     client_id=${clientId ?? '(inside continue param)'}`);

  const applePage = await context.newPage();
  await applePage.goto(base);
  await applePage.getByRole('button', { name: 'Mit Apple anmelden' }).click({ timeout: 60_000 });
  await applePage.waitForURL(/appleid\.apple\.com/, { timeout: 30_000 });
  check(new URL(applePage.url()).searchParams.get('client_id') === 'com.petertrost.familygroceries.web', `Apple sign-in reached ${new URL(applePage.url()).hostname} for the Services ID`);
  await applePage.waitForLoadState('networkidle').catch(() => {});
  await applePage.screenshot({ path: `${shots}/3-apple-sign-in.png` });
  console.log(`screenshots in ${shots}`);
} finally {
  await browser.close();
}
