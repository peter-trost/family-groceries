import { expect, test, type Page } from '@playwright/test';
import {
  addField, addItem, apiAs, itemRow, newEmail, password, screenshot, signUpWithHousehold, supabaseUrl, tickBox, typeInto,
} from './helpers';

/** Cuts the page off from Supabase (HTTP and realtime); the app itself still loads. */
async function cutOff(page: Page): Promise<{ restore: () => Promise<void> }> {
  let offline = true;
  const http = `${supabaseUrl}/**`;
  await page.route(http, (route) => route.abort());
  await page.routeWebSocket(new RegExp(`^ws://${new URL(supabaseUrl).host}/`), (ws) => {
    if (offline) ws.close();
    else ws.connectToServer();
  });
  return {
    restore: async () => {
      offline = false;
      await page.unroute(http);
    },
  };
}

/** The list snapshot the app keeps in localStorage, or null. */
function cachedList(page: Page): Promise<{ server: unknown[]; pending: unknown[] } | null> {
  return page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => /\blist\./.test(k));
    if (!key) return null;
    let value = JSON.parse(localStorage.getItem(key)!);
    if (typeof value === 'string') value = JSON.parse(value);
    return value;
  });
}

/** Makes the stored session look expired, so the start also has to survive a failed token refresh. */
async function expireStoredSession(page: Page): Promise<void> {
  const expired = await page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => /^sb-.*-auth-token$/.test(k));
    if (!key) return false;
    const session = JSON.parse(localStorage.getItem(key)!);
    session.expires_at = Math.floor(Date.now() / 1000) - 60;
    localStorage.setItem(key, JSON.stringify(session));
    return true;
  });
  expect(expired, 'the auth session is in localStorage').toBe(true);
}

test('a cold start without Supabase shows the cached list, queues changes across reloads, and syncs later', async ({ page, browser }) => {
  const email = newEmail('offline');
  await signUpWithHousehold(page, email);
  await addItem(page, 'Brot');
  await addItem(page, 'Milch');
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect.poll(async () => {
    const list = await cachedList(page);
    return list && [list.server.length, list.pending.length];
  }, { message: 'the synced list is cached' }).toEqual([2, 0]);

  const network = await cutOff(page);
  await expireStoredSession(page);
  await page.reload();
  await expect(itemRow(page, 'Brot'), 'the cached list shows offline').toBeVisible();
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(addField(page)).toBeFocused();
  await expect(page.getByText(/^Offline:/)).toHaveCount(1);

  await addItem(page, 'Käse');
  await tickBox(page, 'Brot').click();
  await expect(itemRow(page, 'Käse')).toBeVisible();
  await expect(itemRow(page, 'Brot')).toHaveCount(0);

  await page.reload();
  await expect(itemRow(page, 'Käse'), 'queued ops survive a reload while offline').toBeVisible();
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(itemRow(page, 'Brot')).toHaveCount(0);
  await expect(addField(page)).toBeFocused();
  await screenshot(page, 'offline-01-cold-start-from-cache');

  await network.restore();
  const api = await apiAs(email);
  await expect.poll(async () => {
    const { data } = await api.from('items').select('name, status').order('name');
    return data;
  }, { message: 'the queued ops reach the server', timeout: 20_000 }).toEqual([
    { name: 'Brot', status: 'bought' },
    { name: 'Käse', status: 'active' },
    { name: 'Milch', status: 'active' },
  ]);
  await expect(page.getByText(/^Offline:/)).toHaveCount(0, { timeout: 15_000 });

  const other = await (await browser.newContext()).newPage();
  await other.goto('/');
  await typeInto(other.getByRole('textbox', { name: 'E-Mail' }), email);
  await typeInto(other.getByRole('textbox', { name: 'Passwort' }), password);
  await other.getByRole('button', { name: 'Anmelden', exact: true }).click();
  await expect(itemRow(other, 'Käse'), 'another session of the same user sees the synced list').toBeVisible();
  await expect(itemRow(other, 'Milch')).toBeVisible();
  await expect(itemRow(other, 'Brot')).toHaveCount(0);
});

test('signing out drops the cached list', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('offline-out'));
  await addItem(page, 'Geheimzutat');
  await expect(itemRow(page, 'Geheimzutat')).toBeVisible();
  await expect.poll(async () => (await cachedList(page))?.server.length, { message: 'the list is cached' }).toBe(1);

  await page.getByRole('button', { name: 'Menü' }).click();
  await page.getByRole('menuitem', { name: 'Abmelden' }).click();
  await expect(page.getByRole('button', { name: 'Anmelden', exact: true })).toBeVisible();
  await expect.poll(
    () => page.evaluate(() => Object.keys(localStorage).filter((k) => /\b(list|household)\./.test(k)).length),
    { message: 'nothing of the list stays on the device' },
  ).toBe(0);
});
