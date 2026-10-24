import { expect, test } from './fixtures';
import { addField, addItem, itemRow, newEmail, screenshot, signUpWithHousehold } from './helpers';

test('on open the add field is focused and the list is visible beneath it', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('focus'));
  await addItem(page, 'Bananen');
  await expect(itemRow(page, 'Bananen')).toBeVisible();

  await page.reload();

  await expect(addField(page)).toBeFocused();
  await expect(page.getByText('Obst & Gemüse')).toBeVisible();
  await expect(itemRow(page, 'Bananen')).toBeVisible();
  const field = (await addField(page).boundingBox())!;
  const item = (await itemRow(page, 'Bananen').boundingBox())!;
  expect(item.y, 'the list sits below the add field on the same screen').toBeGreaterThan(field.y);

  await page.keyboard.type('Milch');
  await page.keyboard.press('Enter');
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await expect(addField(page), 'Enter keeps focus for the next item').toBeFocused();
  await expect(addField(page)).toHaveValue('');
  await screenshot(page, '01-autofocus');
});
