begin;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'peter@example.com', '{"full_name": "Peter Trost", "name": "Peter Trost", "iss": "https://accounts.google.com"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'x7k2p9@privaterelay.appleid.com', '{"iss": "https://appleid.apple.com"}'),
  ('00000000-0000-0000-0000-0000000000a3', 'lea@example.com', '{}');

select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000000a1'),
  'Peter Trost', 'Google sign-up: the profile takes full_name from the provider metadata'
);
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000000a2'),
  'x7k2p9', 'Apple sign-up: no name in the ID token, so the email local part for now'
);

update auth.users set raw_user_meta_data = raw_user_meta_data || '{"full_name": "Lea Trost", "given_name": "Lea", "family_name": "Trost"}'
where id = '00000000-0000-0000-0000-0000000000a2';
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000000a2'),
  'Lea Trost', 'Apple first sign-in: the name the app stores replaces the derived one'
);

update public.profiles set display_name = 'Lea' where id = '00000000-0000-0000-0000-0000000000a3';
update auth.users set raw_user_meta_data = '{"full_name": "Lea Trost"}'
where id = '00000000-0000-0000-0000-0000000000a3';
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000000a3'),
  'Lea', 'a name the user chose survives a linked identity''s metadata'
);

update auth.users set raw_user_meta_data = '{"full_name": "Someone Else"}'
where id = '00000000-0000-0000-0000-0000000000a1';
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000000a1'),
  'Someone Else', 'a provider name follows provider updates while the user kept it'
);

set local role authenticated;
select throws_ok(
  $$ select public.default_display_name('{}', 'a@b.c') $$,
  '42501', null, 'clients cannot call the helper'
);

select * from finish();
rollback;
