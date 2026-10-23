-- Duplicate check by name, numbers included. item_key folds case, umlauts,
-- plurals and drops every number, which is right for the classifier memory
-- ("Windeln Größe 4" and "Größe 5" share a category) but wrong for "is this
-- already on the list": a different size or type is a different item.
-- Names reaching here carry no quantity (add_items parses it off first), so
-- the numbers left belong to the name.
create function public.item_name_key(p_name text) returns text
language sql immutable set search_path = '' as $$
  select public.item_key(p_name) || coalesce(
    ' #' || (
      select string_agg(replace(m[1], ',', '.'), ' ')
      from regexp_matches(coalesce(p_name, ''), '([0-9]+(?:[.,][0-9]+)?)', 'g') as m
    ),
    ''
  );
$$;

create or replace function public.add_items(p_household uuid, p_names text[], p_store uuid default null)
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
      and public.item_name_key(i.name) = public.item_name_key(v_entry.name)
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

revoke execute on function public.item_name_key(text) from public, anon;
grant execute on function public.item_name_key(text) to authenticated;
