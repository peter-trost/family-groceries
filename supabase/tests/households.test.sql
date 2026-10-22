begin;
select plan(24);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'peter@example.com', '{"display_name": "Peter"}'),
  ('00000000-0000-0000-0000-00000000000b', 'lea@example.com', '{}');

select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  'Peter', 'profile takes display_name from signup metadata'
);
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000b'),
  'lea', 'profile falls back to the email local part'
);

select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select lives_ok($$ select public.create_household('Trost') $$, 'a signed-in user creates a household');
select throws_ok($$ select public.create_household('Zweiter') $$, 'P0001', 'already_in_household',
  'a user cannot create a second household');

create temp table h as select household_id as id from public.household_members
  where user_id = '00000000-0000-0000-0000-00000000000a';
grant select on h to authenticated;

select results_eq(
  $$ select name from public.categories where household_id = (select id from h) order by sort_order $$,
  $$ values ('Obst & Gemüse'), ('Brot & Backwaren'), ('Kühlregal'), ('Fleisch/Wurst/Fisch'),
            ('Vorrat & Konserven'), ('Süßes & Snacks'), ('Getränke'), ('Tiefkühl'), ('Haushalt'),
            ('👶 Drogerie'), ('Sonstiges') $$,
  'the ten route categories are seeded in order, fallback last'
);
select results_eq(
  $$ select name from public.stores where household_id = (select id from h) order by sort_order $$,
  $$ values ('dm'), ('Lidl'), ('Edeka') $$,
  'dm, Lidl and Edeka are seeded'
);
select is(
  (select count(*)::int from public.store_category_order where household_id = (select id from h)),
  33, 'every store gets an order for every category'
);

insert into public.items (household_id, name) select id, '  Vollmilch ' from h;
select is(
  (select c.seed_key from public.items i join public.categories c on c.id = i.category_id where i.name = 'Vollmilch'),
  'chilled', 'a new item is classified server-side (compound suffix match)'
);
select is(
  (select normalized_name from public.items where name = 'Vollmilch'), 'vollmilch',
  'the name is trimmed and the normalized name is stored'
);
insert into public.items (household_id, name) select id, 'Glühbirnen' from h;
select is(
  (select c.seed_key from public.items i join public.categories c on c.id = i.category_id where i.name = 'Glühbirnen'),
  'other', 'unknown items land in the fallback category'
);
select is(
  (select normalized_name from public.items where name = 'Glühbirnen'), 'gluehbirnen',
  'umlauts are normalized'
);

update public.items set status = 'bought' where name = 'Vollmilch';
select isnt((select bought_at from public.items where name = 'Vollmilch'), null, 'ticking stamps bought_at');
select is((select bought_by from public.items where name = 'Vollmilch'),
  '00000000-0000-0000-0000-00000000000a'::uuid, 'ticking records who bought it');
update public.items set status = 'active' where name = 'Vollmilch';
select is((select bought_at from public.items where name = 'Vollmilch'), null, 'undo clears bought_at');
delete from public.items where name = 'Glühbirnen';

select results_eq(
  $$ select action from public.item_events order by id $$,
  $$ values ('added'), ('added'), ('bought'), ('restored'), ('deleted') $$,
  'every item change is recorded in the history'
);

select throws_ok(
  $$ delete from public.categories where seed_key = 'other' $$,
  'P0001', 'fallback_category_required', 'the fallback category cannot be deleted'
);

create temp table inv as select * from public.create_invite((select id from h));
grant select on inv to authenticated;
select matches((select code from inv), '^[A-HJ-NP-Z2-9]{8}$', 'invite codes are 8 unambiguous characters');

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select throws_ok($$ select public.join_household('NOPE2345') $$, 'P0001', 'invalid_invite', 'an unknown code is rejected');
select lives_ok(
  format($$ select public.join_household(%L) $$, lower(substr((select code from inv), 1, 4)) || '-' || lower(substr((select code from inv), 5))),
  'a code joins case-insensitively and ignores separators'
);
select is(
  (select count(*)::int from public.items where household_id = (select id from h)), 1,
  'the joined member sees the household list'
);
select lives_ok(format($$ select public.join_household(%L) $$, (select code from inv)), 'joining twice is a no-op');
select is(
  (select count(*)::int from public.household_members where household_id = (select id from h)), 2,
  'the household has two members'
);

select pg_temp.logout();
update public.invites set expires_at = now() - interval '1 second';
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000c', 'late@example.com');
select pg_temp.login('00000000-0000-0000-0000-00000000000c');
select throws_ok(format($$ select public.join_household(%L) $$, (select code from inv)),
  'P0001', 'invalid_invite', 'an expired code is rejected');

select pg_temp.login('00000000-0000-0000-0000-00000000000b');
select public.leave_current_household();
select pg_temp.login('00000000-0000-0000-0000-00000000000a');
select public.leave_current_household();
select pg_temp.logout();
select is((select count(*)::int from public.households), 0, 'the last member leaving deletes the household');

select * from finish();
rollback;
