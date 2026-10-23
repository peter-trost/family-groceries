-- Job 2: the classifier (learned memory, then the German dictionary, then the
-- fallback), item->store memory, category management and store layouts.

-- Item keys ----------------------------------------------------------------

-- One German word reduced to a form shared by its singular and common plurals:
-- Gurke/Gurken, Zwiebel/Zwiebeln, Brot/Brote, Joghurt/Joghurts, Kekse/Keks.
-- -er plurals (Eier, Kräuter) are not reduced; the dictionary lists both.
-- -eis/-ais keep their s, so Reis, Eis and Mais stay compound heads
-- (Milchreis, Vanilleeis, Dosenmais).
create function public.stem_word(p_word text) returns text
language plpgsql immutable set search_path = '' as $$
declare
  v text := p_word;
begin
  if char_length(v) >= 5 and v ~ '[elr]n$' then
    v := left(v, -1);
  end if;
  if char_length(v) >= 4 and v ~ 'e$' then
    v := left(v, -1);
  end if;
  if char_length(v) >= 5 and v ~ '[^su]s$' and v !~ '[ae]is$' then
    v := left(v, -1);
  end if;
  return v;
end $$;

-- The identity of an item for the classifier and both memories: lowercase,
-- umlauts and accents folded (ä, ae -> a), ß -> ss, quantities and units
-- dropped, punctuation to spaces, every word stemmed.
-- "2 kg Äpfel" and "Aepfel" both give "apfel"; "Bio-Vollmilch 3,5%" gives "bio vollmilch".
create function public.item_key(p_name text) returns text
language plpgsql immutable set search_path = '' as $$
declare
  v text := lower(coalesce(p_name, ''));
begin
  v := replace(replace(replace(replace(v, 'ä', 'a'), 'ö', 'o'), 'ü', 'u'), 'ß', 'ss');
  v := translate(v, 'àáâãåçèéêëìíîïñòóôõùúûýÿ', 'aaaaaceeeeiiiinooooouuuyy');
  v := replace(replace(replace(v, 'ae', 'a'), 'oe', 'o'), 'ue', 'u');
  v := regexp_replace(
    v,
    '(^|[^a-z0-9])[0-9]+([.,][0-9]+)?\s*(x|kg|gr|g|ml|l|stk|stuck|pck|packungen|packung|dosen|dose|flaschen|flasche|bund|becher|glaser|glas|tuten|tute|beutel|netz|kisten|kiste|kasten|pfund|liter|kilo|gramm|rollen|rolle|tafeln|tafel|stangen|stange|%)?(?![a-z])',
    ' ', 'g'
  );
  v := regexp_replace(v, '[^a-z]+', ' ', 'g');
  return coalesce(
    (select string_agg(public.stem_word(w), ' ' order by ord)
     from unnest(string_to_array(btrim(v), ' ')) with ordinality as t (w, ord)
     where w <> ''),
    ''
  );
end $$;

-- Name and quantity from a typed line, the same rules as the app's parseEntry
-- (app/lib/list/entry.dart): "2 Gurken", "3x Joghurt", "Hack 500 g".
-- A bare trailing number stays in the name ("Windeln Größe 4").
create function public.parse_entry(p_input text, out name text, out quantity text)
language plpgsql immutable set search_path = '' as $$
declare
  v_units constant text :=
    'x|kg|g|gr|l|ml|stk|stück|pck|packung|packungen|dose|dosen|flasche|flaschen|bund|becher|glas|gläser|tüte|tüten|beutel|netz|kiste|kisten|kasten|kästen|pfund|liter|kilo|gramm|rolle|rollen|tafel|tafeln|stange|stangen';
  v_text text := regexp_replace(btrim(coalesce(p_input, '')), '\s+', ' ', 'g');
  v_match text[];
begin
  v_match := regexp_match(v_text, '^(\d+(?:[.,]\d+)?)(?:\s*(' || v_units || ')\.?)?\s+(.+)$', 'i');
  if v_match is not null then
    name := v_match[3];
    quantity := case when v_match[2] is null or lower(v_match[2]) = 'x' then v_match[1]
                     else v_match[1] || ' ' || v_match[2] end;
    return;
  end if;
  v_match := regexp_match(v_text, '^(.+)\s+(\d+(?:[.,]\d+)?)\s*(' || v_units || ')\.?$', 'i');
  if v_match is not null then
    name := v_match[1];
    quantity := case when lower(v_match[3]) = 'x' then v_match[2] else v_match[2] || ' ' || v_match[3] end;
    return;
  end if;
  name := v_text;
  quantity := null;
end $$;

-- Seed dictionary ----------------------------------------------------------

-- Generated from supabase/classifier/dictionary.tsv (see its README); global,
-- read-only for clients.
create table public.classifier_terms (
  term text primary key check (term ~ '^[a-zäöüß]+( [a-zäöüß]+)*$'),
  category text not null check (category in (
    'produce', 'bakery', 'chilled', 'meat', 'pantry', 'sweets', 'drinks', 'frozen', 'household', 'drugstore'
  )),
  key text generated always as (public.item_key(term)) stored
);

create index classifier_terms_key_idx on public.classifier_terms (key);

-- The seed category for a key, by the first rule that matches:
-- 1. a dictionary phrase found in it ("rote bete");
-- 2. the whole key is a term ("tiefkühlbeutel");
-- 3. a frozen marker: the word "TK", or a word starting with tiefkühl,
--    tiefgekühlt or gefroren, so TK-Spinat is frozen, not produce;
-- 4. per word, the longest term the word ends with (compounds: Vollmilch ->
--    milch);
-- 5. the longest term of 4+ letters a word starts with.
-- Ties go to the later word, the head of a German noun phrase. Terms under
-- 3 letters match only whole words.
create function public.dictionary_category(p_key text) returns text
language sql stable set search_path = '' as $$
  with words as (
    select w, ord from unnest(string_to_array(p_key, ' ')) with ordinality as t (w, ord) where w <> ''
  ),
  hits as (
    select d.category, 5 as tier, char_length(d.key) as len, 0::bigint as ord
    from public.classifier_terms d
    where d.key like '% %' and ' ' || p_key || ' ' like '% ' || d.key || ' %'
    union all
    select d.category, 4, char_length(d.key), 0
    from public.classifier_terms d
    where d.key = p_key
    union all
    select 'frozen', 3, 0, w.ord
    from words w
    where w.w = 'tk' or w.w like 'tiefkuhl%' or w.w like 'tiefgekuhl%' or w.w like 'gefror%'
    union all
    select d.category, 2, char_length(d.key), w.ord
    from words w join public.classifier_terms d
      on d.key not like '% %'
     and (w.w = d.key or (char_length(d.key) >= 3 and w.w like '%' || d.key))
    union all
    select d.category, 1, char_length(d.key), w.ord
    from words w join public.classifier_terms d
      on d.key not like '% %' and char_length(d.key) >= 4 and w.w like d.key || '%'
  )
  select category from hits order by tier desc, len desc, ord desc, category limit 1;
$$;

-- Learned memories ---------------------------------------------------------

-- A deleted category hands its seed identity to the category its items moved
-- to, so dictionary hits for it keep landing somewhere sensible.
alter table public.categories add column absorbed_seed_keys text[] not null default '{}';

-- Corrections per item key and category; the latest correction wins.
create table public.category_memory (
  household_id uuid not null references public.households (id) on delete cascade,
  item_key text not null check (item_key <> ''),
  category_id uuid not null,
  corrections integer not null default 1,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (household_id, item_key, category_id),
  foreign key (category_id, household_id) references public.categories (id, household_id) on delete cascade
);

-- Where an item key was tagged or bought; the latest wins.
create table public.item_store_memory (
  household_id uuid not null references public.households (id) on delete cascade,
  item_key text not null check (item_key <> ''),
  store_id uuid not null,
  times integer not null default 1,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (household_id, item_key, store_id),
  foreign key (store_id, household_id) references public.stores (id, household_id) on delete cascade
);

-- Classifier ---------------------------------------------------------------

-- The one classifier: household memory, then the dictionary, then the
-- fallback category. The items trigger, add_items, MCP and Siri all use it.
create or replace function public.classify_item(p_household uuid, p_name text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_key text := public.item_key(p_name);
  v_learned uuid;
  v_seed text;
begin
  -- Signed-in callers may classify only for their own household; service
  -- role and the database itself (no auth.uid()) are trusted server paths.
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  select m.category_id into v_learned
  from public.category_memory m
  where m.household_id = p_household and m.item_key = v_key
  order by m.updated_at desc, m.corrections desc
  limit 1;
  if v_learned is not null then
    return v_learned;
  end if;

  v_seed := public.dictionary_category(v_key);
  return coalesce(
    (select c.id from public.categories c
     where c.household_id = p_household and v_seed is not null
       and (c.seed_key = v_seed or v_seed = any (c.absorbed_seed_keys))
     order by c.seed_key = v_seed desc
     limit 1),
    (select c.id from public.categories c where c.household_id = p_household and c.seed_key = 'other')
  );
end $$;

-- The store an item is usually bought at, or null (any supermarket).
create function public.suggest_store(p_household uuid, p_name text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  return (
    select m.store_id from public.item_store_memory m
    where m.household_id = p_household and m.item_key = public.item_key(p_name)
    order by m.updated_at desc
    limit 1
  );
end $$;

-- New items: classify when no category is given; take the remembered store
-- when none is given.
create or replace function public.items_before_write() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.name := btrim(new.name);
  new.quantity := nullif(btrim(new.quantity), '');
  new.normalized_name := public.normalize_item_name(new.name);
  if new.category_id is null then
    new.category_id := public.classify_item(new.household_id, new.name);
  end if;
  if tg_op = 'INSERT' and new.store_id is null then
    new.store_id := public.suggest_store(new.household_id, new.name);
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

-- Learning: a category change is a correction; a store change is a tag (null
-- clears the memory: "any supermarket"); a tick of a tagged item counts too.
-- Bulk moves (deleting a category) switch learning off for their transaction.
create function public.items_learn() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_key text := public.item_key(new.name);
begin
  if v_key = '' or coalesce(current_setting('family_groceries.learning', true), '') = 'off' then
    return null;
  end if;
  if new.category_id is distinct from old.category_id then
    insert into public.category_memory as m (household_id, item_key, category_id)
    values (new.household_id, v_key, new.category_id)
    on conflict (household_id, item_key, category_id)
      do update set corrections = m.corrections + 1, updated_at = clock_timestamp();
  end if;
  if new.store_id is distinct from old.store_id and new.store_id is null then
    delete from public.item_store_memory where household_id = new.household_id and item_key = v_key;
  elsif new.store_id is distinct from old.store_id
     or (new.store_id is not null and new.status = 'bought' and old.status = 'active') then
    insert into public.item_store_memory as m (household_id, item_key, store_id)
    values (new.household_id, v_key, new.store_id)
    on conflict (household_id, item_key, store_id)
      do update set times = m.times + 1, updated_at = clock_timestamp();
  end if;
  return null;
end $$;

create trigger items_learn
  after update of category_id, store_id, status on public.items
  for each row execute function public.items_learn();

-- Adding items -------------------------------------------------------------

-- The shared add path for MCP and Siri. Each entry may carry a quantity. An
-- entry whose item is already on the list returns that row instead.
create function public.add_items(p_household uuid, p_names text[], p_store uuid default null)
returns setof public.items
language plpgsql set search_path = '' as $$
declare
  v_raw text;
  v_entry record;
  v_row public.items;
begin
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  foreach v_raw in array coalesce(p_names, '{}') loop
    v_entry := public.parse_entry(v_raw);
    continue when v_entry.name = '';
    select * into v_row from public.items i
    where i.household_id = p_household and i.status = 'active'
      and public.item_key(i.name) = public.item_key(v_entry.name)
    order by i.created_at
    limit 1;
    if v_row.id is null then
      insert into public.items (household_id, name, quantity, store_id)
      values (p_household, v_entry.name, v_entry.quantity, p_store)
      returning * into v_row;
    end if;
    return next v_row;
    v_row := null;
  end loop;
end $$;

-- Category management ------------------------------------------------------

-- Raises unless p_ids is exactly the household's categories, each once.
create function public.assert_category_permutation(p_household uuid, p_ids uuid[]) returns void
language plpgsql stable set search_path = '' as $$
begin
  if cardinality(p_ids) is distinct from (select count(distinct x) from unnest(p_ids) as x)
     or exists (
       (select id from public.categories where household_id = p_household)
       except all (select unnest(p_ids))
     )
     or exists (
       (select unnest(p_ids))
       except all (select id from public.categories where household_id = p_household)
     ) then
    raise exception 'invalid_category_order' using errcode = '22023';
  end if;
end $$;

-- Sets the route order to p_ids (all of the household's categories).
create function public.reorder_categories(p_household uuid, p_ids uuid[]) returns void
language plpgsql set search_path = '' as $$
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  perform public.assert_category_permutation(p_household, p_ids);
  update public.categories c set sort_order = t.ord * 10
  from unnest(p_ids) with ordinality as t (id, ord)
  where c.id = t.id and c.sort_order is distinct from t.ord * 10;
end $$;

-- Sets a store's walking order to p_categories (all of the household's
-- categories); p_hidden are the ones the store does not carry.
create function public.set_store_layout(p_store uuid, p_categories uuid[], p_hidden uuid[] default '{}')
returns void
language plpgsql set search_path = '' as $$
declare
  v_household uuid := (select household_id from public.stores where id = p_store);
begin
  if v_household is null or not public.is_household_member(v_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  perform public.assert_category_permutation(v_household, p_categories);
  insert into public.store_category_order as o (household_id, store_id, category_id, sort_order, hidden)
  select v_household, p_store, t.id, t.ord * 10, t.id = any (coalesce(p_hidden, '{}'))
  from unnest(p_categories) with ordinality as t (id, ord)
  on conflict (store_id, category_id) do update
    set sort_order = excluded.sort_order, hidden = excluded.hidden
    where (o.sort_order, o.hidden) is distinct from (excluded.sort_order, excluded.hidden);
end $$;

-- A new category goes before the fallback when the fallback is last, else at
-- the end, in the route and in every store.
create function public.create_category(p_household uuid, p_name text) returns public.categories
language plpgsql set search_path = '' as $$
declare
  v_category public.categories;
  v_ids uuid[];
  v_store record;
begin
  if not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  insert into public.categories (household_id, name, sort_order)
  values (p_household, btrim(p_name), 0)
  returning * into v_category;

  select array_agg(id order by sort_order, name) into v_ids
  from public.categories where household_id = p_household and id <> v_category.id;
  perform public.reorder_categories(p_household, public.insert_before_fallback(p_household, v_ids, v_category.id));

  for v_store in
    select s.id, coalesce(array_agg(o.category_id order by o.sort_order) filter (where o.category_id is not null), '{}') as ids,
           coalesce(array_agg(o.category_id) filter (where o.hidden), '{}') as hidden
    from public.stores s left join public.store_category_order o on o.store_id = s.id
    where s.household_id = p_household
    group by s.id
  loop
    perform public.set_store_layout(
      v_store.id, public.insert_before_fallback(p_household, v_store.ids, v_category.id, v_store.hidden), v_store.hidden
    );
  end loop;
  return (select c from public.categories c where c.id = v_category.id);
end $$;

-- p_ids with p_new placed after the last category not in p_hidden, or just
-- before it when that is the fallback (which then stays last).
create function public.insert_before_fallback(p_household uuid, p_ids uuid[], p_new uuid, p_hidden uuid[] default '{}')
returns uuid[]
language plpgsql stable set search_path = '' as $$
declare
  v_fallback uuid := (select id from public.categories where household_id = p_household and seed_key = 'other');
  v_at integer := coalesce(
    (select max(t.ord) from unnest(p_ids) with ordinality as t (id, ord) where t.id <> all (p_hidden)), 0
  );
begin
  if v_at > 0 and p_ids[v_at] = v_fallback then
    v_at := v_at - 1;
  end if;
  return coalesce(p_ids[1:v_at], '{}') || p_new || coalesce(p_ids[v_at + 1:], '{}');
end $$;

-- Deletes a category, moving its items (active and bought) to p_reassign_to,
-- by default the fallback. The move is not a correction, so it teaches
-- nothing; the deleted category's memories go with it, and its seed identity
-- passes to the target.
create function public.delete_category(p_category uuid, p_reassign_to uuid default null) returns void
language plpgsql set search_path = '' as $$
declare
  v_deleted public.categories := (select c from public.categories c where c.id = p_category);
  v_target uuid;
begin
  if v_deleted.id is null or not public.is_household_member(v_deleted.household_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if v_deleted.seed_key = 'other' then
    raise exception 'fallback_category_required' using errcode = 'P0001';
  end if;
  v_target := coalesce(
    p_reassign_to,
    (select id from public.categories where household_id = v_deleted.household_id and seed_key = 'other')
  );
  if v_target = p_category
     or not exists (select 1 from public.categories where id = v_target and household_id = v_deleted.household_id) then
    raise exception 'invalid_reassign_target' using errcode = '22023';
  end if;

  perform set_config('family_groceries.learning', 'off', true);
  update public.items set category_id = v_target where category_id = p_category;
  perform set_config('family_groceries.learning', 'on', true);

  update public.categories
  set absorbed_seed_keys = absorbed_seed_keys
    || coalesce(array[v_deleted.seed_key], '{}') || v_deleted.absorbed_seed_keys
  where id = v_target;
  delete from public.categories where id = p_category;
end $$;

-- Store layouts ------------------------------------------------------------

alter table public.store_category_order add column hidden boolean not null default false;

-- Default walking orders, researched in docs/STORE_LAYOUTS.md. Categories a
-- layout does not list keep their route order after the listed ones.
create function public.apply_default_store_layouts(p_household uuid) returns void
language plpgsql set search_path = '' as $$
begin
  delete from public.store_category_order where household_id = p_household;
  insert into public.store_category_order (household_id, store_id, category_id, sort_order, hidden)
  select p_household, s.id, c.id,
         row_number() over (partition by s.id order by coalesce(l.ord, 1000), c.sort_order) * 10,
         coalesce(l.hidden, false)
  from public.stores s
  cross join public.categories c
  left join (values
    -- STORE_LAYOUTS_BEGIN
    ('lidl', 'bakery', 1, false), ('lidl', 'produce', 2, false), ('lidl', 'chilled', 3, false),
    ('lidl', 'meat', 4, false), ('lidl', 'pantry', 5, false), ('lidl', 'sweets', 6, false),
    ('lidl', 'drinks', 7, false), ('lidl', 'frozen', 8, false), ('lidl', 'household', 9, false),
    ('lidl', 'drugstore', 10, false), ('lidl', 'other', 11, false),
    ('edeka', 'produce', 1, false), ('edeka', 'bakery', 2, false), ('edeka', 'meat', 3, false),
    ('edeka', 'chilled', 4, false), ('edeka', 'pantry', 5, false), ('edeka', 'sweets', 6, false),
    ('edeka', 'frozen', 7, false), ('edeka', 'drinks', 8, false), ('edeka', 'household', 9, false),
    ('edeka', 'drugstore', 10, false), ('edeka', 'other', 11, false),
    ('dm', 'drugstore', 1, false), ('dm', 'pantry', 2, false), ('dm', 'sweets', 3, false),
    ('dm', 'household', 4, false), ('dm', 'drinks', 5, false), ('dm', 'other', 6, false),
    ('dm', 'produce', 7, true), ('dm', 'bakery', 8, true), ('dm', 'chilled', 9, true),
    ('dm', 'meat', 10, true), ('dm', 'frozen', 11, true)
    -- STORE_LAYOUTS_END
  ) as l (store_key, category_key, ord, hidden)
    on l.store_key = s.seed_key and l.category_key = c.seed_key
  where s.household_id = p_household and c.household_id = p_household;
end $$;

create or replace function public.seed_household(p_household uuid) returns void
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

  perform public.apply_default_store_layouts(p_household);
end $$;

-- Households created before this migration get the researched layouts too.
select public.apply_default_store_layouts(id) from public.households;

-- Grants and row level security --------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.item_key(text),
  public.parse_entry(text),
  public.classify_item(uuid, text),
  public.suggest_store(uuid, text),
  public.add_items(uuid, text[], uuid),
  public.reorder_categories(uuid, uuid[]),
  public.set_store_layout(uuid, uuid[], uuid[]),
  public.create_category(uuid, text),
  public.delete_category(uuid, uuid)
to authenticated;
revoke execute on function
  public.seed_household(uuid),
  public.apply_default_store_layouts(uuid)
from authenticated;

alter table public.classifier_terms enable row level security;
alter table public.category_memory enable row level security;
alter table public.item_store_memory enable row level security;

create policy classifier_terms_read on public.classifier_terms for select to authenticated using (true);
create policy category_memory_member on public.category_memory for select to authenticated
  using (public.is_household_member(household_id));
create policy item_store_memory_member on public.item_store_memory for select to authenticated
  using (public.is_household_member(household_id));

-- Memories change only through the learning trigger.
revoke all on public.classifier_terms, public.category_memory, public.item_store_memory from anon;
revoke insert, update, delete on public.classifier_terms, public.category_memory, public.item_store_memory
  from authenticated;
