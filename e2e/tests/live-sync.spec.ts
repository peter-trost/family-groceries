import { expect, test } from './fixtures';
import {
  addField, addItem, apiAs, createInviteCode, itemRow, newEmail, screenshot, signUp, signUpWithHousehold, tickBox, typeInto,
} from './helpers';

test('two members of one household see each other\'s changes live', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const lea = await (await browser.newContext()).newPage();

  await signUpWithHousehold(peter, newEmail('peter'));
  await addItem(peter, 'Milch');
  const code = await createInviteCode(peter);

  await signUp(lea, newEmail('lea'));
  await typeInto(lea.getByRole('textbox', { name: 'Einladungscode' }), code);
  await lea.getByRole('button', { name: 'Beitreten' }).click();
  await expect(addField(lea)).toBeFocused();
  await expect(itemRow(lea, 'Milch'), 'the joiner sees the existing list').toBeVisible();

  await addItem(peter, 'Bananen');
  await expect(itemRow(lea, 'Bananen'), 'an add in A appears in B').toBeVisible({ timeout: 2_000 });

  await tickBox(lea, 'Milch').click();
  await expect(itemRow(peter, 'Milch'), 'a tick in B disappears in A').toHaveCount(0, { timeout: 2_000 });

  await addItem(lea, 'Windeln');
  await expect(itemRow(peter, 'Windeln'), 'an add in B appears in A').toBeVisible({ timeout: 2_000 });

  await itemRow(peter, 'Bananen').click();
  await typeInto(peter.getByRole('textbox', { name: 'Menge' }), '6');
  await peter.getByRole('button', { name: 'Speichern' }).click();
  await expect(itemRow(lea, 'Bananen'), 'an edit in A updates B').toHaveAccessibleName('Bananen 6', { timeout: 2_000 });

  await itemRow(lea, 'Windeln').click();
  await lea.getByRole('button', { name: 'Löschen' }).click();
  await expect(itemRow(peter, 'Windeln'), 'a delete in B disappears in A').toHaveCount(0, { timeout: 2_000 });

  await screenshot(peter, '05-live-sync-a');
  await screenshot(lea, '06-live-sync-b');
});

test('an invite link takes a new user through sign-up straight into the household', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const lea = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, newEmail('peter'));
  await addItem(peter, 'Kaffee');
  const code = await createInviteCode(peter);

  await signUp(lea, newEmail('lea'), `/join/${code}`);
  await expect(lea.getByRole('textbox', { name: 'Einladungscode' })).toHaveValue(code);
  await lea.getByRole('button', { name: 'Beitreten' }).click();
  await expect(itemRow(lea, 'Kaffee')).toBeVisible();
});

test('a member of another household joins with a code from the menu', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const lea = await (await browser.newContext()).newPage();
  const errors: string[] = [];
  lea.on('pageerror', (e) => errors.push(e.message));
  lea.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await signUpWithHousehold(peter, newEmail('peter'));
  await addItem(peter, 'Kaffee');
  const code = await createInviteCode(peter);
  await signUpWithHousehold(lea, newEmail('lea'));
  await addItem(lea, 'Tee');

  await lea.getByRole('button', { name: 'Menü' }).click();
  await lea.getByRole('menuitem', { name: 'Anderem Haushalt beitreten' }).click();
  await typeInto(lea.getByRole('textbox', { name: 'Einladungscode' }), code.toLowerCase());
  await lea.getByRole('button', { name: 'Beitreten' }).click();
  await expect(lea, 'the code goes to the confirm screen').toHaveURL(new RegExp(`/join/${code}$`));
  await screenshot(lea, '07-join-confirm');
  await lea.getByRole('button', { name: 'Beitreten' }).click();

  await expect(itemRow(lea, 'Kaffee'), 'the joiner sees the new household\'s list').toBeVisible();
  await expect(itemRow(lea, 'Tee'), 'the old list is gone').toHaveCount(0);
  // Both opening resyncs have answered by now; a lost race shows Offline.
  await lea.waitForTimeout(1_000);
  await expect(lea.getByText(/^Offline:/), 'the new list is online').toHaveCount(0);
  await addItem(lea, 'Brot');
  await expect(itemRow(peter, 'Brot'), 'and both now share one list').toBeVisible();
  expect(errors, 'no Flutter errors on the way').toEqual([]);
});

test('a tick made while offline syncs when the connection returns', async ({ browser }) => {
  const peterContext = await browser.newContext();
  const peter = await peterContext.newPage();
  const lea = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, newEmail('peter'));
  await addItem(peter, 'Brot');
  const code = await createInviteCode(peter);
  await signUp(lea, newEmail('lea'), `/join/${code}`);
  await lea.getByRole('button', { name: 'Beitreten' }).click();
  await expect(itemRow(lea, 'Brot')).toBeVisible();

  await peterContext.setOffline(true);
  await tickBox(peter, 'Brot').click();
  await addItem(peter, 'Eier');
  await expect(itemRow(peter, 'Brot'), 'optimistic while offline').toHaveCount(0);
  await expect(itemRow(peter, 'Eier')).toBeVisible();
  await expect(peter.getByText(/^Offline:/)).toHaveCount(1);
  await screenshot(peter, '07-offline-pending');
  await expect(itemRow(lea, 'Brot'), 'the other side has not seen it yet').toBeVisible();

  await peterContext.setOffline(false);
  await expect(itemRow(lea, 'Brot')).toHaveCount(0, { timeout: 15_000 });
  await expect(itemRow(lea, 'Eier')).toBeVisible({ timeout: 15_000 });
});

test('a change made before the channel is live still shows up', async ({ page }) => {
  // Realtime confirms the join before its Postgres listener runs and says
  // "Subscribed to PostgreSQL" when it does; a change in between is never
  // delivered. Simulate that window by holding the message back.
  let ready: string | undefined;
  let live = false;
  let release = () => {};
  await page.routeWebSocket(/\/realtime\/v1\/websocket/, (ws) => {
    const server = ws.connectToServer();
    ws.onMessage((message) => server.send(message));
    server.onMessage((message) => {
      const frame = String(message);
      if (!live && frame.includes('Subscribed to PostgreSQL')) ready = frame;
      else if (!live && frame.includes('"postgres_changes",{"data"')) return;
      else ws.send(message);
    });
    release = () => {
      live = true;
      ws.send(ready!);
    };
  });
  const email = newEmail('gap');
  await signUpWithHousehold(page, email);
  await expect.poll(() => ready, { message: 'the server says it is live' }).toBeTruthy();

  const api = await apiAs(email);
  const { data } = await api.from('household_members').select('household_id').single();
  await api.from('items').insert({ household_id: data!.household_id, name: 'Zwischendurch' });
  await page.waitForTimeout(1_000);
  await expect(itemRow(page, 'Zwischendurch'), 'not delivered while the listener starts').toHaveCount(0);

  release();
  await expect(itemRow(page, 'Zwischendurch'), 'caught up once the channel is live').toBeVisible();
});

/** Routes the page's Realtime socket through the test so it can play the server's part. */
async function interceptRealtime(page: import('@playwright/test').Page) {
  const state: { joined?: unknown[]; live: boolean; close: () => void; closeChannel: () => void } = {
    live: false,
    close: () => {},
    closeChannel: () => {},
  };
  await page.routeWebSocket(/\/realtime\/v1\/websocket/, (ws) => {
    const server = ws.connectToServer();
    ws.onMessage((message) => {
      const frame = JSON.parse(String(message)) as unknown[];
      if (frame[3] === 'phx_join' && String(frame[2]).startsWith('realtime:household:')) state.joined = frame;
      server.send(message);
    });
    server.onMessage((message) => {
      if (String(message).includes('Subscribed to PostgreSQL')) state.live = true;
      ws.send(message);
    });
    state.close = () => ws.close({ code: 1011, reason: 'server restart' });
    state.closeChannel = () => ws.send(JSON.stringify([state.joined![0], null, state.joined![2], 'phx_close', {}]));
  });
  return state;
}

for (const drop of ['closes the list channel', 'drops the socket'] as const) {
  test(`the list recovers when Realtime ${drop}`, async ({ page }) => {
    const realtime = await interceptRealtime(page);
    const email = newEmail('drop');
    await signUpWithHousehold(page, email);
    await expect.poll(() => realtime.live, { message: 'the channel is live' }).toBe(true);
    realtime.live = false;

    if (drop === 'closes the list channel') realtime.closeChannel();
    else realtime.close();
    await expect(page.getByText(/^Offline:/), 'the drop shows').toHaveCount(1);

    await expect(page.getByText(/^Offline:/), 'and clears again on its own').toHaveCount(0, { timeout: 20_000 });
    await expect.poll(() => realtime.live, { message: 'live again', timeout: 20_000 }).toBe(true);
    const api = await apiAs(email);
    const { data } = await api.from('household_members').select('household_id').single();
    await api.from('items').insert({ household_id: data!.household_id, name: 'Nach dem Abbruch' });
    await expect(itemRow(page, 'Nach dem Abbruch'), 'live updates flow again').toBeVisible();
  });
}
