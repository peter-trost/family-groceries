begin;
select plan(12);

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000e1', 'erik@example.com');
select pg_temp.login('00000000-0000-0000-0000-0000000000e1');
create temp table he as select id from public.create_household('Erik');
grant select on he to authenticated;

-- A number in the name makes a different item; case, umlauts and plurals do not.
select isnt(public.item_name_key('Windeln Größe 4'), public.item_name_key('Windeln Größe 5'), 'Windeln Größe 4 and 5 differ');
select isnt(public.item_name_key('Mehl Typ 405'), public.item_name_key('Mehl Typ 550'), 'Mehl Typ 405 and 550 differ');
select isnt(public.item_name_key('Milch 1,5 %'), public.item_name_key('Milch 3,8 %'), 'Milch 1,5 % and 3,8 % differ');
select is(public.item_name_key('Milch 1,5 %'), public.item_name_key('milch 1.5%'), 'Milch 1,5 % and milch 1.5% match');
select is(public.item_name_key('Gurken'), public.item_name_key('Gurke'), 'Gurken and Gurke match');
select is(public.item_name_key('Äpfel'), public.item_name_key('aepfel'), 'Äpfel and aepfel match');
select is(public.item_name_key('Windeln Größe 4'), public.item_name_key('windeln grösse 4'), 'case and ß/ss match');
-- The classifier memory keeps folding sizes together.
select is(public.item_key('Windeln Größe 4'), public.item_key('Windeln Größe 5'), 'item_key still folds sizes for the memory');

-- add_items: both sizes land, a repeat of one does not.
select is(
  (select count(*)::int from public.add_items((select id from he), array['Windeln Größe 4', 'Windeln Größe 5', 'Mehl Typ 405', 'Mehl Typ 550'])),
  4, 'add_items returns a row for each'
);
select is(
  (select count(*)::int from public.items where household_id = (select id from he) and status = 'active'),
  4, 'two sizes and two types are four items'
);
select is(
  (select name from public.add_items((select id from he), array['windeln größe 5'])),
  'Windeln Größe 5', 'a repeat of one size returns that row'
);
select is(
  (select name from public.add_items((select id from he), array['2 Gurken']) union all
   select name from public.add_items((select id from he), array['Gurke']) limit 1 offset 1),
  'Gurken', 'Gurke after 2 Gurken is still the same item'
);

select * from finish();
rollback;
