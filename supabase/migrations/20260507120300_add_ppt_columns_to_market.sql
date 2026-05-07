-- supabase/migrations/20260507120300_add_ppt_columns_to_market.sql

alter table public.graded_market
  add column if not exists ppt_tcgplayer_id text,
  add column if not exists ppt_url          text,
  add column if not exists psa_7_price      numeric(12,2),
  add column if not exists psa_8_price      numeric(12,2),
  add column if not exists psa_9_price      numeric(12,2),
  add column if not exists psa_9_5_price    numeric(12,2),
  add column if not exists price_history    jsonb;

update public.graded_market
   set source = 'pokemonpricetracker'
 where source = 'pricecharting';

alter table public.graded_market
  alter column source set default 'pokemonpricetracker';
