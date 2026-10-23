-- Usuals and due items from the household's purchase history, for the add
-- field's suggestions (prefix) and the "Brauchen wir wieder?" row (due).
create function public.suggest_items(
  p_household uuid,
  p_prefix text default '',
  p_limit int default 5,
  p_now timestamptz default now()
) returns table (name text, quantity text, uses int, last_used timestamptz, due boolean)
language sql stable security invoker set search_path = '' as $$
  -- Every name is keyed once: item_name_key is too slow to call per pair. A
  -- year of history is enough for usuals and keeps the cost flat as it grows.
  with history as materialized (
    select e.id, e.item_id, e.action, e.item_name, e.created_at, public.item_name_key(e.item_name) as key
    from public.item_events e
    where public.is_household_member(p_household)
      and e.household_id = p_household
      and e.action in ('added', 'bought', 'restored')
      and e.created_at <= p_now
      and e.created_at > p_now - interval '1 year'
  ),
  rows as materialized (
    select i.id, i.status, i.quantity, coalesce(i.bought_at, i.updated_at) as at, public.item_name_key(i.name) as key
    from public.items i
    where i.household_id = p_household
      and (i.status = 'active' or i.updated_at > p_now - interval '1 year')
  ),
  -- A restore within 10 minutes of the tick is the snackbar's undo, not a purchase.
  -- After a tick, an item's next added/bought/restored event is its restore, if any.
  purchases as (
    select t.id, t.item_id
    from (
      select h.id, h.item_id, h.action, h.created_at,
        lead(h.action) over w as next_action,
        lead(h.created_at) over w as next_at
      from history h
      window w as (partition by h.item_id order by h.created_at, h.id)
    ) t
    where t.action = 'bought'
      and not coalesce(t.next_action = 'restored' and t.next_at <= t.created_at + interval '10 minutes', false)
  ),
  -- An item added and deleted without ever being bought was a typo, not a use.
  counted as materialized (
    select h.id, h.action, h.item_name, h.created_at, h.key
    from history h
    where h.key <> ''
      and ((h.action = 'bought' and h.id in (select p.id from purchases p))
        or (h.action = 'added' and (
              h.item_id in (select r.id from rows r)
              or h.item_id in (select p.item_id from purchases p))))
  ),
  days as (
    select
      c.key,
      (c.created_at at time zone 'Europe/Berlin')::date as day,
      max(c.created_at) as last_at,
      max(c.created_at) filter (where c.action = 'bought') as bought_at
    from counted c
    group by 1, 2
  ),
  keys as (
    select
      d.key,
      count(*)::int as uses,
      max(d.last_at) as last_used,
      sum(power(0.5, extract(epoch from p_now - d.last_at) / 86400 / 30)) as score,
      count(d.bought_at) as purchases,
      max(d.bought_at) as last_bought_at,
      greatest(
        (max(d.day) filter (where d.bought_at is not null) - min(d.day) filter (where d.bought_at is not null))::numeric
          / nullif(count(d.bought_at) - 1, 0),
        1
      ) as gap_days
    from days d
    group by d.key
  ),
  -- The prefix is matched here, once per name, not once per join pair.
  latest_name as materialized (
    select n.key, n.name,
      case
        when btrim(coalesce(p_prefix, '')) = '' then 0
        when starts_with(n.folded, public.normalize_item_name(p_prefix)) then 0
        when exists (
          select 1 from regexp_split_to_table(n.folded, '[ -]+') as w
          where starts_with(w, public.normalize_item_name(p_prefix))
        ) then 1
      end as prefix_rank
    from (
      select distinct on (c.key) c.key, c.item_name as name, public.normalize_item_name(c.item_name) as folded
      from counted c
      order by c.key, c.created_at desc, c.id desc
    ) n
  ),
  latest_quantity as (
    select distinct on (r.key) r.key, r.quantity
    from rows r
    order by r.key, r.at desc
  ),
  ranked as (
    select k.*, n.name, n.prefix_rank, q.quantity
    from keys k
    join latest_name n using (key)
    left join latest_quantity q using (key)
    where n.prefix_rank is not null
      and k.key not in (select r.key from rows r where r.status = 'active')
  )
  select
    r.name,
    r.quantity,
    r.uses,
    r.last_used,
    r.purchases >= 2
      and extract(epoch from p_now - r.last_bought_at) / 86400 between r.gap_days and 4 * r.gap_days
  from ranked r
  order by r.prefix_rank, r.score desc, r.last_used desc, r.name
  limit least(greatest(p_limit, 0), 200);
$$;

grant execute on function public.suggest_items(uuid, text, int, timestamptz) to authenticated;
