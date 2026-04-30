-- 20260429180000_movers_singles_only.sql
-- Trim sealed product (booster boxes, ETBs, tins, blisters, premium
-- collections) and code cards out of the movers table. Hobby-store
-- vendors care about the singles market — sub-$1 booster packs
-- doubling in price isn't actionable signal, but a card that moved
-- 30% in its tier absolutely is.
--
-- How a "card" is identified:
--   tcg_products is mostly cards but also stores sealed entries and
--   "Code Card" inserts. The rule used here:
--
--     (card_number IS NOT NULL OR rarity IS NOT NULL)
--     AND rarity <> 'Code Card'
--
--   - card_number populated → English-region card (TCGCSV always
--     fills it for EN cards)
--   - rarity populated → JP cards which often don't carry a
--     card_number in TCGCSV but always have a rarity
--   - rarity = 'Code Card' → paper insert that grants a digital
--     code; not a tradable card
--
--   Verified against current data: 57,325 products survive (27,841
--   EN + 29,484 JP) versus 4,343 dropped (3,994 EN sealed/codecard +
--   349 JP). The dropped bucket on inspection is uniformly sealed
--   product names (Booster Box, ETB, Tin, Premium Collection, Single
--   Pack Blister) plus Code Card inserts.
--
-- Data lifecycle:
--   refresh_movers() rebuilds the table from tcg_price_history each
--   time the scraper finishes an ingest. Sealed rows currently in
--   public.movers will be deleted by the existing stale-row sweep
--   the first time the new function runs — which we trigger at the
--   end of this migration so the iOS app reflects the change
--   immediately.

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
    -- Singles only: keep rows that look like cards (card_number or
    -- rarity present) and explicitly drop Code Card inserts.
    where (p.card_number is not null or p.rarity is not null)
      and coalesce(p.rarity, '') <> 'Code Card'
  ),
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

-- Repopulate the movers table immediately so the iOS app sees the
-- sealed rows disappear without waiting for the next scraper run.
select public.refresh_movers();
