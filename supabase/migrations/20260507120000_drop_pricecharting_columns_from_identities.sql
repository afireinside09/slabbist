-- supabase/migrations/20260507120000_drop_pricecharting_columns_from_identities.sql

drop index if exists graded_card_identities_pc_product_idx;

alter table public.graded_card_identities
  drop column if exists pricecharting_product_id,
  drop column if exists pricecharting_url;
