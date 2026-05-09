-- Add a per-tier price map for the Poketrace branch so the iOS source
-- toggle can flip the comp-card ladder between PPT and Poketrace.
-- Stored as JSONB keyed by iOS-friendly tier names ("loose", "psa_7",
-- "psa_8", "psa_9", "psa_9_5", "psa_10", "bgs_10", "cgc_10", "sgc_10")
-- with integer cents values. Only populated when source='poketrace';
-- null for source='pokemonpricetracker'.

alter table public.graded_market
  add column if not exists pt_tier_prices_cents jsonb null;

comment on column public.graded_market.pt_tier_prices_cents is
  'Poketrace per-tier price map, JSONB keyed by iOS tier ids (loose, psa_7..psa_10, bgs_10, cgc_10, sgc_10), integer cents. Source-of-truth for the iOS comp-card ladder when source=''poketrace''.';
