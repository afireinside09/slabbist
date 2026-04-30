-- 20260429190000_movers_drop_all_tier.sql
-- The "all" price tier was originally kept as a backward-compatible
-- fallback for callers that hadn't picked a band yet. The iOS UI
-- now defaults to a real tier on first load and never hands back to
-- "all", so those rows are dead storage that bloats the table and
-- muddies queries.
--
-- This migration:
--   1. Drops the price_tier check constraint and re-adds it without
--      'all' as a valid value.
--   2. Removes any existing 'all' rows from public.movers (TRUNCATE
--      already happened, but DELETE is idempotent against either
--      pre-state).
--   3. Rewrites refresh_movers() so the union no longer produces
--      'all' rows — only the six real price bands.
--   4. Drops the tier parameter from get_movers_sets(): the set
--      rail is supposed to show every set with any mover regardless
--      of which tier the user has picked, so the function now does
--      a SELECT DISTINCT across the whole table for the requested
--      (category, sub_type).
--   5. Calls refresh_movers() so the table is repopulated against
--      the new shape before the migration commits.

-- 1. Constraint update
alter table public.movers
  drop constraint if exists movers_price_tier_check;

-- 2. Sweep any leftover 'all' rows
delete from public.movers where price_tier = 'all';

alter table public.movers
  add constraint movers_price_tier_check
    check (price_tier in ('under_5','tier_5_25','tier_25_50',
                          'tier_50_100','tier_100_200','tier_200_plus'));

-- 3. refresh_movers() — drop the all-tier branches
create or replace function public.refresh_movers()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
begin
  drop table if exists _movers_fresh;
  create temp table _movers_fresh on commit drop as
  with latest as (
    select distinct on (h.product_id, h.sub_type_name)
      h.product_id,
      h.sub_type_name,
      h.market_price                                                         as current_price,
      h.captured_at
    from public.tcg_price_history h
    where h.market_price is not null
      and h.market_price > 0
    order by h.product_id, h.sub_type_name, h.captured_at desc
  ),
  baseline as (
    select distinct on (h.product_id, h.sub_type_name)
      h.product_id,
      h.sub_type_name,
      h.market_price                                                         as previous_price,
      h.captured_at                                                          as previous_captured_at
    from public.tcg_price_history h
    where h.market_price is not null
      and h.market_price > 0
      and h.captured_at >= v_now - interval '90 days'
    order by h.product_id, h.sub_type_name, h.captured_at asc
  ),
  moves as (
    select
      l.product_id,
      l.sub_type_name,
      l.current_price,
      b.previous_price,
      l.captured_at,
      b.previous_captured_at,
      (l.current_price - b.previous_price)                                   as abs_change,
      ((l.current_price - b.previous_price) / b.previous_price) * 100        as pct_change
    from latest l
    join baseline b
      on b.product_id    = l.product_id
     and b.sub_type_name = l.sub_type_name
    where l.captured_at > b.previous_captured_at
  ),
  enriched as (
    select
      m.*,
      p.group_id,
      p.category_id,
      p.name      as product_name,
      g.name      as group_name,
      p.image_url,
      public.movers_price_tier(m.current_price)                              as price_tier
    from moves m
    join public.tcg_products p on p.product_id = m.product_id
    left join public.tcg_groups g on g.group_id = p.group_id
    -- Singles only: cards have card_number or rarity; sealed/code
    -- cards have neither (or rarity = 'Code Card').
    where (p.card_number is not null or p.rarity is not null)
      and coalesce(p.rarity, '') <> 'Code Card'
  ),
  ranked_gainers as (
    select
      e.*,
      'gainers'::text as direction,
      row_number() over (
        partition by e.group_id, e.sub_type_name, e.price_tier
        order by e.pct_change desc, abs(e.abs_change) desc, e.product_id asc
      ) as rank
    from enriched e
    where e.pct_change > 0
  ),
  ranked_losers as (
    select
      e.*,
      'losers'::text as direction,
      row_number() over (
        partition by e.group_id, e.sub_type_name, e.price_tier
        order by e.pct_change asc, abs(e.abs_change) desc, e.product_id asc
      ) as rank
    from enriched e
    where e.pct_change < 0
  ),
  unioned as (
    select * from ranked_gainers where rank <= 10
    union all
    select * from ranked_losers  where rank <= 10
  )
  select
    group_id, category_id, sub_type_name, price_tier,
    direction, rank::smallint as rank,
    product_id, product_name, group_name, image_url,
    current_price, previous_price, abs_change, pct_change,
    captured_at, previous_captured_at
  from unioned;

  insert into public.movers (
    group_id, category_id, sub_type_name, price_tier, direction, rank,
    product_id, product_name, group_name, image_url,
    current_price, previous_price, abs_change, pct_change,
    captured_at, previous_captured_at, refreshed_at
  )
  select
    f.group_id, f.category_id, f.sub_type_name, f.price_tier, f.direction, f.rank,
    f.product_id, f.product_name, f.group_name, f.image_url,
    f.current_price, f.previous_price, f.abs_change, f.pct_change,
    f.captured_at, f.previous_captured_at, v_now
  from _movers_fresh f
  on conflict (group_id, sub_type_name, price_tier, direction, rank) do update
  set
    category_id          = excluded.category_id,
    product_id           = excluded.product_id,
    product_name         = excluded.product_name,
    group_name           = excluded.group_name,
    image_url            = excluded.image_url,
    current_price        = excluded.current_price,
    previous_price       = excluded.previous_price,
    abs_change           = excluded.abs_change,
    pct_change           = excluded.pct_change,
    captured_at          = excluded.captured_at,
    previous_captured_at = excluded.previous_captured_at,
    refreshed_at         = excluded.refreshed_at;

  delete from public.movers m
  where not exists (
    select 1
    from _movers_fresh f
    where f.group_id      = m.group_id
      and f.sub_type_name = m.sub_type_name
      and f.price_tier    = m.price_tier
      and f.direction     = m.direction
      and f.rank          = m.rank
  );
end;
$$;

grant execute on function public.refresh_movers() to service_role;

-- 4. get_movers_sets — drop p_price_tier; rail spans every tier so
-- the user's set selection survives a tier switch.
drop function if exists public.get_movers_sets(int, text, text);

create or replace function public.get_movers_sets(
  p_category_id int,
  p_sub_type    text default 'Normal'
)
returns table (
  group_id     int,
  group_name   text,
  movers_count int,
  published_on date
)
language sql
stable
as $$
  with sets as (
    select m.group_id, count(*)::int as movers_count
    from public.movers m
    where m.category_id   = p_category_id
      and m.sub_type_name = p_sub_type
    group by m.group_id
  )
  select
    s.group_id,
    g.name           as group_name,
    s.movers_count,
    g.published_on
  from sets s
  join public.tcg_groups g on g.group_id = s.group_id
  order by g.published_on desc nulls last, g.name asc;
$$;

grant execute on function public.get_movers_sets(int, text) to anon, authenticated;

-- 5. Repopulate so the iOS app sees the new shape immediately.
select public.refresh_movers();
