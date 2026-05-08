-- Add Poketrace as a second graded-pricing source.
--
--   * graded_card_identities.poketrace_card_id caches the Poketrace UUID
--     after the first tcgplayer_ids cross-walk. Empty string '' is a
--     "lookup attempted, no match" sentinel — re-attempt after 7 days.
--   * graded_market grows pt_* columns and the primary key extends to
--     include `source` so PPT rows and Poketrace rows can coexist.

alter table public.graded_card_identities
  add column if not exists poketrace_card_id text null,
  add column if not exists poketrace_card_id_resolved_at timestamptz null;

comment on column public.graded_card_identities.poketrace_card_id is
  'Cached Poketrace card UUID after tcgplayer_ids cross-walk. Empty string = lookup attempted, no match (re-attempt after 7 days).';

-- Make `source` part of the primary key. The existing PK is
-- `graded_market_pkey` over (identity_id, grading_service, grade) per
-- 20260422120000_tcgcsv_pokemon_and_graded.sql. All extant rows have
-- `source = 'pokemonpricetracker'` per 20260507120300, so the rebuild
-- preserves uniqueness.
alter table public.graded_market drop constraint if exists graded_market_pkey;
alter table public.graded_market
  add constraint graded_market_pkey
  primary key (identity_id, grading_service, grade, source);

-- Poketrace-namespaced columns. Only populated when source = 'poketrace'.
alter table public.graded_market
  add column if not exists pt_avg          numeric(12,2) null,
  add column if not exists pt_low          numeric(12,2) null,
  add column if not exists pt_high         numeric(12,2) null,
  add column if not exists pt_avg_1d       numeric(12,2) null,
  add column if not exists pt_avg_7d       numeric(12,2) null,
  add column if not exists pt_avg_30d      numeric(12,2) null,
  add column if not exists pt_median_3d    numeric(12,2) null,
  add column if not exists pt_median_7d    numeric(12,2) null,
  add column if not exists pt_median_30d   numeric(12,2) null,
  add column if not exists pt_trend        text          null,
  add column if not exists pt_confidence   text          null,
  add column if not exists pt_sale_count   integer       null;

alter table public.graded_market
  drop constraint if exists graded_market_pt_trend_check,
  add  constraint           graded_market_pt_trend_check
       check (pt_trend is null or pt_trend in ('up','down','stable'));

alter table public.graded_market
  drop constraint if exists graded_market_pt_confidence_check,
  add  constraint           graded_market_pt_confidence_check
       check (pt_confidence is null or pt_confidence in ('high','medium','low'));
