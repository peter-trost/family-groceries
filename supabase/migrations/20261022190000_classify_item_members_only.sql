-- classify_item revealed another household's category ids to any signed-in
-- caller who knew that household's id (review 0 of job 1).

create or replace function public.classify_item(p_household uuid, p_name text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_norm text := public.normalize_item_name(p_name);
  v_key text;
begin
  -- Signed-in callers may classify only for their own household; the result
  -- names that household's category ids. Service role and the database
  -- itself (no auth.uid()) are trusted server paths.
  if auth.uid() is not null and not public.is_household_member(p_household) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
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
