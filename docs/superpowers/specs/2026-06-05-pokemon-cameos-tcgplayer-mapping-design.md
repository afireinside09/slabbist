# Pokemon Cameos — images, card detail page, TCGplayer mapping

**Date:** 2026-06-05
**Status:** Approved (design)
**Supersedes/extends:** `2026-06-05-psyduck-cameo-dex-design.md` (the original hidden Cameo Dex feature)

## Problem

The hidden "Cameo Dex" page lists, for each Pokémon/Trainer, every card it cameos
in — but cards are text-only and link to a generic TCGplayer *search*. We want:

1. Rename the page from "Cameo Dex" to **"Pokemon Cameos"**.
2. Show the actual **card image** for each TCGplayer item, and let the user tap
   through to a **card detail page** carrying the **product-specific TCGplayer
   affiliate link**.
3. A **proper, persisted mapping** from each cameo card to a specific TCGplayer
   product, which the user will hand-correct row by row in Supabase.

## Data landscape (existing)

- `public.cameo_subjects` (1013 rows) and `public.cameo_cards` (3945 rows) are
  global-reference, public-read tables, seeded from `cameo-data/*.csv` by
  `scripts/seed-cameos.ts` (parse logic in `scripts/cameo_parse.ts`).
- `public.tcg_products` has `product_id` (PK = TCGplayer product id), `name`,
  `clean_name`, `image_url`, `card_number`, `group_id → tcg_groups(name)` (set).
  It and `tcg_groups` are already `*_public_read` (anon can SELECT).
- `TCGPlayerAffiliateLink.link(productId:subId:)` already builds a
  product-specific impact.com affiliate URL; `TCGPlayerLinkButton(productId:subId:)`
  renders the "View on TCGplayer" CTA. `TCGPlayerSearchLinkButton(query:)` is the
  existing search fallback.
- iOS reads cameo tables PostgREST-direct via `CameoRepository`
  (`.query().select()`), not through an Edge Function.

## Decisions (from brainstorming)

- **Mapping shape:** a single `tcgplayer_product_id int` column on `cameo_cards`
  (1:1), FK → `tcg_products`. Not a join table.
- **Pre-seed:** run a conservative automated best-guess match to populate the
  column where confident; leave ambiguous/none NULL.
- **Unmapped cards:** graceful fallback — mapped cards show image + product link;
  unmapped show no image + the existing search button.
- **Editing:** user edits `tcgplayer_product_id` directly in Supabase. No in-app
  admin editor.
- **Seed durability:** make `seed-cameos.ts` non-destructive so re-seeds preserve
  the user's manual mappings (see Part 2).

## Design

### Part 0 — Rename

`CameoSecretView.swift:18` `KickerLabel("Cameo Dex")` → `KickerLabel("Pokemon Cameos")`.
Grep for any other user-facing "Cameo Dex" strings (nav titles, accessibility
labels) and update them. Internal file/dir/type names (`Features/Cameo`,
`CameoRepository`, etc.) are unchanged — not user-facing.

### Part 1 — Schema (new migration)

New migration `YYYYMMDDHHMMSS_cameo_tcgplayer_mapping.sql`:

```sql
alter table public.cameo_cards
  add column tcgplayer_product_id int
    references public.tcg_products(product_id) on delete set null;

create index if not exists cameo_cards_tcgplayer_product_id_idx
  on public.cameo_cards(tcgplayer_product_id);
```

- `on delete set null` (not cascade): a scraper-dropped product clears the
  mapping but keeps the cameo card. Consistent with raw/graded decoupling.
- The FK validates manual entries — a nonexistent `product_id` is rejected.
- No new RLS: `cameo_cards`, `tcg_products`, `tcg_groups` are already
  `*_public_read`, so the anon iOS client can read the embedded image/link.

### Part 2 — Non-destructive seed (protect manual mappings)

`seed-cameos.ts` currently deletes all subjects (cards cascade) then bulk-inserts
with `gen_random_uuid()` ids. That would wipe every hand-set
`tcgplayer_product_id` on any re-run. Fix:

- Derive **deterministic ids** from a stable natural key:
  - subject: `uuidv5(namespace, "kind|name")` (already unique by `(kind, name)`).
  - card: `uuidv5(namespace, "kind|name|cardName|setName|cardNumber|generation")`.
- Switch from delete+reinsert to **upsert** (`on conflict (id) do update`) that
  updates only the content columns and **never touches `tcgplayer_product_id`**.
- Add a unique constraint backing the card natural key if needed so upsert is
  well-defined. Subjects already have `unique(kind, name)`.
- Rows removed from the CSV: out of scope for this change (the table is additive
  in practice); note it but do not implement a destructive prune.

Result: re-seeding refreshes content while preserving the mapping column.

### Part 3 — Auto-seed match pass (re-runnable SQL)

A `psql`-run script `scripts/match-cameo-products.sql` (run via `$DATABASE_URL`)
that fills `tcgplayer_product_id` **only where NULL** (idempotent — never
clobbers manual edits):

- Candidate match requires: `card_number` equality AND name match
  (`cameo.card_name` ↔ `tcg_products.clean_name`/`name`, normalized) AND fuzzy
  set-name match (`cameo.set_name` ↔ `tcg_groups.name`, normalized).
- Assign **only when exactly one** candidate matches a card; ambiguous (>1) or
  none → leave NULL.
- Print matched / ambiguous / unmatched counts (fail-loud, no silent caps).

Conservative by design: better to leave NULL than to auto-assign a wrong product
the user must hunt down and undo.

### Part 4 — iOS data layer

- `CameoCardDTO` gains an optional embedded product:
  ```swift
  let tcgProduct: CameoCardProductDTO?   // decodes "tcg_products" embed
  // CameoCardProductDTO { productId: Int, imageURL: String? }
  ```
- `CameoRepository.cards(forSubject:)` select becomes
  `*, tcg_products(product_id, image_url)` (PostgREST embed via the new FK).

### Part 5 — iOS UI

- **Card list** (`CameoSubjectDetailView`): each row gains a leading thumbnail
  (`AsyncImage` from `tcgProduct.imageURL`, placeholder when unmapped) and becomes
  a tap-through (`NavigationLink`) instead of carrying an inline button.
- **New `CameoCardDetailView`**: large card image + name / set / number / notes +
  affiliate CTA:
  - mapped → `TCGPlayerLinkButton(productId:, subId: "cameo")`
  - unmapped → no image + existing `TCGPlayerSearchLinkButton(query:)` fallback

Styling follows `.impeccable.md` (dark + gold, `AsyncImage` transition matching
existing image surfaces, 44pt targets, AA contrast).

### Part 6 — Tests

- Extend `CameoDTODecodeTests` to decode the embedded product (mapped + null).
- iOS build green (`xcodebuild` on an iOS 26.x sim).
- Match pass verified by its printed counts.

## Out of scope

- In-app mapping editor (user edits in Supabase).
- Destructive CSV prune on re-seed.
- Any change to the raw/graded comp hero flow or Edge Functions.
