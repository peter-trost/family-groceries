-- Personal access tokens: bearer credentials for the MCP server and the Siri endpoint.
-- Only a SHA-256 hash is stored; the plaintext is returned once by create_personal_access_token.
-- A token acts as its creator, in the household it was created for, while they are still a member.

create table public.personal_access_tokens (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  -- The last four characters, so the settings list can tell tokens apart.
  token_hint text not null check (char_length(token_hint) = 4),
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);

create index personal_access_tokens_user_idx on public.personal_access_tokens (user_id, created_at desc);

alter table public.personal_access_tokens enable row level security;

-- Tokens are personal: members see and revoke only their own, and only in their household.
create policy personal_access_tokens_own on public.personal_access_tokens for select to authenticated
  using (public.is_household_member(household_id) and user_id = (select auth.uid()));
create policy personal_access_tokens_revoke on public.personal_access_tokens for update to authenticated
  using (public.is_household_member(household_id) and user_id = (select auth.uid()))
  with check (public.is_household_member(household_id) and user_id = (select auth.uid()));

revoke all on public.personal_access_tokens from anon, authenticated;
grant select (id, household_id, user_id, name, token_hint, created_at, last_used_at, revoked_at)
  on public.personal_access_tokens to authenticated;
grant update (revoked_at) on public.personal_access_tokens to authenticated;

-- Revocation is one-way.
create function public.personal_access_tokens_keep_revoked() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.revoked_at is not null then
    new.revoked_at := old.revoked_at;
  end if;
  return new;
end $$;

create trigger personal_access_tokens_keep_revoked
  before update on public.personal_access_tokens
  for each row execute function public.personal_access_tokens_keep_revoked();

create function public.create_personal_access_token(p_name text)
returns table (id uuid, name text, token text)
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
  v_token text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select m.household_id into v_household from public.household_members m where m.user_id = auth.uid();
  if v_household is null then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if (select count(*) from public.personal_access_tokens t
      where t.user_id = auth.uid() and t.revoked_at is null) >= 20 then
    raise exception 'too_many_tokens' using errcode = 'P0001';
  end if;
  -- 32 random bytes, base64url without padding: 43 characters after the prefix.
  v_token := 'fgp_' || rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  return query
  insert into public.personal_access_tokens as t (household_id, user_id, name, token_hash, token_hint)
  values (
    v_household,
    auth.uid(),
    coalesce(nullif(btrim(p_name), ''), 'Token'),
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    right(v_token, 4)
  )
  returning t.id, t.name, v_token;
end $$;

-- For edge functions: resolves a token hash to its user and household, or nothing when the
-- token is unknown, revoked, or its creator has left that household.
create function public.authenticate_personal_access_token(p_token_hash text)
returns table (user_id uuid, household_id uuid)
language sql security definer set search_path = '' as $$
  update public.personal_access_tokens t
  set last_used_at = now()
  from public.household_members m
  where t.token_hash = p_token_hash
    and t.revoked_at is null
    and m.user_id = t.user_id
    and m.household_id = t.household_id
  returning t.user_id, t.household_id;
$$;

revoke execute on function public.create_personal_access_token(text) from public, anon;
grant execute on function public.create_personal_access_token(text) to authenticated;
revoke execute on function public.authenticate_personal_access_token(text) from public, anon, authenticated;
grant execute on function public.authenticate_personal_access_token(text) to service_role;
revoke execute on function public.personal_access_tokens_keep_revoked() from public, anon, authenticated;
