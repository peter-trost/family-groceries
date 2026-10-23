import type { Tx } from '../_shared/db.ts';
import type { Added } from './handler.ts';
import type { ParsedItem } from './parse.ts';

/**
 * Adds the items through `add_items` (classifier, learned memory, store memory, duplicate check)
 * in one transaction. The splitter already read each amount, so names go in bare and a new row
 * gets the spoken quantity afterwards.
 */
export async function addItems(tx: Tx, householdId: string, items: ParsedItem[]): Promise<Added[]> {
  const active = await tx<{ id: string }[]>`
    select id from public.items where household_id = ${householdId} and status = 'active'`;
  const known = new Set(active.map((row) => row.id));
  const added: (Added & { id: string })[] = [];
  for (const item of items) {
    const [row] = await tx<
      { id: string; name: string; quantity: string | null; category: string }[]
    >`
      select a.id, a.name, a.quantity, c.name as category
      from public.add_items(${householdId}, array[${item.name}]::text[]) a
      join public.categories c on c.id = a.category_id`;
    // "Gurke und zwei Gurken" fold into one row; it is reported once.
    if (!row || added.some((a) => a.id === row.id)) continue;
    const alreadyOnList = known.has(row.id);
    if (!alreadyOnList && item.quantity !== null) {
      await tx`update public.items set quantity = ${item.quantity} where id = ${row.id}`;
    }
    added.push({
      id: row.id,
      name: row.name,
      quantity: alreadyOnList ? row.quantity : item.quantity ?? row.quantity,
      category: row.category,
      alreadyOnList,
    });
  }
  return added.map(({ id: _, ...rest }) => rest);
}
