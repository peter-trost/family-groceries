import { expect, test } from './fixtures';
import { groupHeadings } from './catalog';
import { addField, addItem, itemRow, newEmail, screenshot, signUpWithHousehold, tickBox, typeInto } from './helpers';

test.beforeEach(async ({ page }) => {
  await signUpWithHousehold(page, newEmail('list'));
});

test('adds are grouped by category in route order', async ({ page }) => {
  for (const item of ['Klopapier', '2 Vollmilch', 'Äpfel', 'Quietscheentchen', 'Brot']) {
    await addItem(page, item);
  }
  await expect(itemRow(page, 'Quietscheentchen')).toBeVisible();
  await expect(itemRow(page, 'Vollmilch')).toHaveAccessibleName('Vollmilch 2');

  // Until the server classifies the last add, it waits under "Wird einsortiert …".
  await expect.poll(() => groupHeadings(page))
    .toEqual(['Obst & Gemüse', 'Brot & Backwaren', 'Kühlregal', 'Haushalt', 'Sonstiges']);
  await screenshot(page, '02-grouped-list');
});

test('ticking removes the item, undo brings it back, and it lands in recently bought', async ({ page }) => {
  await addItem(page, 'Joghurt');
  await expect(itemRow(page, 'Joghurt')).toBeVisible();

  await tickBox(page, 'Joghurt').click();
  await expect(itemRow(page, 'Joghurt')).toHaveCount(0);
  await expect(page.getByText('Joghurt abgehakt').first()).toBeVisible();
  await screenshot(page, '03-ticked-undo-snackbar');

  await page.getByRole('button', { name: 'Rückgängig' }).click();
  await expect(itemRow(page, 'Joghurt')).toBeVisible();

  await tickBox(page, 'Joghurt').click();
  await expect(itemRow(page, 'Joghurt')).toHaveCount(0);
  await page.reload();
  await expect(addField(page)).toBeFocused();
  await expect(itemRow(page, 'Joghurt'), 'the tick persisted on the server').toHaveCount(0);

  await page.getByRole('button', { name: 'Zuletzt gekauft' }).click();
  await page.getByRole('button', { name: 'Wieder auf die Liste' }).click();
  await expect(itemRow(page, 'Joghurt')).toBeVisible();
});

test('adding an item that is already on the list does not duplicate it', async ({ page }) => {
  await addItem(page, 'Butter');
  await expect(itemRow(page, 'Butter')).toBeVisible();
  await addItem(page, 'butter');
  await expect(page.getByText('Butter steht schon auf der Liste').first()).toBeVisible();
  await expect(itemRow(page, 'Butter')).toHaveCount(1);
});

test('edit changes name, quantity and category; delete can be undone', async ({ page }) => {
  await addItem(page, 'Sprudel');
  await itemRow(page, 'Sprudel').click();
  await typeInto(page.getByRole('textbox', { name: 'Name' }), 'Mineralwasser');
  await typeInto(page.getByRole('textbox', { name: 'Menge' }), '6 Flaschen');
  await page.getByRole('button', { name: /Kategorie/ }).click();
  await page.getByRole('menuitem', { name: 'Getränke' }).click();
  await screenshot(page, '04-edit-sheet');
  await page.getByRole('button', { name: 'Speichern' }).click();

  await expect(itemRow(page, 'Mineralwasser')).toHaveAccessibleName('Mineralwasser 6 Flaschen');
  await page.reload();
  await expect(itemRow(page, 'Mineralwasser')).toBeVisible();
  const headings = await page.getByRole('heading', { level: 2 }).allTextContents();
  expect(headings).toContain('Getränke');

  await itemRow(page, 'Mineralwasser').click();
  await page.getByRole('button', { name: 'Löschen' }).click();
  await expect(itemRow(page, 'Mineralwasser')).toHaveCount(0);
  await page.getByRole('button', { name: 'Rückgängig' }).click();
  await expect(itemRow(page, 'Mineralwasser')).toBeVisible();
  await page.reload();
  await expect(itemRow(page, 'Mineralwasser'), 'the undo re-created the row on the server').toBeVisible();
});
