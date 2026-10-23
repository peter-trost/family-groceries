import { expect, test } from '@playwright/test';
import {
  addField, addItem, cutOff, itemRow, newEmail, screenshot, signUpWithHousehold, tickBox, typeInto,
} from './helpers';

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
