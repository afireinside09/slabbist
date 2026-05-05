-- 20260505120300_drop_slab_scan_events.sql
-- The eBay-scraper watchlist promotion signal has no consumer once
-- the eBay comp path is gone. Dropping per scope decision (option B
-- in the design spec).
drop table if exists public.slab_scan_events cascade;
