-- supabase/migrations/20260507120200_drop_pricecharting_columns_from_market.sql

alter table public.graded_market
  drop column if exists pricecharting_product_id,
  drop column if exists pricecharting_url,
  drop column if exists grade_7_price,
  drop column if exists grade_8_price,
  drop column if exists grade_9_price,
  drop column if exists grade_9_5_price;
