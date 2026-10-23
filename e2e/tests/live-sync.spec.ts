import { expect, test } from '@playwright/test';
import {
  addField, addItem, createInviteCode, itemRow, newEmail, screenshot, signUp, signUpWithHousehold, tickBox, typeInto,
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
