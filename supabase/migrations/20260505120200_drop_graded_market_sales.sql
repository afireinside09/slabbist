-- 20260505120200_drop_graded_market_sales.sql
-- PriceCharting publishes aggregate per-grade prices, not per-listing
-- rows. The only writers were the eBay edge function path (now gone)
-- and the scraper's ebay-sold ingest (also being deleted in this
-- changeset). No remaining consumers.
drop table if exists public.graded_market_sales cascade;
