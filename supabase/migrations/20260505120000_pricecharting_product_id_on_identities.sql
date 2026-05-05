-- 20260505120000_pricecharting_product_id_on_identities.sql
-- Sticky cache of PriceCharting's product id on the identity row so
-- the scan-time edge function only pays the search-API hop once per
-- identity. Resolved on first comp fetch, reused forever after.

alter table public.graded_card_identities
  add column if not exists pricecharting_product_id text,
  add column if not exists pricecharting_url        text;

create index if not exists graded_card_identities_pc_product_idx
  on public.graded_card_identities (pricecharting_product_id)
  where pricecharting_product_id is not null;
