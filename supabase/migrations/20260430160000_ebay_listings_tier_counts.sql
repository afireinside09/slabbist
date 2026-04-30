-- 20260430160000_ebay_listings_tier_counts.sql
-- Per-set listing counts by price tier. Drives the iOS eBay-tab
-- tier rail: tiers that come back with zero listings for the
-- currently-picked set get hidden so the user can't tap into an
-- empty band.
--
-- Why a separate RPC instead of bundling into get_ebay_listings:
--   The browse RPC returns at most `p_limit` rows; a tier could
--   look empty just because we didn't fetch into it. The COUNT(*)
--   here is computed against the whole `mover_ebay_listings` table,
--   so a tier showing zero genuinely means zero.

create or replace function public.get_ebay_listings_tier_counts(
  p_group_id int default null
)
returns table (
  price_tier     text,
  listings_count int
)
language sql
stable
as $$
  select
    public.movers_price_tier(l.price) as price_tier,
    count(*)::int                     as listings_count
  from public.mover_ebay_listings l
  join public.tcg_products p on p.product_id = l.product_id
  where (p_group_id is null or p.group_id = p_group_id)
  group by public.movers_price_tier(l.price)
  order by listings_count desc;
$$;

grant execute on function public.get_ebay_listings_tier_counts(int)
  to anon, authenticated;
