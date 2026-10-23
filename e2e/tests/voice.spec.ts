import { expect, test } from '@playwright/test';
import {
  apiAs,
  functionsUrl,
  itemRow,
  newEmail,
  screenshot,
  signUpWithHousehold,
} from './helpers';
import { call, connectWithToken } from './mcp-helpers';

/** Posts a sentence the way the Siri Shortcut does. */
async function say(token: string, text: string, query = '') {
  const res = await fetch(`${functionsUrl}/voice${query}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ text }),
  });
  return { status: res.status, body: await res.text() };
}

async function sessionToken(email: string): Promise<string> {
  const api = await apiAs(email);
  return (await api.auth.getSession()).data.session!.access_token;
}

test('a dictated sentence lands in the open list, split and sorted', async ({ page }) => {
  const email = newEmail('voice');
  await signUpWithHousehold(page, email);
  const token = await sessionToken(email);

  const said = await say(token, 'Milch, zwei Gurken und Klopapier', '?format=text');
  expect(said).toEqual({ status: 200, body: 'Hinzugefügt: Milch, 2 Gurken, Klopapier.' });

  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(itemRow(page, 'Gurken 2')).toBeVisible();
  await expect(itemRow(page, 'Klopapier')).toBeVisible();
  const order = await page.getByRole('heading').allInnerTexts();
  expect(order.filter((h) => ['Obst & Gemüse', 'Kühlregal', 'Haushalt'].includes(h))).toEqual([
    'Obst & Gemüse',
    'Kühlregal',
    'Haushalt',
  ]);
  await screenshot(page, 'voice-01-siri-sentence-in-list');

  const again = await say(token, 'Wir brauchen noch Milch und 1 kg Mehl', '?format=text');
  expect(again.body).toBe('Hinzugefügt: 1 kg Mehl. Schon auf der Liste: Milch.');
  await expect(itemRow(page, 'Mehl 1 kg')).toBeVisible();
  await expect(itemRow(page, 'Milch')).toHaveCount(1);
});

test('the JSON answer names each item with its category', async ({ page }) => {
  const email = newEmail('voice-json');
  await signUpWithHousehold(page, email);
  const said = await say(await sessionToken(email), 'Eine Packung Eier sowie Windeln bitte');
  expect(said.status).toBe(200);
  expect(JSON.parse(said.body)).toEqual({
    speech: 'Hinzugefügt: 1 Packung Eier, Windeln.',
    items: [
      { name: 'Eier', quantity: '1 Packung', category: 'Kühlregal', alreadyOnList: false },
      { name: 'Windeln', quantity: null, category: '👶 Drogerie', alreadyOnList: false },
    ],
  });
});

test('errors come back as German sentences Siri can speak', async ({ page }) => {
  expect(await say('fgp_not-a-token', 'Milch', '?format=text')).toEqual({
    status: 401,
    body: 'Der Zugriffstoken fehlt oder ist ungültig. Erstelle in der Einkauf-App unter Menü, Zugänge einen neuen.',
  });

  const email = newEmail('voice-errors');
  await signUpWithHousehold(page, email);
  const token = await sessionToken(email);
  const nothing = await say(token, 'Bitte, danke');
  expect(nothing.status).toBe(422);
  expect(JSON.parse(nothing.body).speech).toMatch(/^Ich habe nichts verstanden/);
});

test('Siri with a personal access token: add, then revoked is 401', async ({ page }) => {
  const email = newEmail('voice-pat');
  await signUpWithHousehold(page, email);
  const api = await apiAs(email);
  const { data, error } = await api.rpc('create_personal_access_token', { p_name: 'Siri' });
  expect(error).toBeNull();
  const [{ id, token }] = data as { id: string; token: string }[];
  expect(token).toMatch(/^fgp_/);

  const said = await say(token, 'Schreib bitte Windeln und zwei Packungen Klopapier auf', '?format=text');
  expect(said).toEqual({ status: 200, body: 'Hinzugefügt: Windeln, 2 Packungen Klopapier.' });
  await expect(itemRow(page, 'Windeln')).toBeVisible();
  await expect(itemRow(page, 'Klopapier 2 Packungen')).toBeVisible();
  await screenshot(page, 'voice-02-pat-items-in-list');

  const revoked = await api.from('personal_access_tokens').update({ revoked_at: new Date().toISOString() }).eq('id', id);
  expect(revoked.error).toBeNull();
  const after = await say(token, 'Milch', '?format=text');
  expect(after.status).toBe(401);
  expect(after.body).toMatch(/^Der Zugriffstoken fehlt oder ist ungültig/);
  await expect(itemRow(page, 'Milch')).toHaveCount(0);
});

test("a token only reaches its own household's list", async ({ browser }) => {
  const [a, b] = [await browser.newPage(), await browser.newPage()];
  const [emailA, emailB] = [newEmail('voice-a'), newEmail('voice-b')];
  await signUpWithHousehold(a, emailA);
  await signUpWithHousehold(b, emailB);
  const { data } = await (await apiAs(emailA)).rpc('create_personal_access_token', { p_name: 'Siri' });
  const [{ token }] = data as { token: string }[];

  expect((await say(token, 'Zahnpasta')).status).toBe(200);
  await expect(itemRow(a, 'Zahnpasta')).toBeVisible();
  const rowsB = await (await apiAs(emailB)).from('items').select('name');
  expect(rowsB.data).toEqual([]);
  await expect(itemRow(b, 'Zahnpasta')).toHaveCount(0);
});

test('Siri adds go through the classifier memory: move, delete, say again', async ({ page }) => {
  const email = newEmail('voice-learn');
  await signUpWithHousehold(page, email);
  const token = await sessionToken(email);
  const api = await apiAs(email);

  const first = JSON.parse((await say(token, 'Hafermilch')).body);
  const learnedFrom = first.items[0].category as string;
  const { data: categories } = await api.from('categories').select('id, name');
  const target = categories!.find((c) => c.name !== learnedFrom && c.name !== 'Sonstiges')!;

  const { data: row } = await api.from('items').select('id').eq('name', 'Hafermilch').single();
  expect((await api.from('items').update({ category_id: target.id }).eq('id', row!.id)).error).toBeNull();
  expect((await api.from('items').delete().eq('id', row!.id)).error).toBeNull();
  await expect(itemRow(page, 'Hafermilch')).toHaveCount(0);

  const again = JSON.parse((await say(token, 'Hafermilch')).body);
  expect(again.items[0]).toMatchObject({ name: 'Hafermilch', category: target.name, alreadyOnList: false });
  await expect(page.getByRole('heading', { name: target.name })).toBeVisible();
  await expect(itemRow(page, 'Hafermilch')).toBeVisible();
  await screenshot(page, 'voice-03-siri-uses-learned-category');
});

test('Siri and MCP agree on what is already on the list (plurals fold)', async ({ page }) => {
  const email = newEmail('voice-mcp');
  await signUpWithHousehold(page, email);
  const { data } = await (await apiAs(email)).rpc('create_personal_access_token', { p_name: 'Siri' });
  const [{ token }] = data as { token: string }[];

  expect((await say(token, 'Zwei Gurken', '?format=text')).body).toBe('Hinzugefügt: 2 Gurken.');
  expect((await say(token, 'Gurke', '?format=text')).body).toBe('Schon auf der Liste: 2 Gurken.');
  const mcp = await connectWithToken(token);
  const viaMcp = await call<{ added: unknown[]; alreadyOnList: { name: string }[] }>(mcp, 'add_items', {
    items: [{ name: 'Gurke' }],
  });
  expect(viaMcp.added).toEqual([]);
  expect(viaMcp.alreadyOnList.map((i) => i.name)).toEqual(['Gurken']);
  await expect(itemRow(page, 'Gurken 2')).toBeVisible();
  await expect(page.getByRole('button', { name: /^Gurke/ })).toHaveCount(1);
});
