begin;
select plan(37);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bob@example.com');

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
create temp table ha as select id from public.create_household('Alice');
insert into public.items (household_id, name) select id, 'Milch' from ha;
create temp table inv as select * from public.create_invite((select id from ha));
-- Job 2: Alice's learned memories and catalog ids for the cross-household checks.
update public.items
set category_id = (select id from public.categories where household_id = (select id from ha) and seed_key = 'drinks'),
    store_id = (select id from public.stores where household_id = (select id from ha) and seed_key = 'lidl')
where household_id = (select id from ha);
create temp table alice_store as select id from public.stores where household_id = (select id from ha) and seed_key = 'lidl';
create temp table alice_category as
  select id from public.categories where household_id = (select id from ha) and seed_key = 'drinks';
-- Job 8: a bought and then deleted item stays in Alice's history as a suggestion.
insert into public.items (household_id, name) select id, 'Kaffee' from ha;
update public.items set status = 'bought' where household_id = (select id from ha) and name = 'Kaffee';
delete from public.items where household_id = (select id from ha) and name = 'Kaffee';

select pg_temp.login('00000000-0000-0000-0000-0000000000b1');
create temp table hb as select id from public.create_household('Bob');
insert into public.items (household_id, name) select id, 'Brot' from hb;
grant select on ha, hb, inv, alice_store, alice_category to authenticated, anon;

-- Bob is signed in from here on and must not see or touch Alice's household.
select is((select count(*)::int from public.households), 1, 'a user sees only their own household');
select is((select count(*)::int from public.items where household_id = (select id from ha)), 0,
  'items of another household are invisible');
select is((select count(*)::int from public.categories where household_id = (select id from ha)), 0,
  'categories of another household are invisible');
select is((select count(*)::int from public.stores where household_id = (select id from ha)), 0,
  'stores of another household are invisible');
select is((select count(*)::int from public.store_category_order where household_id = (select id from ha)), 0,
  'store orders of another household are invisible');
select is((select count(*)::int from public.household_members where household_id = (select id from ha)), 0,
  'members of another household are invisible');
select is((select count(*)::int from public.invites), 0, 'invites of another household are invisible');
select is((select count(*)::int from public.item_events where household_id = (select id from ha)), 0,
  'history of another household is invisible');
select is((select count(*)::int from public.profiles), 1, 'profiles outside the household are invisible');
select is((select count(*)::int from public.suggest_items((select id from ha), '', 200)), 0,
  'suggestions from another household''s history are empty');

select throws_ok(
  $$ insert into public.items (household_id, name) select id, 'Fremd' from ha $$,
  '42501', null, 'inserting into another household is denied'
);
update public.items set name = 'Gehackt' where household_id = (select id from ha);
delete from public.items where household_id = (select id from ha);
delete from public.categories where household_id = (select id from ha);
select throws_ok(
  $$ update public.items set household_id = (select id from ha) where name = 'Brot' $$,
  '42501', null, 'moving an item into another household is denied'
);
select throws_ok(
  $$ select public.create_invite((select id from ha)) $$,
  '42501', 'not_a_member', 'creating an invite for another household is denied'
);
select throws_ok(
  $$ insert into public.household_members (household_id, user_id) select id, '00000000-0000-0000-0000-0000000000b1' from ha $$,
  '42501', null, 'self-adding to a household without an invite is denied'
);
select throws_ok(
  $$ insert into public.item_events (household_id, item_id, action, item_name) select id, gen_random_uuid(), 'added', 'x' from hb $$,
  '42501', null, 'history is append-only through triggers'
);
select throws_ok(
  $$ select public.seed_household((select id from ha)) $$,
  '42501', null, 'seeding is internal'
);
select throws_ok(
  $$ select public.classify_item((select id from ha), 'Milch') $$,
  '42501', 'not_a_member', 'classifying for another household is denied (it would reveal its category ids)'
);
select is(
  (select seed_key from public.categories where id = public.classify_item((select id from hb), 'Milch')),
  'chilled', 'classifying for the own household works'
);

-- Job 2: learned memories and the catalog RPCs.
select is((select count(*)::int from public.category_memory), 0, 'category memories of another household are invisible');
select is((select count(*)::int from public.item_store_memory), 0, 'store memories of another household are invisible');
select throws_ok(
  $$ insert into public.category_memory (household_id, item_key, category_id) select id, 'x', (select id from alice_category) from ha $$,
  '42501', null, 'memories cannot be written directly'
);
select throws_ok($$ select public.suggest_store((select id from ha), 'Milch') $$, '42501', 'not_a_member',
  'suggest_store for another household is denied');
select throws_ok($$ select public.add_items((select id from ha), array['Milch']) $$, '42501', 'not_a_member',
  'add_items into another household is denied');
select throws_ok($$ select public.create_category((select id from ha), 'Fremd') $$, '42501', 'not_a_member',
  'creating a category in another household is denied');
select throws_ok($$ select public.reorder_categories((select id from ha), array[(select id from alice_category)]) $$,
  '42501', 'not_a_member', 'reordering another household''s categories is denied');
select throws_ok($$ select public.delete_category((select id from alice_category)) $$, '42501', 'not_a_member',
  'deleting another household''s category is denied');
select throws_ok(
  $$ select public.set_store_layout((select id from alice_store), array[(select id from alice_category)]) $$,
  '42501', 'not_a_member', 'changing another household''s store layout is denied'
);
update public.store_category_order set hidden = true where store_id = (select id from alice_store);

select pg_temp.login('00000000-0000-0000-0000-0000000000a1');
select results_eq(
  $$ select item_key from public.category_memory union all select item_key from public.item_store_memory $$,
  $$ values ('milch'), ('milch') $$,
  'Alice''s memories are intact'
);
select is((select count(*)::int from public.store_category_order where store_id = (select id from alice_store) and hidden), 0,
  'the other user''s layout update changed nothing');
select results_eq(
  $$ select name from public.items where household_id = (select id from ha) $$,
  $$ values ('Milch') $$,
  'the other user''s update and delete attempts changed nothing'
);
select is((select count(*)::int from public.categories where household_id = (select id from ha)), 11,
  'the other user''s category delete changed nothing');
select results_eq($$ select name from public.suggest_items((select id from ha), '', 200) $$, $$ values ('Kaffee') $$,
  'Alice gets her own suggestions');
select pg_temp.anon();
set local role postgres;
select throws_ok(
  $$ insert into public.items (household_id, name, category_id)
     select (select id from ha), 'Mix', c.id from public.categories c where c.household_id = (select id from hb) limit 1 $$,
  '23503', null, 'even a privileged writer cannot point an item at another household''s category'
);

select pg_temp.anon();
select throws_ok($$ select public.classify_item((select id from ha), 'Milch') $$, '42501', null,
  'anon cannot classify');
set local role postgres;
select isnt(public.classify_item((select id from ha), 'Milch'), null,
  'trusted server paths without a user (service role, triggers) still classify');
select pg_temp.anon();
select throws_ok($$ select count(*) from public.items $$, '42501', null, 'anon cannot read items');
select throws_ok($$ select public.create_household('x') $$, '42501', null, 'anon cannot call household RPCs');

select * from finish();
rollback;
