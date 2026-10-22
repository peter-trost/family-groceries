-- Display names from Google and Apple. Google puts the name into the user
-- metadata at sign-up (`full_name`, `name`). Apple sends it once, only to the
-- native app, which stores it with `updateUser` after the user row exists.

create function public.default_display_name(meta jsonb, email text) returns text
language sql immutable set search_path = '' as $$
  select left(coalesce(
    nullif(meta ->> 'display_name', ''),
    nullif(meta ->> 'full_name', ''),
    nullif(meta ->> 'name', ''),
    split_part(coalesce(email, ''), '@', 1)
  ), 80)
$$;

revoke execute on function public.default_display_name(jsonb, text) from public, anon, authenticated;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, public.default_display_name(new.raw_user_meta_data, new.email))
  on conflict (id) do nothing;
  return new;
end $$;

-- A later name (Apple's first sign-in, a linked Google identity) replaces the
-- derived one, but never a name the user chose.
create function public.handle_user_metadata_update() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles
  set display_name = public.default_display_name(new.raw_user_meta_data, new.email)
  where id = new.id
    and display_name = public.default_display_name(old.raw_user_meta_data, old.email);
  return new;
end $$;

create trigger on_auth_user_metadata_updated
  after update of raw_user_meta_data, email on auth.users
  for each row
  when (old.raw_user_meta_data is distinct from new.raw_user_meta_data or old.email is distinct from new.email)
  execute function public.handle_user_metadata_update();
