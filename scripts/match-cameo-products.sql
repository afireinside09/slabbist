-- match-cameo-products.sql
--
-- Fills cameo_cards.tcgplayer_product_id ONLY where currently NULL, so it never
-- clobbers manual corrections. Conservative: assigns a product only when exactly
-- one tcg_products row matches a card on (normalized card number AND normalized
-- name AND fuzzy set name). Ambiguous (>1 candidate) or no candidate → left NULL.
--
-- Run:  psql "$DATABASE_URL" -f scripts/match-cameo-products.sql
-- Idempotent: re-running only fills newly-NULL rows.

\timing on

-- Normalization helpers inline via lower()/regexp; no schema changes.
with candidates as (
  select
    c.id            as cameo_card_id,
    p.product_id    as product_id,
    count(*) over (partition by c.id) as n_matches
  from public.cameo_cards c
  join public.tcg_products p
    on  c.tcgplayer_product_id is null
    -- card number: digits only, must be present on both and equal
    and nullif(regexp_replace(coalesce(c.card_number, ''), '\D', '', 'g'), '') =
        nullif(regexp_replace(coalesce(p.card_number, ''), '\D', '', 'g'), '')
    -- name: normalized substring match either direction
    and (
      lower(regexp_replace(c.card_name, '[^a-z0-9]', '', 'gi')) =
      lower(regexp_replace(coalesce(p.clean_name, p.name), '[^a-z0-9]', '', 'gi'))
    )
  join public.tcg_groups g
    on  g.group_id = p.group_id
    -- set name: normalized substring match either direction
    and (
      lower(regexp_replace(c.set_name, '[^a-z0-9]', '', 'gi')) like
        '%' || lower(regexp_replace(g.name, '[^a-z0-9]', '', 'gi')) || '%'
      or lower(regexp_replace(g.name, '[^a-z0-9]', '', 'gi')) like
        '%' || lower(regexp_replace(c.set_name, '[^a-z0-9]', '', 'gi')) || '%'
    )
),
unique_matches as (
  select cameo_card_id, product_id from candidates where n_matches = 1
)
update public.cameo_cards c
set tcgplayer_product_id = u.product_id
from unique_matches u
where c.id = u.cameo_card_id
  and c.tcgplayer_product_id is null;

-- Fail-loud summary: matched / ambiguous / still-unmatched.
do $$
declare
  v_mapped   int;
  v_unmapped int;
begin
  select count(*) into v_mapped   from public.cameo_cards where tcgplayer_product_id is not null;
  select count(*) into v_unmapped from public.cameo_cards where tcgplayer_product_id is null;
  raise notice 'cameo_cards mapped: %, still unmapped: %', v_mapped, v_unmapped;
end $$;
