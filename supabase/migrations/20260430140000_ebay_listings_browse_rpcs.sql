-- 20260430140000_ebay_listings_browse_rpcs.sql
-- The Movers tab now exposes a third "eBay Listings" mode alongside
-- English / Japanese. These RPCs power that mode:
--
--   get_ebay_listings_sets()
--     Distinct sets that have at least one row in
--     `mover_ebay_listings`. Drives the narrowed set rail in eBay
--     mode — the rail should only show sets the user can actually
--     filter to, not the full English-or-Japanese set universe.
--
--   get_ebay_listings(p_price_tier, p_group_id, p_limit)
--     Flat list of listings, sorted by price ASC. Filters are
--     orthogonal: passing nil for tier or group means "no filter on
--     that axis." Tier is computed from the listing's current price
--     via the existing public.movers_price_tier() helper, so eBay
--     mode and Movers mode share one bucketing rule.
--
-- Why no language scoping:
--   eBay listings aren't language-keyed in our model. A graded slab
--   listing identifies the card by product_id; that maps back to a
--   single (category, set) but the eBay tab is meant as a flat
--   browsing surface across both languages. If we ever need EN-only
--   or JP-only, we can add a `p_category_id` parameter then.

-- ---------------------------------------------------------------
-- get_ebay_listings_sets — narrow set rail
-- ---------------------------------------------------------------

create or replace function public.get_ebay_listings_sets()
returns table (
  group_id      int,
  group_name    text,
  listings_count int,
  published_on  date
)
language sql
stable
as $$
  with sets as (
    select p.group_id, count(*)::int as listings_count
    from public.mover_ebay_listings l
    join public.tcg_products p on p.product_id = l.product_id
    group by p.group_id
  )
  select
    s.group_id,
    g.name           as group_name,
    s.listings_count,
    g.published_on
  from sets s
  join public.tcg_groups g on g.group_id = s.group_id
  order by g.published_on desc nulls last, g.name asc;
$$;

grant execute on function public.get_ebay_listings_sets() to anon, authenticated;

-- ---------------------------------------------------------------
-- get_ebay_listings — filterable flat list
-- ---------------------------------------------------------------

create or replace function public.get_ebay_listings(
  p_price_tier text default null,
  p_group_id   int  default null,
  p_limit      int  default 60
)
returns table (
  -- card identity
  product_id      int,
  sub_type_name   text,
  product_name    text,
  group_id        int,
  group_name      text,
  card_image_url  text,
  -- listing
  ebay_item_id    text,
  title           text,
  price           numeric,
  currency        text,
  url             text,
  image_url       text,
  grading_service text,
  grade           text,
  buying_options  text,
  end_at          timestamptz,
  refreshed_at    timestamptz
)
language sql
stable
as $$
  select
    p.product_id,
    l.sub_type_name,
    p.name           as product_name,
    p.group_id,
    g.name           as group_name,
    p.image_url      as card_image_url,
    l.ebay_item_id,
    l.title,
    l.price,
    l.currency,
    l.url,
    l.image_url,
    l.grading_service,
    l.grade,
    l.buying_options,
    l.end_at,
    l.refreshed_at
  from public.mover_ebay_listings l
  join public.tcg_products p on p.product_id = l.product_id
  left join public.tcg_groups g on g.group_id = p.group_id
  where (p_price_tier is null or public.movers_price_tier(l.price) = p_price_tier)
    and (p_group_id   is null or p.group_id = p_group_id)
  order by l.price asc nulls last, l.refreshed_at desc
  limit greatest(p_limit, 0);
$$;

grant execute on function public.get_ebay_listings(text, int, int) to anon, authenticated;
