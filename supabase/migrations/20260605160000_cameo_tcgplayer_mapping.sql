-- Maps each cameo card (1:1) to a specific TCGplayer product so the iOS card
-- detail page can show the card image and a product-specific affiliate link.
-- Nullable: most rows start unmapped and are filled by scripts/match-cameo-products.sql
-- plus manual correction in the Supabase table editor.
--
-- on delete set null (not cascade): if the scraper drops a tcg_products row the
-- cameo card survives and the mapping simply clears — consistent with the
-- raw/graded decoupling rule. The FK also validates manual entries: a
-- nonexistent product_id is rejected at write time.

alter table public.cameo_cards
  add column if not exists tcgplayer_product_id int
    references public.tcg_products(product_id) on delete set null;

create index if not exists cameo_cards_tcgplayer_product_id_idx
  on public.cameo_cards(tcgplayer_product_id);

comment on column public.cameo_cards.tcgplayer_product_id is
  'FK -> tcg_products.product_id. The specific TCGplayer printing this cameo card refers to. NULL = unmapped.';
