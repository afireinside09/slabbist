-- 20260508120000_optimize_refresh_movers.sql
--
-- Problem: refresh_movers() times out when called via the Supabase JS
-- client (~30s Bun fetch timeout) because it does two full sequential
-- scans of tcg_price_history (~840K+ rows) using DISTINCT ON.
--
-- Fix (two parts):
--
-- 1. Replace the `latest` CTE with a direct read from `tcg_prices`,
--    which already holds the current price per (product_id, sub_type_name)
--    — eliminating a full 840K-row DISTINCT ON scan entirely.
--
-- 2. Add a covering index on tcg_price_history for the `baseline` CTE's
--    DISTINCT ON (product_id, sub_type_name) ORDER BY captured_at ASC
--    pattern.  The old index (product_id, captured_at DESC) forced an
--    incremental sort because sub_type_name was missing.

-- ---------------------------------------------------------------
-- Covering index for the baseline CTE
-- ---------------------------------------------------------------
create index concurrently if not exists
  tcg_price_history_product_sub_captured_idx
  on public.tcg_price_history (product_id, sub_type_name, captured_at asc)
  include (market_price);

-- ---------------------------------------------------------------
-- Rewrite refresh_movers to use tcg_prices for current prices
-- ---------------------------------------------------------------
create or replace function public.refresh_movers()
returns void
language plpgsql
as $$
declare
  v_now timestamptz := now();
begin
  drop table if exists _movers_fresh;
  create temp table _movers_fresh on commit drop as
  with latest as (
    -- tcg_prices is upserted every scrape run and already holds the
    -- current price per (product_id, sub_type_name).  Reading it
    -- replaces a DISTINCT ON scan over all of tcg_price_history.
    select
      p.product_id,
      p.sub_type_name,
      p.market_price   as current_price,
      p.updated_at     as captured_at
    from public.tcg_prices p
    where p.market_price is not null
      and p.market_price > 0
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
