import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { expect, type Locator, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import WebSocket from 'ws';

/** The local stack's settings, from the environment or `supabase status`. */
function localStack(): { url: string; key: string; mailpit: string } {
  const { SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: key, MAILPIT_URL: mailpit } = process.env;
  if (url && key) return { url, key, mailpit: mailpit ?? 'http://127.0.0.1:54324' };
  const status = execSync('supabase status -o env', { cwd: '..', encoding: 'utf8' });
  const read = (name: string) => status.match(new RegExp(`^${name}="(.*)"$`, 'm'))?.[1];
  return { url: read('API_URL')!, key: read('PUBLISHABLE_KEY')!, mailpit: read('MAILPIT_URL')! };
}

export const { url: supabaseUrl, key: publishableKey, mailpit } = localStack();
export const functionsUrl = `${supabaseUrl}/functions/v1`;

export const password = 'test-password-123';

export function newEmail(tag: string): string {
  return `${tag}-${randomUUID().slice(0, 8)}@example.test`;
}

/** A supabase-js client signed in as the given user, for API-level checks. */
export async function apiAs(email: string): Promise<SupabaseClient> {
  const client = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false },
    // Node 20 has no global WebSocket.
    realtime: { transport: WebSocket as never },
  });
  const { error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return client;
}

export const addField = (page: Page) => page.getByRole('textbox', { name: 'Was fehlt?' });
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** A list row; its accessible name is the item name, a space, then the quantity. */
export const itemRow = (page: Page, name: string) =>
  page.getByRole('button', { name: new RegExp(`^${escape(name)}( |$)`) });

export const tickBox = (page: Page, name: string) => page.getByRole('checkbox', { name: `${name} abhaken` });

/**
 * Flutter swaps in its own editor on focus, so focus first, then insert.
 * insertText (not type) because synthetic key events drop umlauts.
 */
export async function typeInto(field: Locator, text: string): Promise<void> {
  await field.click();
  await expect(field).toBeFocused();
  await field.page().keyboard.press('ControlOrMeta+a');
  await field.page().keyboard.insertText(text);
}

export async function signUp(page: Page, email: string, path = '/'): Promise<void> {
  await page.goto(path);
  await typeInto(page.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(page.getByRole('textbox', { name: 'Passwort' }), password);
  await page.getByRole('button', { name: 'Registrieren' }).click();
}

export async function signUpWithHousehold(page: Page, email: string): Promise<void> {
  await signUp(page, email);
  await page.getByRole('button', { name: 'Haushalt anlegen' }).click();
  await expect(addField(page)).toBeFocused();
}

export async function addItem(page: Page, text: string): Promise<void> {
  await typeInto(addField(page), text);
  await page.keyboard.press('Enter');
}

/** Reads the invite code from the in-app invite dialog. */
export async function createInviteCode(page: Page): Promise<string> {
  await page.getByRole('button', { name: 'Menü' }).click();
  await page.getByRole('menuitem', { name: 'Mitglied einladen' }).click();
  const code = page.getByRole('group', { name: /^Code [A-HJ-NP-Z2-9]{8}$/ });
  await expect(code).toBeVisible();
  const value = (await code.getAttribute('aria-label'))!.split(/\s+/)[1];
  await page.getByRole('button', { name: 'Schließen' }).click();
  return value;
}

export async function screenshot(page: Page, name: string): Promise<void> {
  const dir = process.env.SCREENSHOT_DIR;
  if (!dir) return;
  mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: `${dir}/${name}.png` });
}

/** The newest sign-in link Mailpit holds for `email`. */
export async function latestLinkFor(email: string): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    const res = await fetch(`${mailpit}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`);
    const { messages } = await res.json() as { messages: { ID: string }[] };
    if (messages.length > 0) {
      const message = await (await fetch(`${mailpit}/api/v1/message/${messages[0].ID}`)).json() as { Text: string };
      const link = message.Text.match(/https?:\/\/\S+\/auth\/v1\/verify\S+/)?.[0];
      if (link) return link;
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`no magic link mail for ${email}`);
}

/** A supabase-js client with no session. */
export function anonClient(): SupabaseClient {
  return createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false },
    realtime: { transport: WebSocket as never },
  });
}

export async function fakeIdToken(claims: {
  email: string; nonce?: string; aud?: string; emailVerified?: boolean; name?: string;
}): Promise<string> {
  const res = await fetch('http://127.0.0.1:54399/mint', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(claims),
  });
  return ((await res.json()) as { id_token: string }).id_token;
}

/**
 * Sends the app's next Google or Apple redirect to the fake provider as
 * `email`, or has the user cancel there. Only the provider name changes, so
 * the app's PKCE flow and Supabase's callback, code exchange and account
 * linking all run for real. Supabase passes extra authorize parameters on to
 * the provider, which reads the account from login_hint.
 */
export async function viaFakeProvider(page: Page, email: string, { cancel = false } = {}): Promise<void> {
  await page.route((url) => url.href.startsWith(`${supabaseUrl}/auth/v1/authorize?`), async (route) => {
    const url = new URL(route.request().url());
    url.searchParams.set('provider', 'keycloak');
    url.searchParams.set('login_hint', email);
    if (cancel) url.searchParams.set('deny', '1');
    await route.fulfill({ status: 302, headers: { location: url.href } });
  });
}
