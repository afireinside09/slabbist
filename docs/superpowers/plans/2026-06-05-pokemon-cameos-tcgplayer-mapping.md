# Pokemon Cameos — Images, Card Detail, TCGplayer Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the hidden "Cameo Dex" to "Pokemon Cameos", give every cameo card a persisted 1:1 mapping to a TCGplayer product, and let the user tap a card to a detail page showing its image and a product-specific affiliate link.

**Architecture:** Add a nullable `tcgplayer_product_id` FK column on `cameo_cards → tcg_products`. The iOS client embeds `tcg_products(product_id, image_url)` via PostgREST (both tables are already public-read). A conservative SQL pass pre-seeds high-confidence matches; the user hand-corrects the rest in Supabase. The CSV seed script is converted from destructive delete+reinsert to deterministic-id upsert so re-seeds preserve the user's manual mappings.

**Tech Stack:** Postgres 17 (Supabase migrations + psql), Deno 2 (seed script), SwiftUI + supabase-swift (PostgREST), Swift Testing.

---

## File Structure

- `supabase/migrations/20260605160000_cameo_tcgplayer_mapping.sql` — **create**: add the FK column + index.
- `scripts/match-cameo-products.sql` — **create**: re-runnable, idempotent best-guess matcher (fills NULLs only).
- `scripts/seed-cameos.ts` — **modify**: deterministic ids + upsert (non-destructive), one-time rebuild behind a flag.
- `ios/slabbist/slabbist/Core/Data/DTOs/CameoCardDTO.swift` — **modify**: add embedded `CameoCardProductDTO`.
- `ios/slabbist/slabbist/Core/Data/Repositories/CameoRepository.swift` — **modify**: embed the product in the cards select.
- `ios/slabbist/slabbist/Features/Cameo/CameoSubjectDetailView.swift` — **modify**: thumbnail + tap-through rows; navigationDestination.
- `ios/slabbist/slabbist/Features/Cameo/CameoCardDetailView.swift` — **create**: image + metadata + affiliate CTA.
- `ios/slabbist/slabbist/Features/Cameo/CameoSecretView.swift` — **modify**: rename "Cameo Dex" → "Pokemon Cameos".
- `ios/slabbist/slabbist/slabbistTests/Core/CameoDTODecodeTests.swift` — **modify**: decode the embedded product (mapped + null).

---

## Task 1: Rename "Cameo Dex" → "Pokemon Cameos"

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Cameo/CameoSecretView.swift:18,52` (and doc comment line 3)

- [ ] **Step 1: Change the visible kicker title**

In `CameoSecretView.swift`, line 18:

```swift
                    KickerLabel("Pokemon Cameos")
```

- [ ] **Step 2: Change the close-button accessibility label**

Line 52:

```swift
                        .accessibilityLabel("Close Pokemon Cameos")
```

- [ ] **Step 3: Update the doc comment for consistency**

Line 3 — change `The hidden "Cameo Dex":` to:

```swift
/// The hidden "Pokemon Cameos" page: a full-screen, tab-less cover reached only via the
```

- [ ] **Step 4: Verify no remaining user-facing "Cameo Dex" strings in app code**

Run: `grep -rn "Cameo Dex" ios/slabbist/slabbist/`
Expected: no matches (docs/ and plan files may still mention it — that's fine).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Cameo/CameoSecretView.swift
git commit -m "feat(cameo): rename Cameo Dex to Pokemon Cameos"
```

---

## Task 2: Migration — add `tcgplayer_product_id` to `cameo_cards`

**Files:**
- Create: `supabase/migrations/20260605160000_cameo_tcgplayer_mapping.sql`

- [ ] **Step 1: Write the migration**

```sql
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
```

- [ ] **Step 2: Apply the migration**

Run: `supabase db push`
Expected: applies `20260605160000_cameo_tcgplayer_mapping.sql` with no error.
(If it errors `relation/column already exists`, the `if not exists` guards make it a no-op; reconcile the ledger per CLAUDE.md by INSERTing into `supabase_migrations.schema_migrations` instead of re-running DDL.)

- [ ] **Step 3: Verify the column exists**

Run:
```bash
psql "$DATABASE_URL" -c "\d public.cameo_cards" | grep tcgplayer_product_id
```
Expected: shows `tcgplayer_product_id | integer` with the FK.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260605160000_cameo_tcgplayer_mapping.sql
git commit -m "feat(cameo): add tcgplayer_product_id FK on cameo_cards"
```

---

## Task 3: Non-destructive seed (deterministic ids + upsert)

Converts `scripts/seed-cameos.ts` from delete-all+reinsert (random UUIDs) to deterministic-id upsert, so re-seeds preserve the manual `tcgplayer_product_id` column. A one-time rebuild flag handles the transition from the existing random-id rows.

**Files:**
- Modify: `scripts/seed-cameos.ts`

- [ ] **Step 1: Add a deterministic-UUID helper and namespace**

At the top of `scripts/seed-cameos.ts`, after the existing imports, add:

```ts
// std@0.224.0 signature: generate(namespace: string, data: Uint8Array): Promise<string>.
// (The object form `{ value, namespace }` is the newer JSR @std/uuid API — do NOT
// use it here; this script pins deno.land/std@0.224.0.)
import { generate as uuidv5 } from "https://deno.land/std@0.224.0/uuid/v5.ts";

// Fixed namespace so the same natural key always yields the same UUID across
// re-seeds. This is what makes the upsert (and thus mapping preservation) work.
const CAMEO_NS = "7c3a1f64-2b9e-4d8a-9c01-5e6f8a2b3c4d";
const enc = new TextEncoder();

const subjectId = (kind: string, name: string) =>
  uuidv5(CAMEO_NS, enc.encode(`subject|${kind}|${name}`));

const cardKey = (
  kind: string, name: string,
  cardName: string, setName: string, cardNumber: string, generation: string, notes: string,
) => `card|${kind}|${name}|${cardName}|${setName}|${cardNumber}|${generation}|${notes}`;

const cardId = (key: string) => uuidv5(CAMEO_NS, enc.encode(key));
```

- [ ] **Step 2: Replace the payload-building block with deterministic ids**

Replace the existing `// ── Build insert payloads ...` block (the `subjectRows` and `cardRows` definitions) with:

```ts
// ── Build upsert payloads (deterministic UUIDs link cards → subjects) ─────────
const subjectRows = await Promise.all(allSubjects.map(async (s) => ({
  id: await subjectId(s.kind, s.name),
  kind: s.kind,
  ndex: s.ndex,
  region: s.region,
  name: s.name,
  card_count: s.cards.length,
})));

const cardRowsNested = await Promise.all(allSubjects.map(async (s, i) => {
  const sid = subjectRows[i].id;
  return Promise.all(s.cards.map(async (c) => {
    const key = cardKey(s.kind, s.name, c.cardName, c.setName, c.cardNumber || "", c.generation, c.notes || "");
    return {
      id: await cardId(key),
      subject_id: sid,
      card_name: c.cardName,
      set_name: c.setName,
      card_number: c.cardNumber || null,
      notes: c.notes || null,
      generation: c.generation,
      // NOTE: tcgplayer_product_id intentionally omitted — upsert leaves the
      // user's manual mapping untouched.
    };
  }));
}));
const cardRows = cardRowsNested.flat();

// Fail loud if the natural key collides (would silently merge two cards).
const seen = new Set<string>();
const dupes = cardRows.filter((r) => seen.size === seen.add(r.id).size);
if (dupes.length > 0) {
  console.error(`✗ ${dupes.length} cards share a deterministic id (natural-key collision).`);
  console.error("  Add a discriminator to cardKey() before re-running.");
  Deno.exit(1);
}
```

- [ ] **Step 3: Replace the destructive rebuild block with upsert**

Replace the `// ── Rebuild ──` block (the DELETE + two `chunkedInsert` calls + final logs) with:

```ts
// ── Upsert ───────────────────────────────────────────────────────────────────
// Steady state: upsert by deterministic id. Content columns refresh; the
// tcgplayer_product_id mapping is preserved (not in the payload).
//
// One-time transition: existing rows were seeded with RANDOM ids, so the first
// deterministic run would duplicate them. Run once with CAMEO_REBUILD=1 to clear
// the old rows first (safe — tcgplayer_product_id is entirely NULL until then).
if (Deno.env.get("CAMEO_REBUILD") === "1") {
  await rest("cameo_subjects?kind=in.(pokemon,trainer)", { method: "DELETE", headers: { Prefer: "return=minimal" } });
  console.log("CAMEO_REBUILD=1 → cleared existing cameo data");
}

await chunkedUpsert("cameo_subjects", subjectRows);
await chunkedUpsert("cameo_cards", cardRows);
console.log(`Upserted ${subjectRows.length} subjects, ${cardRows.length} cards`);
console.log("✓ Done");
```

- [ ] **Step 4: Add the `chunkedUpsert` helper**

Next to the existing `chunkedInsert` function, add:

```ts
async function chunkedUpsert(table: string, rows: unknown[]) {
  const SIZE = 500;
  for (let i = 0; i < rows.length; i += SIZE) {
    await rest(table, {
      method: "POST",
      // merge-duplicates → INSERT ... ON CONFLICT (pk) DO UPDATE SET <payload cols>.
      // Columns absent from the payload (tcgplayer_product_id) are left as-is.
      headers: { Prefer: "return=minimal,resolution=merge-duplicates" },
      body: JSON.stringify(rows.slice(i, i + SIZE)),
    });
  }
}
```

`chunkedInsert` is now unused — delete it (it was only called by the block replaced in Step 3).

- [ ] **Step 5: Typecheck the script**

Run: `cd scripts && deno check seed-cameos.ts` (or `deno check scripts/seed-cameos.ts` from repo root)
Expected: no type errors.

- [ ] **Step 6: One-time transition run (clears random-id rows, seeds deterministic)**

Run (inside a direnv-allowed shell so `SUPABASE_SECRET_KEY` is set):
```bash
CAMEO_REBUILD=1 ./scripts/seed-cameos.ts
```
Expected tail:
```
Upserted 1013 subjects, 3945 cards
✓ Done
```

- [ ] **Step 7: Verify idempotent re-run preserves a manual mapping**

Set one mapping, re-seed WITHOUT the rebuild flag, confirm it survived:
```bash
# pick any real product_id and any card id, set it
psql "$DATABASE_URL" -c "update public.cameo_cards set tcgplayer_product_id = (select product_id from public.tcg_products limit 1) where id = (select id from public.cameo_cards limit 1) returning id, tcgplayer_product_id;"
# re-seed (no rebuild)
./scripts/seed-cameos.ts
# confirm still mapped
psql "$DATABASE_URL" -c "select count(*) from public.cameo_cards where tcgplayer_product_id is not null;"
```
Expected: count is still ≥ 1 (the manual mapping survived the re-seed).

- [ ] **Step 8: Commit**

```bash
git add scripts/seed-cameos.ts
git commit -m "feat(cameo): non-destructive seed via deterministic ids + upsert

Preserves manual tcgplayer_product_id mappings across re-seeds. One-time
transition from random ids handled by CAMEO_REBUILD=1."
```

---

## Task 4: Auto-seed match pass (re-runnable SQL)

**Files:**
- Create: `scripts/match-cameo-products.sql`

- [ ] **Step 1: Write the matcher**

```sql
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
```

- [ ] **Step 2: Run the matcher**

Run: `psql "$DATABASE_URL" -f scripts/match-cameo-products.sql`
Expected: ends with a `NOTICE: cameo_cards mapped: <N>, still unmapped: <M>` line where `N + M = 3945`. (N>0 confirms some confident matches landed; M>0 is expected — the rest are for manual correction.)

- [ ] **Step 3: Spot-check a few matches are correct**

Run:
```bash
psql "$DATABASE_URL" -c "select c.card_name, c.set_name, c.card_number, p.name, p.product_id from public.cameo_cards c join public.tcg_products p on p.product_id = c.tcgplayer_product_id limit 10;"
```
Expected: the cameo card name/set/number visibly correspond to the tcg product. (If many look wrong, tighten the matcher before relying on it — better to under-match.)

- [ ] **Step 4: Commit**

```bash
git add scripts/match-cameo-products.sql
git commit -m "feat(cameo): conservative SQL pass to pre-seed tcgplayer_product_id"
```

---

## Task 5: iOS DTO — embed the TCGplayer product

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Data/DTOs/CameoCardDTO.swift`
- Test: `ios/slabbist/slabbist/slabbistTests/Core/CameoDTODecodeTests.swift`

- [ ] **Step 1: Write the failing decode test**

In `CameoDTODecodeTests.swift`, add inside the `CameoDTODecodeTests` struct:

```swift
    // Why: the card list/detail render image + product affiliate link straight
    // from the PostgREST embed `tcg_products(product_id, image_url)`, which comes
    // back as a nested object for mapped rows and null for unmapped rows. Both
    // shapes must decode or cards silently lose their image/link.
    @Test("card decodes embedded tcg_products (mapped) and null (unmapped)")
    func cardEmbeddedProduct() throws {
        let json = """
        [
          {"id":"44444444-4444-4444-4444-444444444444","subject_id":"22222222-2222-2222-2222-222222222222",
           "card_name":"Pikachu","set_name":"Base Set","card_number":"58","notes":null,"generation":"Gen 1",
           "tcg_products":{"product_id":42445,"image_url":"https://img/42445.jpg"}},
          {"id":"55555555-5555-5555-5555-555555555555","subject_id":"22222222-2222-2222-2222-222222222222",
           "card_name":"Pokémon March","set_name":"Neo Genesis","card_number":null,"notes":null,"generation":"Gen 2",
           "tcg_products":null}
        ]
        """.data(using: .utf8)!
        let rows = try JSONDecoder().decode([CameoCardDTO].self, from: json)
        #expect(rows[0].tcgProduct?.productId == 42445)
        #expect(rows[0].tcgProduct?.imageURL == "https://img/42445.jpg")
        #expect(rows[1].tcgProduct == nil)
    }
```

- [ ] **Step 2: Run the test, verify it fails to compile**

Run:
```bash
xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:slabbistTests/CameoDTODecodeTests/cardEmbeddedProduct 2>&1 | tail -20
```
Expected: build failure — `value of type 'CameoCardDTO' has no member 'tcgProduct'`.

- [ ] **Step 3: Add the embedded product to the DTO**

In `CameoCardDTO.swift`, add the property and nested type, and the coding key:

```swift
nonisolated struct CameoCardDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: UUID
    let subjectId: UUID
    let cardName: String
    let setName: String
    let cardNumber: String?
    let notes: String?
    let generation: String
    /// PostgREST embed of the mapped TCGplayer product (`tcg_products`); nil when
    /// the card has no `tcgplayer_product_id` yet.
    let tcgProduct: CameoCardProductDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case subjectId  = "subject_id"
        case cardName   = "card_name"
        case setName    = "set_name"
        case cardNumber = "card_number"
        case notes, generation
        case tcgProduct = "tcg_products"
    }
}

/// The subset of `public.tcg_products` embedded alongside a cameo card — enough
/// to render the image and a product-specific affiliate link.
nonisolated struct CameoCardProductDTO: Codable, Sendable, Equatable, Hashable {
    let productId: Int
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case imageURL  = "image_url"
    }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run:
```bash
xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:slabbistTests/CameoDTODecodeTests 2>&1 | tail -20
```
Expected: `cardEmbeddedProduct` and the existing two cameo decode tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/DTOs/CameoCardDTO.swift ios/slabbist/slabbist/slabbistTests/Core/CameoDTODecodeTests.swift
git commit -m "feat(cameo): decode embedded tcg_products on CameoCardDTO"
```

---

## Task 6: Repository — embed the product in the cards query

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Data/Repositories/CameoRepository.swift:39-50`

- [ ] **Step 1: Embed `tcg_products` in the select**

In `cards(forSubject:)`, change `.query().select()` to embed the product:

```swift
    func cards(forSubject id: UUID) async throws -> [CameoCardDTO] {
        do {
            return try await cards.query()
                .select("*, tcg_products(product_id, image_url)")
                .eq("subject_id", value: id.uuidString)
                .order("generation", ascending: true)
                .order("set_name", ascending: true)
                .execute()
                .value
        } catch {
            throw SupabaseError.map(error)
        }
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/Repositories/CameoRepository.swift
git commit -m "feat(cameo): embed tcg_products(product_id,image_url) in cards query"
```

---

## Task 7: Card detail page

**Files:**
- Create: `ios/slabbist/slabbist/Features/Cameo/CameoCardDetailView.swift`

- [ ] **Step 1: Create the detail view**

```swift
import SwiftUI

/// Detail page for a single cameo card: the card image (when mapped to a
/// TCGplayer product) plus its metadata and a product-specific affiliate link.
/// Falls back to a search link for cards not yet mapped.
struct CameoCardDetailView: View {
    let card: CameoCardDTO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let urlString = card.tcgProduct?.imageURL, let url = URL(string: urlString) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .empty:
                            ProgressView().tint(AppColor.gold).frame(maxWidth: .infinity, minHeight: 280)
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(card.cardName).slabRowTitle()
                    Text("\(card.setName)\(card.cardNumber.map { " · #\($0)" } ?? "")")
                        .font(SlabFont.mono(size: 13))
                        .foregroundStyle(AppColor.dim)
                    if let notes = card.notes, !notes.isEmpty {
                        Text(notes)
                            .font(SlabFont.sans(size: 12))
                            .foregroundStyle(AppColor.dim)
                    }
                }

                if let productId = card.tcgProduct?.productId, productId > 0 {
                    TCGPlayerLinkButton(productId: productId, subId: "cameo")
                } else {
                    TCGPlayerSearchLinkButton(query: "\(card.cardName) \(card.setName)")
                }
            }
            .padding(Spacing.m)
        }
        .background(AppColor.ink)
        .navigationTitle(card.cardName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
            .fill(AppColor.surface)
            .frame(maxWidth: .infinity, minHeight: 280)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(AppColor.dim)
            )
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Cameo/CameoCardDetailView.swift
git commit -m "feat(cameo): CameoCardDetailView — image + product affiliate link"
```

---

## Task 8: Card list — thumbnails + tap-through

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Cameo/CameoSubjectDetailView.swift`

- [ ] **Step 1: Replace the card row body with a thumbnail + tap-through NavigationLink**

Replace the `ForEach(cards) { card in ... }` block (the `VStack` that currently ends with `TCGPlayerSearchLinkButton`) with:

```swift
                    ForEach(cards) { card in
                        NavigationLink(value: card) {
                            HStack(alignment: .top, spacing: Spacing.m) {
                                thumbnail(for: card)
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(card.cardName).slabRowTitle()
                                    Text("\(card.setName)\(card.cardNumber.map { " · #\($0)" } ?? "")")
                                        .font(SlabFont.mono(size: 13))
                                        .foregroundStyle(AppColor.dim)
                                    if let notes = card.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(SlabFont.sans(size: 12))
                                            .foregroundStyle(AppColor.dim)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(Spacing.m)
                            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
```

- [ ] **Step 2: Add the thumbnail helper and the navigation destination**

Add a `thumbnail(for:)` helper to the view (e.g. just after `body`), and attach the destination to the `ScrollView`.

Helper:

```swift
    @ViewBuilder
    private func thumbnail(for card: CameoCardDTO) -> some View {
        let size = CGSize(width: 48, height: 67) // ~card aspect
        if let urlString = card.tcgProduct?.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        } else {
            thumbnailPlaceholder
                .frame(width: size.width, height: size.height)
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
            .fill(AppColor.ink)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColor.dim)
            )
    }
```

Attach the destination — add this modifier to the `ScrollView` (alongside `.background(AppColor.ink)` / `.navigationTitle(...)`):

```swift
        .navigationDestination(for: CameoCardDTO.self) { card in
            CameoCardDetailView(card: card)
        }
```

- [ ] **Step 3: Confirm `Radius.s` exists (used by the thumbnail)**

Run: `grep -rn "static let s" ios/slabbist/slabbist/Core/DesignSystem/ | grep -i radius`
Expected: a `Radius.s` token exists. If it does NOT, substitute `Radius.l` in Step 2's `cornerRadius:` calls.

- [ ] **Step 4: Build**

Run:
```bash
xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Cameo/CameoSubjectDetailView.swift
git commit -m "feat(cameo): card list thumbnails + tap-through to card detail"
```

---

## Task 9: Full verification

- [ ] **Step 1: Run the full cameo test suite**

Run:
```bash
xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:slabbistTests/CameoDTODecodeTests 2>&1 | tail -20
```
Expected: all cameo decode tests PASS. (The wider suite has known-red baselines per project memory — do not block on those.)

- [ ] **Step 2: Manual smoke (real app)**

Launch the app (`/run` or Xcode). Tap the Psyduck easter egg → the page title reads **"Pokemon Cameos"**. Search a Pokémon with mapped cards (e.g. one you confirmed in Task 4 Step 3) → its cards show thumbnails. Tap a mapped card → detail page shows the large image + "View on TCGplayer" (opens an affiliate URL). Tap an unmapped card → no image + "Search on TCGplayer" fallback.

- [ ] **Step 3: Confirm affiliate routing**

On a mapped card's detail page, tap "View on TCGplayer". Expected: opens `partner.tcgplayer.com/...?subId1=cameo&u=<encoded tcgplayer.com/product/{id}>` (product page, not a search).

---

## Notes / out of scope

- No in-app mapping editor — the user corrects `tcgplayer_product_id` in the Supabase table editor.
- The seed does not prune cards removed from the CSV (additive in practice). If a homonym/natural-key collision ever appears, Task 3 Step 2's guard fails loud with instructions.
- `xcodebuild` simulator name: project memory notes the CLAUDE.md "iPhone 16 Pro" is stale (only 18.x). Use an installed iOS 26.x sim (e.g. iPhone 17 Pro); adjust the `-destination` if your installed sim differs.
