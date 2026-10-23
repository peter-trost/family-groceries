import { expect, test } from '@playwright/test';
import { dragHandle, groupHeadings, selectStore } from './catalog';
import {
  addField, addItem, createInviteCode, itemRow, newEmail, screenshot, signUp, signUpWithHousehold, tickBox, typeInto,
} from './helpers';

const route = [
  'Obst & Gemüse', 'Brot & Backwaren', 'Kühlregal', 'Fleisch/Wurst/Fisch', 'Süßes & Snacks', 'Tiefkühl', 'Haushalt',
  '👶 Drogerie',
];

async function setStore(page: import('@playwright/test').Page, item: string, store: string): Promise<void> {
  await itemRow(page, item).click();
  await page.getByRole('button', { name: /Geschäft/ }).click();
  await page.getByRole('menuitem', { name: store, exact: true }).click();
  await page.getByRole('button', { name: 'Speichern' }).click();
}

test('STORE ORDERING: each store groups in its own order, editable by drag, with item->store memory', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('stores'));
  for (const item of ['Brot', 'Äpfel', 'Milch', 'Hack', 'Zahnpasta', 'Klopapier', 'Chips', 'Pizza']) {
    await addItem(page, item);
  }
  await expect(itemRow(page, 'Pizza')).toBeVisible();
  await expect(addField(page), 'the picker does not take focus from the add field').toBeFocused();
  await expect.poll(() => groupHeadings(page)).toEqual(route);

  await selectStore(page, 'Lidl');
  await expect.poll(() => groupHeadings(page), { message: 'Lidl: bake station first' }).toEqual([
    'Brot & Backwaren', 'Obst & Gemüse', 'Kühlregal', 'Fleisch/Wurst/Fisch', 'Süßes & Snacks', 'Tiefkühl', 'Haushalt',
    '👶 Drogerie',
  ]);
  await page.mouse.move(0, 899);
  await screenshot(page, '05-store-lidl');

  await selectStore(page, 'Edeka');
  await expect.poll(() => groupHeadings(page), { message: 'Edeka: counters before the chilled aisle' }).toEqual([
    'Obst & Gemüse', 'Brot & Backwaren', 'Fleisch/Wurst/Fisch', 'Kühlregal', 'Süßes & Snacks', 'Tiefkühl', 'Haushalt',
    '👶 Drogerie',
  ]);

  await selectStore(page, 'dm');
  await expect.poll(() => groupHeadings(page), { message: 'dm: only what a drugstore carries' }).toEqual([
    '👶 Drogerie', 'Süßes & Snacks', 'Haushalt',
  ]);
  const hidden = page.getByRole('button', { name: '5 Artikel, die es bei dm meist nicht gibt, anzeigen' });
  await expect(hidden).toBeVisible();
  await page.mouse.move(0, 899);
  await screenshot(page, '06-store-dm');
  await hidden.click();
  await expect(itemRow(page, 'Milch')).toBeVisible();
  await page.getByRole('button', { name: '5 Artikel, die es bei dm meist nicht gibt, ausblenden' }).click();
  await expect(itemRow(page, 'Milch')).toHaveCount(0);

  await page.getByRole('button', { name: 'Reihenfolge bearbeiten' }).click();
  await expect(page.getByText('dm: Reihenfolge')).toBeVisible();
  await page.getByRole('switch', { name: 'Kühlregal gibt es bei dm' }).click();
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect.poll(() => groupHeadings(page), { message: 'dm now carries the chilled aisle' }).toEqual([
    '👶 Drogerie', 'Süßes & Snacks', 'Haushalt', 'Kühlregal',
  ]);

  await selectStore(page, 'Lidl');
  await page.getByRole('button', { name: 'Reihenfolge bearbeiten' }).click();
  await dragHandle(page, 'Tiefkühl verschieben', 'Brot & Backwaren verschieben');
  await screenshot(page, '07-store-layout-editor');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect.poll(() => groupHeadings(page), { message: 'the reorder applies to the Lidl view' }).toEqual([
    'Tiefkühl', 'Brot & Backwaren', 'Obst & Gemüse', 'Kühlregal', 'Fleisch/Wurst/Fisch', 'Süßes & Snacks', 'Haushalt',
    '👶 Drogerie',
  ]);
  await page.reload();
  await expect(addField(page)).toBeFocused();
  await expect.poll(() => groupHeadings(page), { message: 'after a reload the picker is back on Alle' }).toEqual(route);
  await selectStore(page, 'Lidl');
  await expect.poll(async () => (await groupHeadings(page))[0], { message: 'the Lidl order was saved' })
    .toBe('Tiefkühl');

  await tickBox(page, 'Hack').click();
  await expect(itemRow(page, 'Hack')).toHaveCount(0);
  await selectStore(page, 'Alle');
  await addItem(page, 'Hack');
  await selectStore(page, 'Edeka');
  await expect(itemRow(page, 'Klopapier'), 'untagged items show at every supermarket').toBeVisible();
  await expect(itemRow(page, 'Hack'), 'bought at Lidl last time, so not listed for Edeka').toHaveCount(0);
  await selectStore(page, 'Lidl');
  await expect(itemRow(page, 'Hack'), 'remembered for Lidl').toBeVisible();

  await setStore(page, 'Zahnpasta', 'dm');
  await expect(itemRow(page, 'Zahnpasta'), 'tagged for dm, gone from the Lidl view').toHaveCount(0);
  await selectStore(page, 'dm');
  await expect(itemRow(page, 'Zahnpasta')).toBeVisible();
  await expect(itemRow(page, 'Klopapier'), 'untagged household goods show at dm too').toBeVisible();
  await page.mouse.move(0, 899);
  await screenshot(page, '08-store-memory-dm');

  await selectStore(page, 'Edeka');
  await addItem(page, 'Butter');
  await expect(itemRow(page, 'Butter'), 'typed in the Edeka view, it stays there').toBeVisible();
  await selectStore(page, 'Lidl');
  await expect(itemRow(page, 'Butter')).toHaveCount(0);

  await selectStore(page, 'Alle');
  await addItem(page, 'Zahnpasta');
  await expect(page.getByText('Zahnpasta steht schon auf der Liste').first()).toBeVisible();
  await tickBox(page, 'Zahnpasta').click();
  await addItem(page, 'Zahnpasta');
  await selectStore(page, 'Lidl');
  await expect(page.getByRole('heading', { name: 'Tiefkühl' })).toBeVisible();
  await expect(itemRow(page, 'Zahnpasta'), 're-added, it is still a dm item').toHaveCount(0);
});

test('category and store layout changes sync live to the other member', async ({ browser }) => {
  const peter = await (await browser.newContext()).newPage();
  const lea = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, newEmail('peter-cat'));
  await addItem(peter, 'Spülmittel');
  await addItem(peter, 'Brot');
  const code = await createInviteCode(peter);
  await signUp(lea, newEmail('lea-cat'));
  await typeInto(lea.getByRole('textbox', { name: 'Einladungscode' }), code);
  await lea.getByRole('button', { name: 'Beitreten' }).click();
  await expect(itemRow(lea, 'Spülmittel')).toBeVisible();
  await selectStore(lea, 'Lidl');
  await expect.poll(() => groupHeadings(lea)).toEqual(['Brot & Backwaren', 'Haushalt']);

  await selectStore(peter, 'Lidl');
  await peter.getByRole('button', { name: 'Reihenfolge bearbeiten' }).click();
  await dragHandle(peter, 'Haushalt verschieben', 'Brot & Backwaren verschieben');
  await expect.poll(() => groupHeadings(lea), { message: 'a store reorder in A reaches B', timeout: 3_000 })
    .toEqual(['Haushalt', 'Brot & Backwaren']);
  await peter.getByRole('button', { name: 'Zurück' }).click();

  await peter.getByRole('button', { name: 'Menü' }).click();
  await peter.getByRole('menuitem', { name: 'Kategorien verwalten' }).click();
  await peter.getByRole('button', { name: 'Haushalt', exact: true }).click();
  await typeInto(peter.getByRole('textbox', { name: 'Name' }), 'Putzzeug');
  await peter.getByRole('button', { name: 'Speichern' }).click();
  await expect.poll(() => groupHeadings(lea), { message: 'a rename in A reaches B', timeout: 3_000 })
    .toEqual(['Putzzeug', 'Brot & Backwaren']);
  await screenshot(lea, '09-live-catalog-sync');
});

test('categories: add, move an item there, rename, reorder, delete with reassignment', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('categories'));
  await addItem(page, 'Windeln');
  await addItem(page, 'Bier');
  await page.getByRole('button', { name: 'Menü' }).click();
  await page.getByRole('menuitem', { name: 'Kategorien verwalten' }).click();

  await page.getByRole('button', { name: 'Kategorie hinzufügen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name' }), 'Baby');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('button', { name: 'Baby', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Kategorie hinzufügen' }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name' }), 'Baby');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByText('Eine Kategorie „Baby“ gibt es schon.').first()).toBeVisible();

  await dragHandle(page, 'Getränke verschieben', 'Obst & Gemüse verschieben');
  await screenshot(page, '10-categories-screen');
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect.poll(() => groupHeadings(page), { message: 'the route order changed' })
    .toEqual(['Getränke', '👶 Drogerie']);

  await itemRow(page, 'Windeln').click();
  await page.getByRole('button', { name: /Kategorie/ }).click();
  await page.getByRole('menuitem', { name: 'Baby' }).click();
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect.poll(() => groupHeadings(page)).toEqual(['Getränke', 'Baby']);

  await page.getByRole('button', { name: 'Menü' }).click();
  await page.getByRole('menuitem', { name: 'Kategorien verwalten' }).click();
  await page.getByRole('button', { name: 'Baby', exact: true }).click();
  await typeInto(page.getByRole('textbox', { name: 'Name' }), 'Babysachen');
  await page.getByRole('button', { name: 'Speichern' }).click();
  await expect(page.getByRole('button', { name: 'Sonstiges löschen' }), 'the fallback cannot be deleted').toHaveCount(0);
  await page.getByRole('button', { name: 'Babysachen löschen' }).click();
  await page.getByRole('button', { name: /Artikel verschieben nach/ }).click();
  await page.getByRole('menuitem', { name: '👶 Drogerie' }).click();
  await page.getByRole('button', { name: 'Löschen', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Babysachen', exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Zurück' }).click();
  await expect.poll(() => groupHeadings(page), { message: 'the items moved to the chosen category' })
    .toEqual(['Getränke', '👶 Drogerie']);

  await page.reload();
  await expect(addField(page)).toBeFocused();
  await expect.poll(() => groupHeadings(page)).toEqual(['Getränke', '👶 Drogerie']);
});
