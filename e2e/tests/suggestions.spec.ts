import { createClient } from '@supabase/supabase-js';
import { expect, test } from '@playwright/test';
import { localSecretKey } from '../stack';
import {
  addField, addItem, apiAs, cutOff, itemRow, newEmail, screenshot, signUpWithHousehold, supabaseUrl, tickBox, typeInto,
} from './helpers';

const daysAgo = (days: number, hours = 0) => new Date(Date.now() - (days * 24 + hours) * 3_600_000).toISOString();

test('typing offers what the household bought before; a tap adds it with its last quantity', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('usuals'));
  await addItem(page, '2 l Milch');
  await addItem(page, 'Mineralwasser');
  await expect(itemRow(page, 'Milch')).toHaveAccessibleName(/^Milch 2 l/);
  await tickBox(page, 'Milch').click();
  await expect(itemRow(page, 'Milch')).toHaveCount(0);

  await typeInto(addField(page), 'Mi');
  const chip = page.getByRole('button', { name: 'Vorschlag: 2 l Milch' });
  await expect(chip, 'a bought item is offered while typing').toBeVisible();
  await expect(
    page.getByRole('button', { name: /^Vorschlag: .*Mineralwasser/ }),
    'an item already on the list is not offered',
  ).toHaveCount(0);
  await screenshot(page, '10-suggestion-chips');

  await chip.click();
  await expect(itemRow(page, 'Milch'), 'added with the quantity it was bought in').toHaveAccessibleName(/^Milch 2 l/);
  await expect(addField(page), 'the chip leaves focus in the add field').toBeFocused();
  await expect(addField(page)).toHaveValue('');
  await expect(chip).toHaveCount(0);

  await page.keyboard.insertText('Brot');
  await page.keyboard.press('Enter');
  await expect(itemRow(page, 'Brot'), 'Enter adds the next item').toBeVisible();
  await expect(addField(page)).toBeFocused();
});

test('suggestions come from the device cache when Supabase is unreachable', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('usuals-offline'));
  await addItem(page, '6 Eier');
  await tickBox(page, 'Eier').click();
  await typeInto(addField(page), 'Ei');
  await expect(page.getByRole('button', { name: 'Vorschlag: 6 Eier' })).toBeVisible();
  await expect.poll(() => page.evaluate(() => {
    const key = Object.keys(localStorage).find((k) => /\blist\./.test(k));
    let value = key && JSON.parse(localStorage.getItem(key)!);
    if (typeof value === 'string') value = JSON.parse(value);
    return value?.usuals?.length ?? 0;
  }), { message: 'the usuals are in the list snapshot' }).toBe(1);

  await cutOff(page);
  await page.reload();
  await expect(page.getByRole('button', { name: 'Zuletzt gekauft' }), 'the cached list is back').toBeVisible();
  await typeInto(addField(page), 'ei');
  await page.getByRole('button', { name: 'Vorschlag: 6 Eier' }).click();
  await expect(itemRow(page, 'Eier'), 'added offline from a cached suggestion').toHaveAccessibleName(/^Eier 6/);
  await expect(addField(page)).toBeFocused();
});

test('with the field empty, what is due again is offered; a tap adds it and typing goes on', async ({ page }) => {
  const email = newEmail('usuals-due');
  await signUpWithHousehold(page, email);
  await addItem(page, '4 Brötchen');
  await expect(itemRow(page, 'Brötchen')).toHaveAccessibleName(/^Brötchen 4/);
  await tickBox(page, 'Brötchen').click();
  await expect(itemRow(page, 'Brötchen')).toHaveCount(0);
  await expect(page.getByText('Brauchen wir wieder?'), 'one purchase is not a usual interval yet').toHaveCount(0);

  // Two purchases a week apart, the last a week ago: history only the server writes.
  const api = await apiAs(email);
  const { data: item } = await api.from('items').select('id, household_id').eq('name', 'Brötchen').single();
  const admin = createClient(supabaseUrl, localSecretKey(), { auth: { persistSession: false } });
  const events = admin.from('item_events');
  expect((await events.update({ created_at: daysAgo(7) }).eq('item_id', item!.id).eq('action', 'bought')).error).toBeNull();
  expect((await events.update({ created_at: daysAgo(7, 1) }).eq('item_id', item!.id).eq('action', 'added')).error).toBeNull();
  expect((await events.insert([
    { household_id: item!.household_id, item_id: item!.id, action: 'added', item_name: 'Brötchen', created_at: daysAgo(14, 1) },
    { household_id: item!.household_id, item_id: item!.id, action: 'bought', item_name: 'Brötchen', created_at: daysAgo(14) },
  ])).error).toBeNull();

  await page.reload();
  await expect(addField(page)).toBeFocused();
  await expect(page.getByText('Brauchen wir wieder?'), 'the usual week has passed').toBeVisible();
  const chip = page.getByRole('button', { name: 'Vorschlag: 4 Brötchen' });
  await expect(chip).toBeVisible();
  await screenshot(page, '11-due-suggestions');

  await chip.click();
  await expect(itemRow(page, 'Brötchen'), 'added with its usual quantity').toHaveAccessibleName(/^Brötchen 4/);
  await expect(page.getByText('Brauchen wir wieder?'), 'nothing else is due').toHaveCount(0);
  await expect(addField(page), 'the chip leaves focus in the add field').toBeFocused();
  await page.keyboard.insertText('Butter');
  await page.keyboard.press('Enter');
  await expect(itemRow(page, 'Butter'), 'Enter adds the next item').toBeVisible();
  await expect(addField(page)).toBeFocused();
});
