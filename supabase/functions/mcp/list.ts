// The shopping-list operations behind the MCP tools. Every function runs inside asUser(), so RLS
// confines it to the caller's household; household_id filters only narrow the query plan.
import type { Tx } from '../_shared/db.ts';

export class ToolError extends Error {}

export type Named = { id: string; name: string };

export type Item = {
  id: string;
  name: string;
  quantity: string | null;
  category: string;
  store: string | null;
};

/** Lowercase, umlauts folded, everything but letters and digits dropped: "👶 Drogerie" ~ "drogerie". */
export function fold(text: string): string {
  return text.toLowerCase()
    .replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss')
    .replace(/[^\p{L}\p{N}]+/gu, '');
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Finds one entry by id, exact name, or a unique partial name. Names are matched folded, so
 * "kuehlregal", "Kühlregal" and "kühl" all find "Kühlregal".
 */
export function resolve<T extends Named>(options: readonly T[], query: string, what: string): T {
  const byId = UUID.test(query) ? options.find((o) => o.id === query.toLowerCase()) : undefined;
  if (byId) return byId;
  const q = fold(query);
  const exact = options.filter((o) => fold(o.name) === q);
  if (exact.length === 1) return exact[0];
  const partial = q === '' ? [] : options.filter((o) => fold(o.name).includes(q));
  if (exact.length === 0 && partial.length === 1) return partial[0];
  const candidates = exact.length > 1 ? exact : partial;
  if (candidates.length > 1) {
    throw new ToolError(
      `${what} „${query}“ ist nicht eindeutig: ${candidates.map((c) => c.name).join(', ')}.`,
    );
  }
  throw new ToolError(
    `${what} „${query}“ nicht gefunden. Vorhanden: ${
      options.map((o) => o.name).join(', ') || '(keine)'
    }.`,
  );
}

export function categories(tx: Tx, household: string): Promise<(Named & { sort_order: number })[]> {
  return tx`select id, name, sort_order from public.categories
            where household_id = ${household} order by sort_order, name`;
}

export function stores(tx: Tx, household: string): Promise<(Named & { sort_order: number })[]> {
  return tx`select id, name, sort_order from public.stores
            where household_id = ${household} order by sort_order, name`;
}

function activeItems(tx: Tx, household: string): Promise<Named[]> {
  return tx`select id, name from public.items
            where household_id = ${household} and status = 'active' order by created_at`;
}

function itemsById(tx: Tx, ids: readonly string[]): Promise<Item[]> {
  return tx`
    select i.id, i.name, i.quantity, c.name as category, s.name as store
    from public.items i
    join public.categories c on c.id = i.category_id
    left join public.stores s on s.id = i.store_id
    where i.id = any(${ids}::uuid[])`;
}

export async function listItems(
  tx: Tx,
  household: string,
  filter: { store?: string; category?: string },
): Promise<{ store: string | null; category: string | null; items: Item[] }> {
  const store = filter.store ? resolve(await stores(tx, household), filter.store, 'Laden') : null;
  const category = filter.category
    ? resolve(await categories(tx, household), filter.category, 'Kategorie')
    : null;
  const storeId = store?.id ?? null;
  const categoryId = category?.id ?? null;
  // A store view shows the store's own items plus untagged ones, in that store's aisle order.
  const items = await tx<Item[]>`
    select i.id, i.name, i.quantity, c.name as category, s.name as store
    from public.items i
    join public.categories c on c.id = i.category_id
    left join public.stores s on s.id = i.store_id
    left join public.store_category_order o
      on o.store_id = ${storeId}::uuid and o.category_id = i.category_id
    where i.household_id = ${household} and i.status = 'active'
      and (${storeId}::uuid is null or i.store_id is null or i.store_id = ${storeId}::uuid)
      and (${categoryId}::uuid is null or i.category_id = ${categoryId}::uuid)
    order by coalesce(o.sort_order, c.sort_order), c.name, i.created_at`;
  return { store: store?.name ?? null, category: category?.name ?? null, items };
}

export type NewItem = { name: string; quantity?: string; category?: string; store?: string };

/**
 * Adds items, skipping names already on the active list (matched by `item_name_key`, as `add_items`
 * and Siri do: "Gurke" is "2 Gurken"). Items without a category go through the items trigger and
 * so through classify_item and the store memory, like everything the app adds.
 */
export async function addItems(
  tx: Tx,
  household: string,
  wanted: readonly NewItem[],
): Promise<{ added: Item[]; alreadyOnList: Item[] }> {
  const [cats, shops, active] = await Promise.all([
    categories(tx, household),
    stores(tx, household),
    tx<{ id: string; key: string }[]>`
      select id, public.item_name_key(name) as key from public.items
      where household_id = ${household} and status = 'active'`,
  ]);
  const onList = new Map(active.map((i) => [i.key, i.id]));
  const added: string[] = [];
  const existing: string[] = [];
  for (const item of wanted) {
    const name = item.name.trim();
    if (name === '') continue;
    const [{ key }] = await tx<{ key: string }[]>`select public.item_name_key(${name}) as key`;
    const already = onList.get(key);
    if (already) {
      existing.push(already);
      continue;
    }
    const category = item.category ? resolve(cats, item.category, 'Kategorie').id : null;
    const store = item.store ? resolve(shops, item.store, 'Laden').id : null;
    const [row] = await tx<{ id: string }[]>`
      insert into public.items (household_id, name, quantity, category_id, store_id)
      values (${household}, ${name.slice(0, 120)}, ${item.quantity?.trim().slice(0, 40) || null},
              ${category}, ${store})
      returning id`;
    onList.set(key, row.id);
    added.push(row.id);
  }
  const rows = await itemsById(tx, [...added, ...existing]);
  const pick = (ids: string[]) => ids.map((id) => rows.find((r) => r.id === id)!);
  return { added: pick(added), alreadyOnList: pick(existing) };
}

export async function tickItems(
  tx: Tx,
  household: string,
  refs: readonly string[],
): Promise<{ ticked: Item[]; notFound: { item: string; reason: string }[] }> {
  const active = await activeItems(tx, household);
  const ids: string[] = [];
  const notFound: { item: string; reason: string }[] = [];
  for (const ref of refs) {
    try {
      ids.push(resolve(active, ref, 'Eintrag').id);
    } catch (e) {
      if (!(e instanceof ToolError)) throw e;
      notFound.push({ item: ref, reason: e.message });
    }
  }
  if (ids.length > 0) {
    await tx`update public.items set status = 'bought' where id = any(${ids}::uuid[])`;
  }
  return { ticked: await itemsById(tx, ids), notFound };
}

export async function moveItem(
  tx: Tx,
  household: string,
  move: { item: string; category?: string; store?: string | null },
): Promise<Item> {
  if (move.category === undefined && move.store === undefined) {
    throw new ToolError('Gib eine Kategorie oder einen Laden an.');
  }
  const item = resolve(await activeItems(tx, household), move.item, 'Eintrag');
  if (move.category !== undefined) {
    const category = resolve(await categories(tx, household), move.category, 'Kategorie');
    await tx`update public.items set category_id = ${category.id} where id = ${item.id}`;
  }
  if (move.store !== undefined) {
    const store = move.store === null || move.store.trim() === ''
      ? null
      : resolve(await stores(tx, household), move.store, 'Laden');
    await tx`update public.items set store_id = ${store?.id ?? null} where id = ${item.id}`;
  }
  const [moved] = await itemsById(tx, [item.id]);
  return moved;
}
