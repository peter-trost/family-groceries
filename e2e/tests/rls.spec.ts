import { expect, test } from './fixtures';
import { addItem, apiAs, itemRow, newEmail, signUpWithHousehold } from './helpers';

test('a user from another household can neither see nor change the list', async ({ browser }) => {
  const peterEmail = newEmail('peter');
  const eveEmail = newEmail('eve');
  const peter = await (await browser.newContext()).newPage();
  const eve = await (await browser.newContext()).newPage();
  await signUpWithHousehold(peter, peterEmail);
  await addItem(peter, 'Geheimzutat');
  await expect(itemRow(peter, 'Geheimzutat')).toBeVisible();
  await signUpWithHousehold(eve, eveEmail);
  await expect(itemRow(eve, 'Geheimzutat'), 'not in the other household\'s UI').toHaveCount(0);

  const peterApi = await apiAs(peterEmail);
  const { data: own } = await peterApi.from('items').select('id, household_id').eq('name', 'Geheimzutat').single();
  const householdId = own!.household_id as string;

  const eveApi = await apiAs(eveEmail);
  const read = await eveApi.from('items').select('*').eq('household_id', householdId);
  expect(read.data, 'reading by household id returns nothing').toEqual([]);
  const categories = await eveApi.from('categories').select('*').eq('household_id', householdId);
  expect(categories.data).toEqual([]);

  const insert = await eveApi.from('items').insert({ household_id: householdId, name: 'Eingeschleust' });
  expect(insert.error?.code, 'insert is denied by RLS').toBe('42501');

  const update = await eveApi.from('items').update({ name: 'Gehackt' }).eq('id', own!.id).select();
  expect(update.data).toEqual([]);
  const del = await eveApi.from('items').delete().eq('id', own!.id).select();
  expect(del.data).toEqual([]);
  const invite = await eveApi.rpc('create_invite', { p_household: householdId });
  expect(invite.error?.message).toBe('not_a_member');
  const classify = await eveApi.rpc('classify_item', { p_household: householdId, p_name: 'Milch' });
  expect(classify.data, 'classify does not reveal another household\'s category ids').toBeNull();
  expect(classify.error?.message).toBe('not_a_member');

  const { data: after } = await peterApi.from('items').select('name').eq('id', own!.id).single();
  expect(after!.name, 'the row is untouched').toBe('Geheimzutat');

  // Realtime: Eve listening on Peter's household receives nothing.
  const received: unknown[] = [];
  const channel = eveApi.channel('spy').on(
    'postgres_changes',
    { event: '*', schema: 'public', table: 'items', filter: `household_id=eq.${householdId}` },
    (payload) => received.push(payload),
  );
  await new Promise<void>((resolve) => channel.subscribe((status) => status === 'SUBSCRIBED' && resolve()));
  await addItem(peter, 'Noch geheimer');
  await expect(itemRow(peter, 'Noch geheimer')).toBeVisible();
  await peter.waitForTimeout(1_500);
  expect(received, 'no realtime events leak across households').toEqual([]);
  await eveApi.removeAllChannels();
});
