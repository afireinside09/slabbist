-- 20260429200000_movers_combine_sub_types.sql
-- Movers slates were partitioned by (group, sub_type, tier, direction)
-- so each sub-type variant got its own top-10. That hid signal: ME03:
-- Perfect Order had zero Normal movers in $5-$25 because nothing in
-- the Normal sub-type costs above 41¢, but the Holofoil variants for
-- the same set had 15 movers in that band — and the iOS app couldn't
-- see them because it queries `sub_type_name = 'Normal'` everywhere.
--
-- New shape: top-10 per (group, tier, direction) across ALL sub-types.
-- The sub_type_name comes along on each row as descriptive metadata so
-- the iOS row can subtly show "Charizard · Holo" alongside the plain
-- "Charizard" entry — they're different cards in the secondary market
-- and both belong on the same slate when they both moved.
--
-- Schema changes:
--   - PK: (group_id, sub_type_name, price_tier, direction, rank)
--          → (group_id, price_tier, direction, rank)
--     sub_type_name becomes a non-key descriptive column. Two rows
--     with the same product_id but different sub_types each take a
--     distinct rank — they ARE different cards.
--   - Index: drop sub_type_name from the supporting index since
--     queries no longer filter on it.
--
-- RPC signatures lose `p_sub_type`. The iOS app already hard-coded it
-- to "Normal" — that hard-code is now wrong, so the parameter is
-- dropped rather than silently ignored.

-- ---------------------------------------------------------------
-- Reshape the table
-- ---------------------------------------------------------------

truncate table public.movers;

alter table public.movers
  drop constraint if exists movers_pkey;

alter table public.movers
  add primary key (group_id, price_tier, direction, rank);

drop index if exists movers_category_direction_pct_idx;
create index movers_category_direction_pct_idx
  on public.movers (category_id, price_tier, direction, pct_change);

-- ---------------------------------------------------------------
-- refresh_movers() — partition the row_number windows on
-- (group_id, price_tier) instead of (group_id, sub_type_name,
-- price_tier). Everything else is unchanged.
-- ---------------------------------------------------------------

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
    where (p.card_number is not null or p.rarity is not null)
      and coalesce(p.rarity, '') <> 'Code Card'
  ),
  ranked_gainers as (
    select
      e.*,
      'gainers'::text as direction,
      row_number() over (
        -- Sub-type left out of the partition: a single Charizard
        -- product can appear twice (Normal + Holofoil), each
        -- holding its own rank slot.
        partition by e.group_id, e.price_tier
        order by e.pct_change desc, abs(e.abs_change) desc, e.product_id asc, e.sub_type_name asc
      ) as rank
    from enriched e
    where e.pct_change > 0
  ),
  ranked_losers as (
    select
      e.*,
      'losers'::text as direction,
      row_number() over (
        partition by e.group_id, e.price_tier
        order by e.pct_change asc, abs(e.abs_change) desc, e.product_id asc, e.sub_type_name asc
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
  on conflict (group_id, price_tier, direction, rank) do update
  set
    sub_type_name        = excluded.sub_type_name,
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
    where f.group_id   = m.group_id
      and f.price_tier = m.price_tier
      and f.direction  = m.direction
      and f.rank       = m.rank
  );
end;
$$;

grant execute on function public.refresh_movers() to service_role;

-- ---------------------------------------------------------------
-- Read RPCs — drop p_sub_type from all three.
-- ---------------------------------------------------------------

drop function if exists public.get_top_movers(int, text, int, text, text);
drop function if exists public.get_movers_sets(int, text);
drop function if exists public.get_set_movers(int, text, text);

create or replace function public.get_top_movers(
  p_category_id int,
  p_direction   text default 'gainers',
  p_limit       int  default 10,
  p_price_tier  text default 'under_5'
)
returns table (
  product_id           int,
  product_name         text,
  group_name           text,
  image_url            text,
  sub_type_name        text,
  current_price        numeric,
  previous_price       numeric,
  abs_change           numeric,
  pct_change           numeric,
  captured_at          timestamptz,
  previous_captured_at timestamptz
)
language sql
stable
as $$
  select
    m.product_id,
    m.product_name,
    m.group_name,
    m.image_url,
    m.sub_type_name,
    m.current_price,
    m.previous_price,
    m.abs_change,
    m.pct_change,
    m.captured_at,
    m.previous_captured_at
  from public.movers m
  where m.category_id = p_category_id
    and m.direction   = p_direction
    and m.price_tier  = p_price_tier
  order by
    case when p_direction = 'gainers' then m.pct_change end desc nulls last,
    case when p_direction = 'losers'  then m.pct_change end asc  nulls last,
    abs(m.abs_change) desc
  limit greatest(p_limit, 0);
$$;

grant execute on function public.get_top_movers(int, text, int, text) to anon, authenticated;

create or replace function public.get_movers_sets(
  p_category_id int
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
    where m.category_id = p_category_id
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

grant execute on function public.get_movers_sets(int) to anon, authenticated;

create or replace function public.get_set_movers(
  p_group_id   int,
  p_price_tier text default 'under_5'
)
returns table (
  direction            text,
  rank                 smallint,
  product_id           int,
  product_name         text,
  group_name           text,
  image_url            text,
  sub_type_name        text,
  current_price        numeric,
  previous_price       numeric,
  abs_change           numeric,
  pct_change           numeric,
  captured_at          timestamptz,
  previous_captured_at timestamptz
)
language sql
stable
as $$
  select
    m.direction,
    m.rank,
    m.product_id,
    m.product_name,
    m.group_name,
    m.image_url,
    m.sub_type_name,
    m.current_price,
    m.previous_price,
    m.abs_change,
    m.pct_change,
    m.captured_at,
    m.previous_captured_at
  from public.movers m
  where m.group_id   = p_group_id
    and m.price_tier = p_price_tier
  order by m.direction asc, m.rank asc;
$$;

grant execute on function public.get_set_movers(int, text) to anon, authenticated;

-- ---------------------------------------------------------------
-- Repopulate immediately so the iOS app sees the combined slates
-- the moment the migration commits.
-- ---------------------------------------------------------------

select public.refresh_movers();
