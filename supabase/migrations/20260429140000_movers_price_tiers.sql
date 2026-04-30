-- 20260429140000_movers_price_tiers.sql
-- Slice the per-set movers slates by current-price tier so the iOS
-- Movers tab can answer "what's moving in $25-$50 cards in Base Set?"
-- without sub-dollar rockets crowding out everything else.
--
-- Why a stored tier dimension (not a runtime filter):
--   The table only keeps the top-10 per partition. If we filtered by
--   tier at query time, the universe would be the existing top-10s
--   (which heavily skew under_5 for any popular set) and nearly every
--   higher-tier query would come back empty. Pre-computing top-10
--   per (group, sub_type, tier) puts each tier on equal footing.
--
-- Tier scheme (text labels, not enum, so they round-trip cleanly to
-- iOS without a Postgres-type-aware decoder):
--   - 'all'           → current_price ≥ 0 (the whole spectrum, kept
--                       so the existing "no tier picked" UX returns
--                       the same rows it always has)
--   - 'under_5'       → current_price < 5
--   - 'tier_5_25'     → 5 ≤ current_price < 25
--   - 'tier_25_50'    → 25 ≤ current_price < 50
--   - 'tier_50_100'   → 50 ≤ current_price < 100
--   - 'tier_100_200'  → 100 ≤ current_price < 200
--   - 'tier_200_plus' → current_price ≥ 200
--
-- Storage estimate: 200 sets × 7 tiers × 2 directions × 10 ranks ≈
-- 28 000 rows per language. Both languages → ~56 000 rows. Index
-- footprint is comparable. The materialized cost is tiny next to the
-- 280k-row tcg_price_history scan that refresh_movers() already does
-- once per ingest.
--
-- Function signatures grow by one default-valued param so PostgREST
-- callers that haven't migrated keep working — but Postgres won't let
-- us *add* a parameter via `create or replace`, so each function is
-- dropped and recreated. iOS clients pass the param explicitly.

-- ---------------------------------------------------------------
-- Tier helper. Stable text label keyed off current_price. Inlined
-- everywhere we need to compute a tier so the bucketing rule stays
-- in one place.
-- ---------------------------------------------------------------

create or replace function public.movers_price_tier(p_price numeric)
returns text
language sql
immutable
as $$
  select case
    when p_price <    5 then 'under_5'
    when p_price <   25 then 'tier_5_25'
    when p_price <   50 then 'tier_25_50'
    when p_price <  100 then 'tier_50_100'
    when p_price <  200 then 'tier_100_200'
    else                     'tier_200_plus'
  end;
$$;

-- ---------------------------------------------------------------
-- Schema change: add price_tier and recompose the PK around it.
-- The table is fully derived by refresh_movers(); truncating it here
-- avoids a DEFAULT-then-DROP-DEFAULT dance for the new NOT NULL
-- column. The function is invoked at the bottom of this migration
-- to repopulate before the transaction commits.
-- ---------------------------------------------------------------

truncate table public.movers;

alter table public.movers
  drop constraint if exists movers_pkey;

alter table public.movers
  add column if not exists price_tier text not null
    check (price_tier in ('all','under_5','tier_5_25','tier_25_50',
                          'tier_50_100','tier_100_200','tier_200_plus'));

alter table public.movers
  add primary key (group_id, sub_type_name, price_tier, direction, rank);

drop index if exists movers_category_direction_pct_idx;
create index movers_category_direction_pct_idx
  on public.movers (category_id, price_tier, direction, sub_type_name, pct_change);

-- ---------------------------------------------------------------
-- Refresh: per-set top-10 per (tier, direction), plus an 'all' tier
-- that mirrors the pre-tier behavior. One temp table fans out into
-- the upsert + stale-delete pattern the previous version used.
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
  ),
  -- Two passes per direction. The 'all' tier keeps the legacy view
  -- (top-10 across every price); the tier-scoped pass partitions on
  -- the computed tier so each band gets its own slate.
  ranked_gainers_all as (
    select
      e.*,
      'all'::text     as tier_label,
      'gainers'::text as direction,
      row_number() over (
        partition by e.group_id, e.sub_type_name
        order by e.pct_change desc, abs(e.abs_change) desc, e.product_id asc
      ) as rank
    from enriched e
    where e.pct_change > 0
  ),
  ranked_losers_all as (
    select
      e.*,
      'all'::text     as tier_label,
      'losers'::text  as direction,
      row_number() over (
        partition by e.group_id, e.sub_type_name
        order by e.pct_change asc, abs(e.abs_change) desc, e.product_id asc
      ) as rank
    from enriched e
    where e.pct_change < 0
  ),
  ranked_gainers_tiered as (
    select
      e.*,
      e.price_tier    as tier_label,
      'gainers'::text as direction,
      row_number() over (
        partition by e.group_id, e.sub_type_name, e.price_tier
        order by e.pct_change desc, abs(e.abs_change) desc, e.product_id asc
      ) as rank
    from enriched e
    where e.pct_change > 0
  ),
  ranked_losers_tiered as (
    select
      e.*,
      e.price_tier    as tier_label,
      'losers'::text  as direction,
      row_number() over (
        partition by e.group_id, e.sub_type_name, e.price_tier
        order by e.pct_change asc, abs(e.abs_change) desc, e.product_id asc
      ) as rank
    from enriched e
    where e.pct_change < 0
  ),
  unioned as (
    select * from ranked_gainers_all   where rank <= 10
    union all
    select * from ranked_losers_all    where rank <= 10
    union all
    select * from ranked_gainers_tiered where rank <= 10
    union all
    select * from ranked_losers_tiered  where rank <= 10
  )
  select
    group_id, category_id, sub_type_name,
    tier_label as price_tier,
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

-- ---------------------------------------------------------------
-- Recreate the read RPCs with the new tier filter. Default 'all'
-- keeps any non-tier-aware caller showing the legacy slate.
-- ---------------------------------------------------------------

drop function if exists public.get_top_movers(int, text, int, text);
drop function if exists public.get_movers_sets(int, text);
drop function if exists public.get_set_movers(int, text);

create or replace function public.get_top_movers(
  p_category_id int,
  p_direction   text default 'gainers',
  p_limit       int  default 10,
  p_sub_type    text default 'Normal',
  p_price_tier  text default 'all'
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
  where m.category_id   = p_category_id
    and m.sub_type_name = p_sub_type
    and m.direction     = p_direction
    and m.price_tier    = p_price_tier
  order by
    case when p_direction = 'gainers' then m.pct_change end desc nulls last,
    case when p_direction = 'losers'  then m.pct_change end asc  nulls last,
    abs(m.abs_change) desc
  limit greatest(p_limit, 0);
$$;

grant execute on function public.get_top_movers(int, text, int, text, text) to anon, authenticated;

create or replace function public.get_movers_sets(
  p_category_id int,
  p_sub_type    text default 'Normal',
  p_price_tier  text default 'all'
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
      and m.price_tier    = p_price_tier
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

grant execute on function public.get_movers_sets(int, text, text) to anon, authenticated;

create or replace function public.get_set_movers(
  p_group_id   int,
  p_sub_type   text default 'Normal',
  p_price_tier text default 'all'
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
  where m.group_id      = p_group_id
    and m.sub_type_name = p_sub_type
    and m.price_tier    = p_price_tier
  order by m.direction asc, m.rank asc;
$$;

grant execute on function public.get_set_movers(int, text, text) to anon, authenticated;

-- ---------------------------------------------------------------
-- Repopulate immediately so the iOS app sees data the moment the
-- migration lands. Subsequent refreshes flow through the scraper.
-- ---------------------------------------------------------------

select public.refresh_movers();
