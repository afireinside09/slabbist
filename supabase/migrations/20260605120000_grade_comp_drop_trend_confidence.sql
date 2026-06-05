-- 20260605120000_grade_comp_drop_trend_confidence.sql
-- Poketrace v1 never supplies trend/confidence for the PSA_10 price (null in
-- 100% of rows), and the ingest now persists only rows that carry a usable
-- PSA 10 price. Drop the two dead columns, refresh the read RPC, and purge the
-- legacy null-price (cache-only) rows that are no longer written.

-- 1. Purge existing rows with no PSA 10 price — they never reach the Grade
--    Gains page (the RPC already filters psa10 not-null) and are no longer
--    persisted going forward.
delete from public.tcg_grade_comp where psa10_price_cents is null;

-- 2. Drop the read RPC first so its return-type change is clean, then drop the
--    always-null columns.
drop function if exists public.get_set_grade_gains(int, text);

alter table public.tcg_grade_comp
  drop column if exists pt_trend,
  drop column if exists pt_confidence;

-- 3. Recreate get_set_grade_gains without pt_trend / pt_confidence.
create function public.get_set_grade_gains(
  p_group_id   int,
  p_price_tier text default 'under_5'
)
returns table (
  product_id        int,
  product_name      text,
  group_name        text,
  image_url         text,
  sub_type_name     text,
  raw_price_cents   int,
  psa10_price_cents int,
  spread_cents      int,
  pt_sale_count     int
)
language sql
stable
as $$
  with raw_best as (
    select distinct on (pr.product_id)
      pr.product_id, pr.sub_type_name, pr.market_price
    from public.tcg_prices pr
    where pr.market_price is not null and pr.market_price > 0
    order by pr.product_id, pr.market_price desc
  )
  select
    p.product_id,
    p.name                                                    as product_name,
    g.name                                                    as group_name,
    p.image_url,
    rb.sub_type_name,
    round(rb.market_price * 100)::int                         as raw_price_cents,
    c.psa10_price_cents,
    (c.psa10_price_cents - round(rb.market_price * 100)::int) as spread_cents,
    c.pt_sale_count
  from public.tcg_grade_comp c
  join public.tcg_products p on p.product_id = c.product_id
  join raw_best rb           on rb.product_id = c.product_id
  left join public.tcg_groups g on g.group_id = p.group_id
  where p.group_id = p_group_id
    and c.psa10_price_cents is not null
    and public.movers_price_tier(rb.market_price) = p_price_tier
    and (c.psa10_price_cents - round(rb.market_price * 100)::int) > 0
  order by spread_cents desc, p.product_id asc;
$$;

grant execute on function public.get_set_grade_gains(int, text) to anon, authenticated;
