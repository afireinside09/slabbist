-- 20260505120100_graded_market_pricecharting_columns.sql
-- Drops the eBay-aggregate columns added in 20260424000001 and the
-- generic distribution columns owned by the original tcgcsv graded
-- migration; replaces them with PriceCharting's per-grade ladder.
-- The ladder is the only canonical price source going forward.

alter table public.graded_market
  drop column if exists mean_price,
  drop column if exists trimmed_mean_price,
  drop column if exists sample_window_days,
  drop column if exists confidence,
  drop column if exists velocity_7d,
  drop column if exists velocity_30d,
  drop column if exists velocity_90d,
  drop column if exists sample_count_30d,
  drop column if exists sample_count_90d,
  drop column if exists low_price,
  drop column if exists median_price,
  drop column if exists high_price,
  drop column if exists last_sale_price,
  drop column if exists last_sale_at;

alter table public.graded_market
  add column if not exists source                   text,
  add column if not exists pricecharting_product_id text,
  add column if not exists pricecharting_url        text,
  add column if not exists headline_price           numeric(12,2),
  add column if not exists loose_price              numeric(12,2),
  add column if not exists grade_7_price            numeric(12,2),
  add column if not exists grade_8_price            numeric(12,2),
  add column if not exists grade_9_price            numeric(12,2),
  add column if not exists grade_9_5_price          numeric(12,2),
  add column if not exists psa_10_price             numeric(12,2),
  add column if not exists bgs_10_price             numeric(12,2),
  add column if not exists cgc_10_price             numeric(12,2),
  add column if not exists sgc_10_price             numeric(12,2);

update public.graded_market set source = 'pricecharting' where source is null;
alter table public.graded_market alter column source set not null;
alter table public.graded_market alter column source set default 'pricecharting';
