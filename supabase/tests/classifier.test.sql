begin;
select plan(56);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.cat(p_household uuid, p_seed text) returns uuid language sql as $$
  select id from public.categories where household_id = p_household and seed_key = p_seed;
$$;

create function pg_temp.store(p_household uuid, p_seed text) returns uuid language sql as $$
  select id from public.stores where household_id = p_household and seed_key = p_seed;
$$;

create function pg_temp.seed_of(p_category uuid) returns text language sql as $$
  select coalesce(seed_key, name) from public.categories where id = p_category;
$$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'carla@example.com'),
  ('00000000-0000-0000-0000-0000000000d1', 'dora@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
create temp table hd as select id from public.create_household('Dora');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
create temp table hc as select id from public.create_household('Carla');
grant select on hc, hd to authenticated;

-- Item keys: one form per item across case, umlauts, quantities and plurals.
select is(public.item_key(x), 'apfel', format('key of %L', x))
from unnest(array['Apfel', 'Äpfel', 'aepfel', '2 kg Äpfel', 'ÄPFEL ']) as x;
select is(public.item_key('Gurken'), public.item_key('Gurke'), 'Gurken and Gurke share a key');
select is(public.item_key('Zwiebeln'), public.item_key('zwiebel'), 'Zwiebeln and Zwiebel share a key');
select is(public.item_key('Joghurts'), public.item_key('Joghurt'), 'Joghurts and Joghurt share a key');
select is(public.item_key('Kekse'), public.item_key('Keks'), 'Kekse and Keks share a key');
select is(public.item_key('Würste'), public.item_key('Wurst'), 'Würste and Wurst share a key');
select isnt(public.item_key('Eis'), public.item_key('Eier'), 'Eis and Eier stay apart');
select is(public.item_key('Bio-Vollmilch 3,5%'), 'bio vollmilch', 'punctuation and percentages drop out');
select is(public.item_key('Füße straße'), 'fuss strass', 'ß becomes ss');
select is(public.item_key('Milch 1,5 l'), 'milch', 'trailing amounts with units drop out');
select is(public.item_key('3x Joghurt'), 'joghurt', '3x drops out');

-- parse_entry mirrors the app's parseEntry.
select results_eq(
  $$ select (public.parse_entry(x)).* from unnest(array[
       '2 Gurken', '3x Joghurt', 'Hack 500 g', 'Windeln Größe 4', '1,5 l Milch', '  Brot  ', '500g Mehl', 'Milch 2 Flaschen',
       '1 Packung Eier', '1 Kasten Wasser', '10 Stück Eier', '1 Pfund Kaffee', '0,5 kg Hackfleisch'
     ]) with ordinality as t (x, n) order by n $$,
  $$ values ('Gurken', '2'), ('Joghurt', '3'), ('Hack', '500 g'), ('Windeln Größe 4', null),
            ('Milch', '1,5 l'), ('Brot', null), ('Mehl', '500 g'), ('Milch', '2 Flaschen'),
            ('Eier', '1 Packung'), ('Wasser', '1 Kasten'), ('Eier', '10 Stück'), ('Kaffee', '1 Pfund'),
            ('Hackfleisch', '0,5 kg') $$,
  'parse_entry splits name and quantity like the app'
);

-- Pipeline: dictionary, compound suffix, fallback.
select is(pg_temp.seed_of(public.classify_item((select id from hc), 'Vollmilch')), 'chilled', 'compound suffix: Vollmilch');
select is(pg_temp.seed_of(public.classify_item((select id from hc), '2 Gurken')), 'produce', 'quantity and plural: 2 Gurken');
select is(pg_temp.seed_of(public.classify_item((select id from hc), 'Quietscheentchen-Zubehör')), 'other', 'unknown items fall back');

-- Learning: a category change is a correction, the latest one wins.
insert into public.items (household_id, name) select id, 'Quietscheentchen' from hc;
select is(pg_temp.seed_of(category_id), 'other', 'an unknown item starts in Sonstiges')
from public.items where name = 'Quietscheentchen';
update public.items set category_id = pg_temp.cat((select id from hc), 'drinks') where name = 'Quietscheentchen';
select is(pg_temp.seed_of(public.classify_item((select id from hc), '2 QUIETSCHEENTCHEN')), 'drinks',
  'the correction is learned under the item key');
update public.items set category_id = pg_temp.cat((select id from hc), 'chilled') where name = 'Quietscheentchen';
select is(pg_temp.seed_of(public.classify_item((select id from hc), 'Quietscheentchen')), 'chilled', 'the latest correction wins');
update public.items set category_id = pg_temp.cat((select id from hc), 'drinks') where name = 'Quietscheentchen';
update public.items set category_id = pg_temp.cat((select id from hc), 'chilled') where name = 'Quietscheentchen';
select results_eq(
  $$ select pg_temp.seed_of(category_id), corrections from public.category_memory
     where household_id = (select id from hc) order by updated_at $$,
  $$ values ('drinks', 2), ('chilled', 2) $$,
  'corrections are counted per category'
);
update public.items set category_id = pg_temp.cat((select id from hc), 'meat') where name = 'Quietscheentchen';
select is(pg_temp.seed_of(public.classify_item((select id from hc), 'Vollmilch')), 'chilled',
  'learning one item leaves others alone');
delete from public.items where name = 'Quietscheentchen';
insert into public.items (household_id, name) select id, 'Quietscheentchen' from hc;
select is(pg_temp.seed_of(category_id), 'meat', 're-added, the item lands where it was last moved')
from public.items where name = 'Quietscheentchen';
update public.items set name = 'Quietscheentchen!', quantity = '2' where name = 'Quietscheentchen';
select is((select count(*)::int from public.category_memory where household_id = (select id from hc)), 3,
  'edits that keep the category teach nothing');

select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select is(pg_temp.seed_of(public.classify_item((select id from hd), 'Quietscheentchen')), 'other',
  'another household is unaffected by these corrections');
select is((select count(*)::int from public.category_memory), 0, 'and cannot read them');
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');

-- Item->store memory: tagging, ticking in a store, clearing.
insert into public.items (household_id, name) select id, 'Zahnpasta' from hc;
select is(store_id, null, 'an item without memory is untagged') from public.items where name = 'Zahnpasta';
update public.items set store_id = pg_temp.store((select id from hc), 'dm') where name = 'Zahnpasta';
update public.items set status = 'bought' where name = 'Zahnpasta';
select is(times, 2, 'a tag and a tick in the store both count')
from public.item_store_memory where item_key = 'zahnpasta';
select is(public.suggest_store((select id from hc), 'zahnpasta'), pg_temp.store((select id from hc), 'dm'),
  'suggest_store returns the remembered store');
update public.items set status = 'active' where name = 'Zahnpasta';
delete from public.items where name = 'Zahnpasta';
insert into public.items (household_id, name) select id, 'Zahnpasta' from hc;
select is(store_id, pg_temp.store((select id from hc), 'dm'), 're-added, the item is tagged with its store')
from public.items where name = 'Zahnpasta';
update public.items set store_id = pg_temp.store((select id from hc), 'lidl') where name = 'Zahnpasta';
select is(public.suggest_store((select id from hc), 'Zahnpasta'), pg_temp.store((select id from hc), 'lidl'),
  'the latest store wins');
update public.items set store_id = null where name = 'Zahnpasta';
select is(public.suggest_store((select id from hc), 'Zahnpasta'), null, 'untagging means any supermarket again');

-- add_items: the shared add path for MCP and Siri.
select results_eq(
  $$ select name, quantity, pg_temp.seed_of(category_id) from public.add_items(
       (select id from hc), array['2 Gurken', 'Windeln Größe 4', 'Hack 500 g', '  ', 'Gurke']) $$,
  $$ values ('Gurken', '2', 'produce'), ('Windeln Größe 4', null, 'drugstore'), ('Hack', '500 g', 'meat'),
            ('Gurken', '2', 'produce') $$,
  'add_items parses, classifies, skips blanks and returns the existing row for a duplicate'
);
select is((select count(*)::int from public.items where household_id = (select id from hc) and name like 'Gurke%'), 1,
  'the duplicate was not inserted');
select is(
  (select store_id from public.add_items((select id from hc), array['Shampoo'], pg_temp.store((select id from hc), 'dm'))),
  pg_temp.store((select id from hc), 'dm'), 'add_items tags with the given store'
);
select throws_ok(
  $$ select public.add_items((select id from hd), array['Milch']) $$,
  '42501', 'not_a_member', 'add_items into another household is denied'
);

-- Category management.
create temp table baby as select * from public.create_category((select id from hc), 'Baby');
select is(
  (select array_agg(seed_key order by sort_order) from public.categories where household_id = (select id from hc)),
  array['produce', 'bakery', 'chilled', 'meat', 'pantry', 'sweets', 'drinks', 'frozen', 'household', 'drugstore', null, 'other'],
  'a new category goes before Sonstiges'
);
select is(
  (select count(*)::int from public.store_category_order where category_id = (select id from baby)), 3,
  'and into every store layout'
);
select is(
  (select array_agg(c.seed_key order by o.sort_order) from public.store_category_order o
   join public.categories c on c.id = o.category_id where o.store_id = pg_temp.store((select id from hc), 'dm')),
  array['drugstore', 'pantry', 'sweets', 'household', 'drinks', null, 'other', 'produce', 'bakery', 'chilled', 'meat', 'frozen'],
  'before Sonstiges in a store too, since Sonstiges is not last there'
);
select throws_ok(
  $$ select public.create_category((select id from hc), 'Baby') $$, '23505', null, 'category names are unique'
);
select throws_ok(
  $$ select public.reorder_categories((select id from hc), array[(select id from baby)]) $$,
  '22023', 'invalid_category_order', 'a reorder must name every category'
);
select lives_ok(
  $$ select public.reorder_categories((select id from hc),
       (select array_agg(id order by sort_order desc) from public.categories where household_id = (select id from hc))) $$,
  'a full reorder is accepted'
);
select is(
  (select seed_key from public.categories where household_id = (select id from hc) order by sort_order limit 1), 'other',
  'and applied'
);
update public.categories set name = 'Babysachen' where id = (select id from baby);
select is((select name from public.categories where id = (select id from baby)), 'Babysachen', 'members can rename');

-- Deleting a category moves its items without teaching, and hands over its dictionary terms.
insert into public.items (household_id, name, category_id) select id, 'Schnuller', (select id from baby) from hc;
update public.items set category_id = (select id from baby) where name = 'Windeln Größe 4';
select public.delete_category(pg_temp.cat((select id from hc), 'drugstore'), (select id from baby));
select is(
  (select count(*)::int from public.categories where household_id = (select id from hc) and seed_key = 'drugstore'), 0,
  'the category is gone'
);
select is(
  (select category_id from public.items where name = 'Shampoo'), (select id from baby),
  'its items moved to the chosen category'
);
select is(public.classify_item((select id from hc), 'Duschgel'), (select id from baby),
  'its dictionary terms now land in the chosen category');
select public.delete_category((select id from baby));
select is(pg_temp.seed_of(category_id), 'other', 'deleting without a target moves items to Sonstiges')
from public.items where name = 'Schnuller';
select is(
  (select count(*)::int from public.category_memory m where m.household_id = (select id from hc)
     and m.category_id = pg_temp.cat((select id from hc), 'other')), 0,
  'moves caused by a delete teach nothing'
);
select throws_ok(
  $$ select public.delete_category(pg_temp.cat((select id from hc), 'other')) $$,
  'P0001', 'fallback_category_required', 'Sonstiges cannot be deleted'
);

-- Store layouts.
select pg_temp.login('00000000-0000-0000-0000-0000000000d1');
select is(
  (select array_agg(c.seed_key order by o.sort_order) from public.store_category_order o
   join public.categories c on c.id = o.category_id where o.store_id = pg_temp.store((select id from hd), 'lidl')),
  array['bakery', 'produce', 'chilled', 'meat', 'pantry', 'sweets', 'drinks', 'frozen', 'household', 'drugstore', 'other'],
  'Lidl starts with the bake station, then produce'
);
select is(
  (select array_agg(c.seed_key order by o.sort_order) from public.store_category_order o
   join public.categories c on c.id = o.category_id
   where o.store_id = pg_temp.store((select id from hd), 'dm') and o.hidden),
  array['produce', 'bakery', 'chilled', 'meat', 'frozen'],
  'dm hides what a drugstore does not sell'
);
select pg_temp.login('00000000-0000-0000-0000-0000000000c1');
select lives_ok(
  $$ select public.set_store_layout(pg_temp.store((select id from hc), 'edeka'),
       (select array_agg(id order by name) from public.categories where household_id = (select id from hc)),
       array[pg_temp.cat((select id from hc), 'frozen')]) $$,
  'set_store_layout takes a full order and the hidden categories'
);
select is(
  (select array_agg(c.name order by o.sort_order) from public.store_category_order o
   join public.categories c on c.id = o.category_id
   where o.store_id = pg_temp.store((select id from hc), 'edeka')),
  (select array_agg(name order by name) from public.categories where household_id = (select id from hc)),
  'and stores the order'
);

select * from finish();
rollback;
