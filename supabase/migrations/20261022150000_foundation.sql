-- Households, membership, invites, categories, stores, items and their history.
-- Every household-owned row carries household_id so RLS and Realtime filters need no joins.

create extension if not exists pgcrypto with schema extensions;

-- Profiles -----------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 80),
  created_at timestamptz not null default now()
);

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(coalesce(new.email, ''), '@', 1)), 80)
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Households ---------------------------------------------------------------

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Unser Haushalt' check (char_length(name) between 1 and 80),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households (id) on delete cascade,
  -- A user belongs to at most one household; joining another one moves them.
  user_id uuid not null unique references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create function public.is_household_member(p_household uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.household_members
    where household_id = p_household and user_id = auth.uid()
  );
$$;

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days',
  revoked_at timestamptz
);

-- Categories and stores ----------------------------------------------------

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  -- Stable identity of a seeded category, independent of renames; 'other' is the fallback.
  seed_key text,
  sort_order integer not null,
  created_at timestamptz not null default now(),
  unique (household_id, name),
  unique (household_id, seed_key),
  unique (id, household_id)
);

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  seed_key text,
  sort_order integer not null,
  created_at timestamptz not null default now(),
  unique (household_id, name),
  unique (household_id, seed_key),
  unique (id, household_id)
);

create table public.store_category_order (
  household_id uuid not null references public.households (id) on delete cascade,
  store_id uuid not null,
  category_id uuid not null,
  sort_order integer not null,
  primary key (store_id, category_id),
  foreign key (store_id, household_id) references public.stores (id, household_id) on delete cascade,
  foreign key (category_id, household_id) references public.categories (id, household_id) on delete cascade
);

-- Items --------------------------------------------------------------------

create function public.normalize_item_name(p_name text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(
    replace(replace(replace(replace(lower(btrim(p_name)), 'ä', 'ae'), 'ö', 'oe'), 'ü', 'ue'), 'ß', 'ss'),
    '\s+', ' ', 'g'
  );
$$;

create table public.items (
  -- Clients generate ids so optimistic rows and server echoes reconcile by id.
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  normalized_name text not null default '',
  quantity text check (quantity is null or char_length(quantity) <= 40),
  category_id uuid not null,
  store_id uuid,
  status text not null default 'active' check (status in ('active', 'bought')),
  added_by uuid references auth.users (id) on delete set null default auth.uid(),
  bought_by uuid references auth.users (id) on delete set null,
  bought_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (category_id, household_id) references public.categories (id, household_id),
  foreign key (store_id, household_id) references public.stores (id, household_id) on delete set null (store_id)
);

create index items_household_status_idx on public.items (household_id, status);
create index items_household_normalized_idx on public.items (household_id, normalized_name);

-- Placeholder classifier: keyword suffix match onto seeded categories, else the fallback.
-- Job 2 replaces the body (learned memory, full dictionary); the signature is the stable hook
-- that the items trigger, the app, MCP and Siri all go through.
create function public.classify_item(p_household uuid, p_name text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_norm text := public.normalize_item_name(p_name);
  v_key text;
begin
  select k.seed_key into v_key
  from (values
    ('apfel', 'produce'), ('aepfel', 'produce'), ('banane', 'produce'), ('bananen', 'produce'),
    ('gurke', 'produce'), ('gurken', 'produce'), ('tomate', 'produce'), ('tomaten', 'produce'),
    ('salat', 'produce'), ('kartoffeln', 'produce'), ('zwiebeln', 'produce'), ('karotten', 'produce'),
    ('brot', 'bakery'), ('broetchen', 'bakery'), ('toast', 'bakery'), ('brezel', 'bakery'),
    ('milch', 'chilled'), ('joghurt', 'chilled'), ('butter', 'chilled'), ('kaese', 'chilled'),
    ('quark', 'chilled'), ('sahne', 'chilled'), ('eier', 'chilled'),
    ('wurst', 'meat'), ('schinken', 'meat'), ('hackfleisch', 'meat'), ('fleisch', 'meat'),
    ('haehnchen', 'meat'), ('lachs', 'meat'), ('fisch', 'meat'),
    ('nudeln', 'pantry'), ('reis', 'pantry'), ('mehl', 'pantry'), ('zucker', 'pantry'),
    ('oel', 'pantry'), ('dosentomaten', 'pantry'), ('kaffee', 'pantry'), ('tee', 'pantry'),
    ('schokolade', 'sweets'), ('chips', 'sweets'), ('kekse', 'sweets'), ('gummibaerchen', 'sweets'),
    ('wasser', 'drinks'), ('saft', 'drinks'), ('bier', 'drinks'), ('wein', 'drinks'), ('cola', 'drinks'),
    ('pizza', 'frozen'), ('eis', 'frozen'), ('tiefkuehlgemuese', 'frozen'),
    ('klopapier', 'household'), ('toilettenpapier', 'household'), ('kuechenrolle', 'household'),
    ('spuelmittel', 'household'), ('muellbeutel', 'household'), ('waschmittel', 'household'),
    ('windeln', 'drugstore'), ('feuchttuecher', 'drugstore'), ('shampoo', 'drugstore'),
    ('zahnpasta', 'drugstore'), ('duschgel', 'drugstore'), ('deo', 'drugstore')
  ) as k (keyword, seed_key)
  where v_norm = k.keyword or v_norm like '%' || k.keyword
  order by char_length(k.keyword) desc
  limit 1;

  return (
    select c.id from public.categories c
    where c.household_id = p_household and c.seed_key = coalesce(v_key, 'other')
  );
end $$;

create function public.items_before_write() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.name := btrim(new.name);
  new.quantity := nullif(btrim(new.quantity), '');
  new.normalized_name := public.normalize_item_name(new.name);
  if new.category_id is null then
    new.category_id := public.classify_item(new.household_id, new.name);
  end if;
  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
    new.added_by := old.added_by;
    new.updated_at := now();
  end if;
  if new.status = 'bought' and (tg_op = 'INSERT' or old.status is distinct from 'bought') then
    new.bought_at := now();
    new.bought_by := auth.uid();
  elsif new.status = 'active' then
    new.bought_at := null;
    new.bought_by := null;
  end if;
  return new;
end $$;

create trigger items_before_write
  before insert or update on public.items
  for each row execute function public.items_before_write();

-- Item history -------------------------------------------------------------

create table public.item_events (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.households (id) on delete cascade,
  -- No foreign key: history outlives deleted items.
  item_id uuid not null,
  action text not null check (action in ('added', 'bought', 'restored', 'edited', 'deleted')),
  item_name text not null,
  category_id uuid,
  actor uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create index item_events_household_idx on public.item_events (household_id, created_at desc);

create function public.items_log_event() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.items := case when tg_op = 'DELETE' then old else new end;
  v_action text;
begin
  -- A household delete cascades to its items; its history goes with it.
  if tg_op = 'DELETE' and not exists (select 1 from public.households where id = old.household_id) then
    return null;
  end if;
  v_action := case
    when tg_op = 'INSERT' then 'added'
    when tg_op = 'DELETE' then 'deleted'
    when new.status = 'bought' and old.status = 'active' then 'bought'
    when new.status = 'active' and old.status = 'bought' then 'restored'
    else 'edited'
  end;
  insert into public.item_events (household_id, item_id, action, item_name, category_id)
  values (v_row.household_id, v_row.id, v_action, v_row.name, v_row.category_id);
  return null;
end $$;

create trigger items_log_event
  after insert or update or delete on public.items
  for each row execute function public.items_log_event();

-- Household lifecycle RPCs -------------------------------------------------

create function public.seed_household(p_household uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.categories (household_id, name, seed_key, sort_order)
  values
    (p_household, 'Obst & Gemüse', 'produce', 10),
    (p_household, 'Brot & Backwaren', 'bakery', 20),
    (p_household, 'Kühlregal', 'chilled', 30),
    (p_household, 'Fleisch/Wurst/Fisch', 'meat', 40),
    (p_household, 'Vorrat & Konserven', 'pantry', 50),
    (p_household, 'Süßes & Snacks', 'sweets', 60),
    (p_household, 'Getränke', 'drinks', 70),
    (p_household, 'Tiefkühl', 'frozen', 80),
    (p_household, 'Haushalt', 'household', 90),
    (p_household, '👶 Drogerie', 'drugstore', 100),
    (p_household, 'Sonstiges', 'other', 1000);

  insert into public.stores (household_id, name, seed_key, sort_order)
  values
    (p_household, 'dm', 'dm', 10),
    (p_household, 'Lidl', 'lidl', 20),
    (p_household, 'Edeka', 'edeka', 30);

  -- Default each store to the route order; job 2 sets store-specific layouts.
  insert into public.store_category_order (household_id, store_id, category_id, sort_order)
  select p_household, s.id, c.id, c.sort_order
  from public.stores s cross join public.categories c
  where s.household_id = p_household and c.household_id = p_household;
end $$;

create function public.leave_current_household() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
begin
  delete from public.household_members where user_id = auth.uid()
  returning household_id into v_household;
  if v_household is not null
     and not exists (select 1 from public.household_members where household_id = v_household) then
    delete from public.households where id = v_household;
  end if;
end $$;

create function public.create_household(p_name text default 'Unser Haushalt') returns public.households
language plpgsql security definer set search_path = '' as $$
declare
  v_household public.households;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if exists (select 1 from public.household_members where user_id = auth.uid()) then
    raise exception 'already_in_household' using errcode = 'P0001';
  end if;
  insert into public.households (name, created_by)
  values (coalesce(nullif(btrim(p_name), ''), 'Unser Haushalt'), auth.uid())
  returning * into v_household;
  insert into public.household_members (household_id, user_id, role)
  values (v_household.id, auth.uid(), 'owner');
  perform public.seed_household(v_household.id);
  return v_household;
end $$;

create function public.create_invite(p_household uuid) returns public.invites
language plpgsql security definer set search_path = '' as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
  v_invite public.invites;
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, 1 + get_byte(v_bytes, i) % 32, 1);
    end loop;
    exit when not exists (select 1 from public.invites where code = v_code);
  end loop;
  insert into public.invites (household_id, code, created_by)
  values (p_household, v_code, auth.uid())
  returning * into v_invite;
  return v_invite;
end $$;

create function public.join_household(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_household uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select household_id into v_household
  from public.invites
  where code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'))
    and revoked_at is null
    and expires_at > now();
  if v_household is null then
    raise exception 'invalid_invite' using errcode = 'P0001';
  end if;
  if public.is_household_member(v_household) then
    return v_household;
  end if;
  perform public.leave_current_household();
  insert into public.household_members (household_id, user_id, role)
  values (v_household, auth.uid(), 'member');
  return v_household;
end $$;

-- Execute grants: lifecycle RPCs for signed-in users only; internals for nobody.
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.create_household(text),
  public.create_invite(uuid),
  public.join_household(text),
  public.leave_current_household(),
  public.classify_item(uuid, text),
  public.normalize_item_name(text),
  public.is_household_member(uuid)
to authenticated;
revoke execute on function public.seed_household(uuid) from authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;

-- Row level security -------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.invites enable row level security;
alter table public.categories enable row level security;
alter table public.stores enable row level security;
alter table public.store_category_order enable row level security;
alter table public.items enable row level security;
alter table public.item_events enable row level security;

create policy profiles_select on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.household_members theirs
      where theirs.user_id = profiles.id and public.is_household_member(theirs.household_id)
    )
  );
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy households_select on public.households for select to authenticated
  using (public.is_household_member(id));
create policy households_update on public.households for update to authenticated
  using (public.is_household_member(id)) with check (public.is_household_member(id));

create policy household_members_select on public.household_members for select to authenticated
  using (public.is_household_member(household_id));

create policy invites_select on public.invites for select to authenticated
  using (public.is_household_member(household_id));
create policy invites_revoke on public.invites for update to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));

-- Household-owned data: full access for members, nothing for anyone else.
create policy categories_member on public.categories for all to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy stores_member on public.stores for all to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy store_category_order_member on public.store_category_order for all to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));
create policy items_member on public.items for all to authenticated
  using (public.is_household_member(household_id)) with check (public.is_household_member(household_id));

create policy item_events_select on public.item_events for select to authenticated
  using (public.is_household_member(household_id));

-- The fallback category must always exist: the classifier and deletions land there.
create function public.categories_keep_fallback() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.seed_key = 'other' and exists (select 1 from public.households where id = old.household_id) then
    raise exception 'fallback_category_required' using errcode = 'P0001';
  end if;
  return old;
end $$;

create trigger categories_keep_fallback
  before delete on public.categories
  for each row execute function public.categories_keep_fallback();

-- Table privileges: anon gets nothing; history and membership change only through RPCs.
revoke all on all tables in schema public from anon;
revoke insert, update, delete on public.item_events, public.household_members, public.households, public.invites, public.profiles from authenticated;
grant update (name) on public.households to authenticated;
grant update (revoked_at) on public.invites to authenticated;
grant update (display_name) on public.profiles to authenticated;

-- Realtime -----------------------------------------------------------------

alter publication supabase_realtime add table
  public.items, public.categories, public.stores, public.store_category_order, public.households;
