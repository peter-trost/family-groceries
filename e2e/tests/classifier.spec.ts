import { expect, test } from '@playwright/test';
import { deleteItem, dragItemTo, expectGroup } from './catalog';
import { addItem, apiAs, itemRow, newEmail, screenshot, signUpWithHousehold, tickBox } from './helpers';

test('CLASSIFIER-LEARNING: add -> X, move -> Y, re-add -> Y, in this household only', async ({ browser }) => {
  const peterEmail = newEmail('learn');
  const peter = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, peterEmail);

  await addItem(peter, 'Hafermilch');
  await expectGroup(peter, 'Hafermilch', 'Kühlregal');
  await dragItemTo(peter, 'Hafermilch', 'Getränke');
  await expectGroup(peter, 'Hafermilch', 'Getränke');
  await screenshot(peter, '01-dragged-to-getraenke');
  await deleteItem(peter, 'Hafermilch');
  await addItem(peter, '2 Hafermilch');
  await expectGroup(peter, 'Hafermilch', 'Getränke');

  await addItem(peter, 'Zahnbürste');
  await expectGroup(peter, 'Zahnbürste', '👶 Drogerie');
  await itemRow(peter, 'Zahnbürste').click();
  await peter.getByRole('button', { name: /Kategorie/ }).click();
  await peter.getByRole('menuitem', { name: 'Haushalt' }).click();
  await peter.getByRole('button', { name: 'Speichern' }).click();
  await expectGroup(peter, 'Zahnbürste', 'Haushalt');
  await tickBox(peter, 'Zahnbürste').click();
  await addItem(peter, 'Zahnbürsten');
  await expectGroup(peter, 'Zahnbürsten', 'Haushalt');
  await screenshot(peter, '02-relearned-after-readd');

  const api = await apiAs(peterEmail);
  const { data: household } = await api.from('households').select('id').single();
  await tickBox(peter, 'Hafermilch').click();
  await expect(itemRow(peter, 'Hafermilch')).toHaveCount(0);
  const { data: added, error } = await api.rpc('add_items', {
    p_household: household!.id,
    p_names: ['Hafermilch', '1 Packung Kaffee'],
  });
  expect(error).toBeNull();
  expect(added.map((i: { name: string; quantity: string | null }) => [i.name, i.quantity]))
    .toEqual([['Hafermilch', null], ['Kaffee', '1 Packung']]);
  await expectGroup(peter, 'Hafermilch', 'Getränke');

  const lea = await (await browser.newContext()).newPage();
  await signUpWithHousehold(lea, newEmail('other-household'));
  await addItem(lea, 'Hafermilch');
  await addItem(lea, 'Zahnbürste');
  await expectGroup(lea, 'Hafermilch', 'Kühlregal');
  await expectGroup(lea, 'Zahnbürste', '👶 Drogerie');
  await screenshot(lea, '03-other-household-unaffected');
});

test('seed dictionary spot checks: compounds, plurals, quantities, umlauts', async ({ page }) => {
  await signUpWithHousehold(page, newEmail('seed'));
  const expected: Record<string, string> = {
    'Vollkornbrot': 'Brot & Backwaren',
    'Schlagsahne': 'Kühlregal',
    '6 Eier': 'Kühlregal',
    'Rinderhack': 'Fleisch/Wurst/Fisch',
    'Kichererbsen': 'Vorrat & Konserven',
    'Gummibärchen': 'Süßes & Snacks',
    'Apfelschorle': 'Getränke',
    'Fischstäbchen': 'Tiefkühl',
    'Spülmaschinentabs': 'Haushalt',
    'Windeln Größe 4': '👶 Drogerie',
    'Aepfel 2 kg': 'Obst & Gemüse',
    'Quietscheentchen': 'Sonstiges',
  };
  for (const item of Object.keys(expected)) await addItem(page, item);
  await expect(itemRow(page, 'Quietscheentchen')).toBeVisible();
  for (const [input, group] of Object.entries(expected)) {
    const name = input.replace(/^\d+ /, '').replace(/ \d+ kg$/, '');
    await expectGroup(page, name, group);
  }
  await screenshot(page, '04-seed-dictionary');
});
