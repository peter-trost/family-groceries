-- Usuals and due items from the household's purchase history, for the add
-- field's suggestions (prefix) and the "Brauchen wir wieder?" row (due).
create function public.suggest_items(
  p_household uuid,
  p_prefix text default '',
  p_limit int default 5,
  p_now timestamptz default now()
) returns table (name text, quantity text, uses int, last_used timestamptz, due boolean)
language sql stable security invoker set search_path = '' as $$
  with history as (
    select e.id, e.item_id, e.action, e.item_name, e.created_at
    from public.item_events e
    where public.is_household_member(p_household)
      and e.household_id = p_household
      and e.action in ('added', 'bought', 'restored')
      and e.created_at <= p_now
  ),
  -- A restore within 10 minutes of the tick is the snackbar's undo, not a purchase.
  purchases as (
    select b.id, b.item_id
    from history b
    where b.action = 'bought'
      and not exists (
        select 1 from history r
        where r.item_id = b.item_id
          and r.action = 'restored'
          and r.created_at between b.created_at and b.created_at + interval '10 minutes'
      )
  ),
  -- An item added and deleted without ever being bought was a typo, not a use.
  counted as (
    select h.id, h.action, h.item_name, h.created_at, public.item_name_key(h.item_name) as key
    from history h
    where (h.action = 'bought' and h.id in (select p.id from purchases p))
       or (h.action = 'added' and (
             exists (select 1 from public.items i where i.id = h.item_id)
             or h.item_id in (select p.item_id from purchases p)))
  ),
  days as (
    select
      c.key,
      (c.created_at at time zone 'Europe/Berlin')::date as day,
      max(c.created_at) as last_at,
      max(c.created_at) filter (where c.action = 'bought') as bought_at
    from counted c
    where c.key <> ''
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
  named as (
    select
      k.*,
      (select c.item_name from counted c where c.key = k.key order by c.created_at desc, c.id desc limit 1) as name
    from keys k
    where not exists (
      select 1 from public.items i
      where i.household_id = p_household and i.status = 'active' and public.item_name_key(i.name) = k.key
    )
  ),
  ranked as (
    select
      n.*,
      case
        when btrim(coalesce(p_prefix, '')) = '' then 0
        when starts_with(public.normalize_item_name(n.name), public.normalize_item_name(p_prefix)) then 0
        when exists (
          select 1 from regexp_split_to_table(public.normalize_item_name(n.name), '[ -]+') as w
          where starts_with(w, public.normalize_item_name(p_prefix))
        ) then 1
      end as prefix_rank
    from named n
  )
  select
    r.name,
    (
      select i.quantity from public.items i
      where i.household_id = p_household and public.item_name_key(i.name) = r.key
      order by coalesce(i.bought_at, i.updated_at) desc
      limit 1
    ),
    r.uses,
    r.last_used,
    r.purchases >= 2
      and extract(epoch from p_now - r.last_bought_at) / 86400 between r.gap_days and 4 * r.gap_days
  from ranked r
  where r.prefix_rank is not null
  order by r.prefix_rank, r.score desc, r.last_used desc, r.name
  limit least(greatest(p_limit, 0), 200);
$$;

grant execute on function public.suggest_items(uuid, text, int, timestamptz) to authenticated;
