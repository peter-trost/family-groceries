import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { expect, type Locator, type Page } from '@playwright/test';
import { execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import WebSocket from 'ws';

/** The local stack's settings, from the environment or `supabase status`. */
function localStack(): { url: string; key: string } {
  const { SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: key } = process.env;
  if (url && key) return { url, key };
  const status = execSync('supabase status -o env', { cwd: '..', encoding: 'utf8' });
  const read = (name: string) => status.match(new RegExp(`^${name}="(.*)"$`, 'm'))?.[1];
  return { url: read('API_URL')!, key: read('PUBLISHABLE_KEY')! };
}

const { url: supabaseUrl, key: publishableKey } = localStack();

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
