# Psyduck Cameo Dex — design

**Date:** 2026-06-05
**Status:** Approved (brainstorm), pending implementation plan

## Summary

A hidden easter egg in the iOS app: a Psyduck (`cameo-data/psyduck.png`) peeks out from the
trailing edge of every screen. Tapping it opens a full-screen "Cameo Dex" with **no tab
navigation** that lets the user browse and search every Pokémon (and Trainer) that appears as a
*cameo* on Pokémon TCG cards. Each card that features a cameo links out to a TCGplayer search,
wrapped in our existing impact.com affiliate base.

The source data is `cameo-data/RotomAmiti's Cameo Pokémon Card Database` — 10 CSV sheets
(Gen 1–9 + Trainers). It is processed and stored in Supabase as global reference data.

## Decisions (locked during brainstorm)

1. **TCGplayer linking = search URLs for every card.** No product-ID matching against `tcg_products`.
   Each card links to a TCGplayer search pre-filled with card name + set.
2. **Scope = Pokémon (Gen 1–9) + Trainers.** Both fold into the same tables via a `kind` discriminator.
3. **Easter egg = all screens, always, same spot.** Psyduck overlays every tab at a fixed edge position.
4. **Read path = PostgREST direct via a repo** (not a new edge function). Plain reference read.
5. **Schema in a migration; data in a re-runnable seed script** (DDL and reference data stay separate).

## Source data shape

Header (Gen sheets): `Ndex,Cameo Pokémon,Card name,Set,#,Notes`
Header (Trainers): `,Cameo Trainer,Card name,Set,#,Notes` (col 0 is region, e.g. `KANTO`)

The CSV is **sparse / forward-filled** at two independent levels:

- `Ndex` + `Cameo Pokémon` (Gen) / region + `Cameo Trainer` (Trainers) are filled only on the first
  row of a subject group, blank thereafter — forward-fill **down** until the next subject.
- `Card name` is blank on reprint rows: a single card reprinted across sets appears as one row with
  the card name, followed by rows with blank `Card name` but a new `Set`/`#`. Forward-fill the card
  name **down** until the next non-blank card name (the next card or the next subject boundary).

`#` (card number) is **not numeric** — values include `2nd`, `TG16`, `-`, `Jumbo`-context, etc.
Keep it as `text`.

## 1. Data model — Supabase

Global reference data, in the same class as `tcg_*` / `graded_*`: **not** `store_id`-scoped.
Public-read RLS mirroring the `tcg_*` pattern; writes only via the service role.

```sql
create table public.cameo_subjects (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('pokemon','trainer')),
  ndex        int,            -- National Dex number; null for trainers
  region      text,           -- e.g. 'KANTO'; null for pokemon
  name        text not null,  -- 'Pikachu', 'Red' — searched via ilike
  card_count  int not null default 0,  -- denormalized for list display
  unique (kind, name)
);

create table public.cameo_cards (
  id           uuid primary key default gen_random_uuid(),
  subject_id   uuid not null references public.cameo_subjects(id) on delete cascade,
  card_name    text not null,
  set_name     text not null,
  card_number  text,          -- TEXT: '2nd', 'TG16', '-'
  notes        text,
  generation   text not null  -- source sheet label: 'Gen 1'..'Gen 9' | 'Trainers'
);
create index cameo_cards_subject_id_idx on public.cameo_cards(subject_id);
```

RLS: enable on both, `for select using (true)` public read (mirror the loop in
`20260422120000_tcgcsv_pokemon_and_graded.sql`). No write policies — the seed script uses the
service role, which bypasses RLS.

Schema lands in a new timestamped migration under `supabase/migrations/`.

## 2. Ingestion — re-runnable Deno seed script

`scripts/seed-cameos.ts` (the repo already ships Deno scripts: `validate-csv.ts`, `audit-aliases.ts`).

- Reads all 10 CSV files from `cameo-data/`.
- Parses with a **pure** `parseCameoSheet(rows, generationLabel)` function implementing the two-level
  forward-fill above. This function is unit-tested in isolation (the forward-fill is the bug-prone part).
- Aggregates into subjects (with `card_count`) and cards.
- Writes to Supabase via the service-role client:
  - upsert `cameo_subjects` on `(kind, name)`;
  - **clear + re-insert** `cameo_cards` (the script wholly owns this reference data, so a full
    rebuild each run is deterministic and avoids duplicate-row drift on reprints).
- Idempotent: running twice yields the same rows.

Data lives in this script, **not** in a migration (migrations are DDL only — rule #3).

## 3. Read API — `CameoRepository` (PostgREST direct)

New repo under `ios/slabbist/slabbist/Core/Data/Repositories/`, following the
`StoreMemberRepository` direct-`from().select()` pattern (rule #4 — repos are the only layer talking
to Supabase). No edge function: this is a plain reference read, not the aggregator/proxy hero-flow
that edge functions are reserved for (rule #6).

- `searchSubjects(_ query: String) async throws -> [CameoSubject]` — `ilike` on `name`
  (empty query returns all), ordered by `ndex` then `name`.
- `cards(forSubject id: UUID) async throws -> [CameoCard]` — cards for one subject, ordered by
  generation / set.

Swift models `CameoSubject` and `CameoCard` are `Decodable`; verified with a decode round-trip
against a real PostgREST response shape (live-decode per project convention), not just a hand-mocked JSON.

## 4. TCGplayer affiliate search link

Extend `Core/Utilities/TCGPlayerAffiliateLink.swift` with a sibling builder:

```swift
static func searchLink(query: String, subId: String,
                       baseURL: String = AppEnvironment.tcgplayerImpactBaseURL) -> URL?
```

Destination: `https://www.tcgplayer.com/search/pokemon/product?productLineName=pokemon&q=<encoded>`
where `<query>` is `"<cardName> <set>"`. Percent-encoded into the same impact.com base via the
existing `u=` + `subId1=` mechanism (`subId = "cameo"`). Falls back to the raw search URL when no
base URL is configured — same graceful path as the product link.

Add a thin `TCGPlayerSearchLinkButton` (or generalize the existing button to accept a prebuilt URL)
reusing the gold-outlined CTA style and the affiliate-disclosure caption already in
`TCGPlayerLinkButton`.

Unit test: `searchLink` produces the correct encoded destination, base-wrap, and `subId1`.

## 5. iOS easter egg + secret screen

- **Asset:** add `psyduck.png` as a new imageset in `Assets.xcassets`.
- **`PsyduckPeekOverlay`** — a small (~64pt) Psyduck `Image`, pinned to the **trailing edge, lower
  third**, offset ~half its width off-screen so only part "peeks." Added as a `ZStack(alignment:)`
  overlay wrapping the `TabView` in `RootTabView` so it sits over **every tab**. Only the duck is
  hit-testable; the rest of the overlay passes touches through. Tapping it presents a
  `.fullScreenCover`.
- **`CameoSecretView`** (the cover) — dark+gold per `.impeccable.md` (AppColor / Spacing / Radius /
  SlabFont, WCAG 2.2 AA). Contains a `KickerLabel` ("Cameo Dex"), a search field bound to
  `searchSubjects`, and a list of subjects rendered as `name · #ndex · card count`. Its own
  `NavigationStack` drives subject → detail. An `X` dismisses the cover. **No tab bar** is present.
- **`CameoSubjectDetailView`** — lists the selected subject's cards (`card_name`, `set_name`,
  `card_number`, `notes`), each row carrying the TCGplayer search-affiliate button from §4.

All UI uses existing design-system primitives; the mockup IA language ("vault"/"portfolio") must not
leak in (rule #8).

## Testing

- **Deno test** (`Deno.test`, colocated with the script — `scripts/` is Deno, not Bun/Vitest):
  `parseCameoSheet` — a known cameo expands to the exact expected card rows, including a reprint
  (blank `Card name`) and a subject boundary. Encodes *why* (forward-fill correctness), not just a
  value (rule #9).
- **`supabase/tests/rls_cameo.sql`**: anon role can `select` from both tables; anon `insert` is denied.
- **Swift:** `searchLink` encoding test; `CameoRepository` Decodable round-trip.

## Plan phasing

1. Migration (`cameo_subjects` / `cameo_cards` + RLS) → verify with `rls_cameo.sql`.
2. `seed-cameos.ts` + `parseCameoSheet` unit test → run against Supabase, spot-check counts.
3. `searchLink` util + `TCGPlayerSearchLinkButton` + util test.
4. `CameoRepository` + `CameoSubject`/`CameoCard` models + decode round-trip.
5. `psyduck.png` asset + `PsyduckPeekOverlay` in `RootTabView` + `CameoSecretView` +
   `CameoSubjectDetailView`.

## Out of scope

- Product-ID matching to `tcg_products` (deliberately deferred — search URLs only).
- Offline caching of cameo data (the secret screen is network-gated; acceptable for an easter egg).
- Any change to product IA / tab navigation (the Cameo Dex is reachable only via the hidden Psyduck).
