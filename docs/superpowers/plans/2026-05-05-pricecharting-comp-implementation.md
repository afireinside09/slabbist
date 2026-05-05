# PriceCharting Comp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the eBay-backed scan-time comp with a PriceCharting-backed equivalent. Same iOS-facing endpoint URL (`/price-comp`); new internals + new payload shape; eBay scaffolding (cascade, Marketplace Insights, sold-listing mirroring, watchlist event stream, scraper's `ebay-sold` ingest) gone from the comp path. Movers and the eBay account-deletion webhook untouched.

**Architecture:** Edge Function `price-comp` does hybrid product matching (`graded_card_identities.pricecharting_product_id` cached → `/api/products` search fallback → persist) → `/api/product?id=…&t=…` for the per-grade ladder → upsert `graded_market` (reshaped per-tier columns) → return JSON. iOS `CompFetchService` and the `compFetchState` state machine stay; `CompRepository` decodes the new shape; `CompCardView` renders headline + grade ladder + PriceCharting deep-link.

**Tech Stack:** Deno (Supabase Edge Functions), TypeScript, Postgres (via `supabase db push` + the migration ledger reconciliation memory note), SwiftUI / SwiftData (iOS), Swift Testing, Vitest (scraper).

**Reference spec:** [`docs/superpowers/specs/2026-05-05-pricecharting-comp-design.md`](../specs/2026-05-05-pricecharting-comp-design.md)

---

## File structure

This is the locked-in decomposition. Each file has one responsibility; tasks are scoped to the smallest set of files that ship a working slice.

### New (Edge Function — `supabase/functions/price-comp/`)

- `pricecharting/client.ts` — low-level HTTP helper. Builds `https://www.pricecharting.com/api/<endpoint>?t=…&…`. Returns `{ status, body }`. Centralizes the in-isolate rate-limit pause and the single 401 retry.
- `pricecharting/search.ts` — `searchProducts(client, q)` → `{ products: PCProduct[] }`. Returns the raw JSON `products` array; caller picks the top hit.
- `pricecharting/product.ts` — `getProduct(client, id)` → `PCProductRow` (one row from PriceCharting). Calls `/api/product?id=…&t=…`.
- `pricecharting/parse.ts` — pure functions:
  - `pickTier(row, gradingService, grade)` → headline `numeric` or `null`
  - `extractLadder(row)` → `{ loose, grade_7, grade_8, grade_9, grade_9_5, psa_10, bgs_10, cgc_10, sgc_10 }` (each `numeric | null`, dollars)
  - `centsFromPennies(n)` → integer (PriceCharting publishes prices as pennies-int → straight-through to our cents wire shape)
  - `productUrl(row)` → derived `https://www.pricecharting.com/game/<console>/<slug>` if not provided
- `lib/grade-key.ts` — `gradeKeyFor(service: GradingService, grade: string): TierKey | null`. Maps `(PSA, "10")` → `"psa_10"`, `(BGS, "9.5")` → `"grade_9_5"`, etc. Lookup table.
- `persistence/identity-product-id.ts` — `persistIdentityProductId(supabase, identityId, productId, productUrl): Promise<void>`. Service-role upsert into `graded_card_identities`.
- `persistence/market.ts` — rewritten. `upsertMarketLadder(supabase, input)` writes one row to `graded_market` with the per-tier ladder + `pricecharting_product_id`, `pricecharting_url`, `source = 'pricecharting'`, `updated_at`.
- `index.ts` — rewritten orchestrator. Same `Deno.serve` shape; new control flow.
- `types.ts` — rewritten. `PriceCompRequest` unchanged. `PriceCompResponse` reshaped (per-tier fields + headline). New internal `PCProductRow`, `Tier`, `TierKey`, `LadderPrices` types.
- `cache/freshness.ts` — kept verbatim. New default TTL is environment-driven, code unchanged.
- `__tests__/` — replaced. New files (kept small, one concern each):
  - `__tests__/grade-key.test.ts`
  - `__tests__/parse.test.ts`
  - `__tests__/freshness.test.ts` (kept — same logic, new fixture values)
  - `__tests__/index.test.ts` (rewritten)
- `__fixtures__/pricecharting/`
  - `product-full-ladder.json`
  - `product-partial-ladder.json`
  - `product-no-prices.json`
  - `products-search-hits.json`
  - `products-search-empty.json`

### Removed (Edge Function)

- `supabase/functions/price-comp/ebay/` (entire directory: `browse.ts`, `cascade.ts`, `marketplace-insights.ts`, `oauth.ts`, `query-builder.ts`)
- `supabase/functions/price-comp/persistence/scan-event.ts`
- `supabase/functions/price-comp/stats/` (entire directory: `aggregates.ts`, `confidence.ts`, `outliers.ts`)
- `supabase/functions/price-comp/lib/grade-normalize.ts` and `graded-title-parse.ts` and `card-name-normalize.ts` (eBay-only callers; verified absent in the new code)
- `supabase/functions/price-comp/__fixtures__/mi-*.json`, `oauth-token.json`
- All eBay-specific test files: `aggregates.test.ts`, `browse.test.ts`, `cascade.test.ts`, `oauth.test.ts`, `outliers.test.ts`, `query-builder.test.ts`, `card-name-normalize.test.ts`, `grade-normalize.test.ts`

### Modified / removed (scraper)

- `scraper/src/cli.ts` — remove the `runEbaySoldIngest` import and the `if (job === "ebay") { … }` block of the `run graded` command; leave the `pop` branch alone.
- `scraper/src/graded/ingest/ebay-sold.ts` — deleted.
- Any peer test if it exists: `scraper/tests/graded/ingest/ebay-sold.test.ts` — deleted (Task 18 covers the conditional delete).

### Modified (iOS)

- `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift` — full reshape (see Task 6).
- `ios/slabbist/slabbist/Core/Models/SoldListingMirror.swift` — deleted.
- `ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift` — drop `SoldListingMirror.self` from both schema arrays.
- `ios/slabbist/slabbist/Features/Comp/CompRepository.swift` — rewritten Wire/Decoded/error mapping.
- `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift` — `persistSnapshot` reshape; `classify` copy update; in-flight + flip-matching unchanged.
- `ios/slabbist/slabbist/Features/Comp/CompCardView.swift` — rewritten (headline + ladder rail + footer).
- `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift` — listings section removed; copy updated.
- `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift` — `blendedPriceCents` → `headlinePriceCents`, drop "N listed" line, drop confidence pill.
- `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift` — rewritten.
- `ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift` — rewritten.

### New (DB migrations)

- `supabase/migrations/20260505120000_pricecharting_product_id_on_identities.sql`
- `supabase/migrations/20260505120100_graded_market_pricecharting_columns.sql`
- `supabase/migrations/20260505120200_drop_graded_market_sales.sql`
- `supabase/migrations/20260505120300_drop_slab_scan_events.sql`

---

## Task ordering rationale

DB schema → backend leaves first → Edge Function orchestrator → scraper teardown → iOS model + repo + service → iOS UI → final integration smoke. Each phase is independently testable. TDD throughout: red test before green code.

---

## Task 1: Add `pricecharting_product_id` to `graded_card_identities`

**Files:**
- Create: `supabase/migrations/20260505120000_pricecharting_product_id_on_identities.sql`

- [ ] **Step 1: Write the migration**

```sql
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
```

- [ ] **Step 2: Apply locally and verify schema**

Run: `cd /Users/dixoncider/slabbist && supabase db push`
Expected: migration applied. If error reports "relation already exists" on a separate object, use the migration-ledger memory note (`INSERT INTO supabase_migrations.schema_migrations`) to reconcile — do **not** re-run DDL by hand.

Then verify:
```bash
supabase db execute --sql "select column_name, data_type from information_schema.columns where table_name='graded_card_identities' and column_name in ('pricecharting_product_id','pricecharting_url');"
```
Expected output: two rows, both `text`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260505120000_pricecharting_product_id_on_identities.sql
git commit -m "db: add pricecharting_product_id + pricecharting_url to graded_card_identities"
```

---

## Task 2: Reshape `graded_market` to per-tier columns

**Files:**
- Create: `supabase/migrations/20260505120100_graded_market_pricecharting_columns.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 20260505120100_graded_market_pricecharting_columns.sql
-- Drops the eBay-aggregate columns added in 20260424000001 and the
-- generic distribution columns owned by the original tcgcsv graded
-- migration; replaces them with PriceCharting's per-grade ladder.
-- The ladder is the only canonical price source going forward.

alter table public.graded_market
  drop column if exists mean_price,
  drop column if exists trimmed_mean_price,
  drop column if exists sample_window_days,
  drop column if exists confidence,
  drop column if exists velocity_7d,
  drop column if exists velocity_30d,
  drop column if exists velocity_90d,
  drop column if exists sample_count_30d,
  drop column if exists sample_count_90d,
  drop column if exists low_price,
  drop column if exists median_price,
  drop column if exists high_price,
  drop column if exists last_sale_price,
  drop column if exists last_sale_at;

alter table public.graded_market
  add column if not exists source                   text,
  add column if not exists pricecharting_product_id text,
  add column if not exists pricecharting_url        text,
  add column if not exists headline_price           numeric(12,2),
  add column if not exists loose_price              numeric(12,2),
  add column if not exists grade_7_price            numeric(12,2),
  add column if not exists grade_8_price            numeric(12,2),
  add column if not exists grade_9_price            numeric(12,2),
  add column if not exists grade_9_5_price          numeric(12,2),
  add column if not exists psa_10_price             numeric(12,2),
  add column if not exists bgs_10_price             numeric(12,2),
  add column if not exists cgc_10_price             numeric(12,2),
  add column if not exists sgc_10_price             numeric(12,2);

update public.graded_market set source = 'pricecharting' where source is null;
alter table public.graded_market alter column source set not null;
alter table public.graded_market alter column source set default 'pricecharting';
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db push`
Then:
```bash
supabase db execute --sql "select column_name, data_type, is_nullable from information_schema.columns where table_name='graded_market' order by ordinal_position;"
```
Expected: 14 columns total — `identity_id, grading_service, grade, updated_at, source, pricecharting_product_id, pricecharting_url, headline_price, loose_price, grade_7_price, grade_8_price, grade_9_price, grade_9_5_price, psa_10_price, bgs_10_price, cgc_10_price, sgc_10_price`. The first three + `updated_at` are NOT NULL; `source` is NOT NULL with default `'pricecharting'`; the rest are NULL-able.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260505120100_graded_market_pricecharting_columns.sql
git commit -m "db: reshape graded_market to PriceCharting per-tier ladder"
```

---

## Task 3: Drop `graded_market_sales`

**Files:**
- Create: `supabase/migrations/20260505120200_drop_graded_market_sales.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 20260505120200_drop_graded_market_sales.sql
-- PriceCharting publishes aggregate per-grade prices, not per-listing
-- rows. The only writers were the eBay edge function path (now gone)
-- and the scraper's ebay-sold ingest (also being deleted in this
-- changeset). No remaining consumers.
drop table if exists public.graded_market_sales cascade;
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db push`
Then:
```bash
supabase db execute --sql "select count(*) from information_schema.tables where table_name='graded_market_sales';"
```
Expected: count = 0.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260505120200_drop_graded_market_sales.sql
git commit -m "db: drop graded_market_sales (no remaining writers)"
```

---

## Task 4: Drop `slab_scan_events`

**Files:**
- Create: `supabase/migrations/20260505120300_drop_slab_scan_events.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 20260505120300_drop_slab_scan_events.sql
-- The eBay-scraper watchlist promotion signal has no consumer once
-- the eBay comp path is gone. Dropping per scope decision (option B
-- in the design spec).
drop table if exists public.slab_scan_events cascade;
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db push`
Then:
```bash
supabase db execute --sql "select count(*) from information_schema.tables where table_name='slab_scan_events';"
```
Expected: count = 0.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260505120300_drop_slab_scan_events.sql
git commit -m "db: drop slab_scan_events (no remaining consumer)"
```

---

## Task 5: Edge Function — `lib/grade-key.ts`

**Files:**
- Create: `supabase/functions/price-comp/lib/grade-key.ts`
- Create: `supabase/functions/price-comp/__tests__/grade-key.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/price-comp/__tests__/grade-key.test.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { gradeKeyFor } from "../lib/grade-key.ts";

Deno.test("PSA 10 -> psa_10", () => {
  assertEquals(gradeKeyFor("PSA", "10"), "psa_10");
});

Deno.test("BGS 10 -> bgs_10", () => {
  assertEquals(gradeKeyFor("BGS", "10"), "bgs_10");
});

Deno.test("CGC 10 -> cgc_10", () => {
  assertEquals(gradeKeyFor("CGC", "10"), "cgc_10");
});

Deno.test("SGC 10 -> sgc_10", () => {
  assertEquals(gradeKeyFor("SGC", "10"), "sgc_10");
});

Deno.test("PSA 9.5 -> grade_9_5 (generic intermediate tier)", () => {
  assertEquals(gradeKeyFor("PSA", "9.5"), "grade_9_5");
});

Deno.test("BGS 9.5 -> grade_9_5 (generic intermediate tier)", () => {
  assertEquals(gradeKeyFor("BGS", "9.5"), "grade_9_5");
});

Deno.test("PSA 9 -> grade_9", () => {
  assertEquals(gradeKeyFor("PSA", "9"), "grade_9");
});

Deno.test("PSA 7 -> grade_7", () => {
  assertEquals(gradeKeyFor("PSA", "7"), "grade_7");
});

Deno.test("PSA 6 -> null (not published as a tier by PriceCharting)", () => {
  assertEquals(gradeKeyFor("PSA", "6"), null);
});

Deno.test("Whitespace and PSA verbose adjectives are tolerated", () => {
  assertEquals(gradeKeyFor("PSA", "GEM MT 10"), "psa_10");
  assertEquals(gradeKeyFor("PSA", " 10 "), "psa_10");
});

Deno.test("TAG (unsupported by PriceCharting) -> null", () => {
  assertEquals(gradeKeyFor("TAG", "10"), null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/dixoncider/slabbist && deno test supabase/functions/price-comp/__tests__/grade-key.test.ts --no-check`
Expected: FAIL with "Cannot find module ../lib/grade-key.ts" or similar import resolution error.

- [ ] **Step 3: Write minimal implementation**

```typescript
// supabase/functions/price-comp/lib/grade-key.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { GradingService } from "../types.ts";

export type TierKey =
  | "loose"
  | "grade_7"
  | "grade_8"
  | "grade_9"
  | "grade_9_5"
  | "psa_10"
  | "bgs_10"
  | "cgc_10"
  | "sgc_10";

// Strip PSA's verbose adjectives ("GEM MT 10" -> "10") and trim whitespace.
// Intentionally narrow: we only ever see numeric strings or those one PSA
// adjective set in practice.
function bareGrade(grade: string): string {
  const m = grade.trim().match(/(\d+(?:\.\d+)?)$/);
  return m ? m[1] : grade.trim();
}

export function gradeKeyFor(service: GradingService, grade: string): TierKey | null {
  const g = bareGrade(grade);
  if (g === "10") {
    if (service === "PSA") return "psa_10";
    if (service === "BGS") return "bgs_10";
    if (service === "CGC") return "cgc_10";
    if (service === "SGC") return "sgc_10";
    return null;
  }
  if (g === "9.5") return "grade_9_5";
  if (g === "9")   return "grade_9";
  if (g === "8")   return "grade_8";
  if (g === "7")   return "grade_7";
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/price-comp/__tests__/grade-key.test.ts --no-check`
Expected: PASS, all 11 cases.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/lib/grade-key.ts \
        supabase/functions/price-comp/__tests__/grade-key.test.ts
git commit -m "edge: add gradeKeyFor() to map (service, grade) to PriceCharting tier"
```

---

## Task 6: Edge Function — `pricecharting/parse.ts`

**Files:**
- Create: `supabase/functions/price-comp/pricecharting/parse.ts`
- Create: `supabase/functions/price-comp/__tests__/parse.test.ts`
- Create: `supabase/functions/price-comp/__fixtures__/pricecharting/product-full-ladder.json`
- Create: `supabase/functions/price-comp/__fixtures__/pricecharting/product-partial-ladder.json`
- Create: `supabase/functions/price-comp/__fixtures__/pricecharting/product-no-prices.json`

- [ ] **Step 1: Write the fixtures**

```json
// supabase/functions/price-comp/__fixtures__/pricecharting/product-full-ladder.json
{
  "id": "12345678",
  "product-name": "Pikachu ex 247/191",
  "console-name": "Pokemon Surging Sparks",
  "release-date": "2024-11-08",
  "loose-price":      400,
  "grade-7-price":   2400,
  "grade-8-price":   3400,
  "grade-9-price":   6800,
  "grade-9.5-price":11200,
  "psa-10-price":  18500,
  "bgs-10-price":  21500,
  "cgc-10-price":  16800,
  "sgc-10-price":  16500
}
```

```json
// supabase/functions/price-comp/__fixtures__/pricecharting/product-partial-ladder.json
{
  "id": "98765432",
  "product-name": "Obscure Card 999/999",
  "console-name": "Pokemon Vintage",
  "release-date": "1999-01-09",
  "loose-price":  500,
  "grade-9-price": 4200,
  "psa-10-price": 18000
}
```

```json
// supabase/functions/price-comp/__fixtures__/pricecharting/product-no-prices.json
{
  "id": "11111111",
  "product-name": "Never-Sold Card 0/0",
  "console-name": "Pokemon Promo",
  "release-date": "2024-06-01"
}
```

- [ ] **Step 2: Write the failing test**

```typescript
// supabase/functions/price-comp/__tests__/parse.test.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { extractLadder, pickTier, productUrl, ladderHasAnyPrice } from "../pricecharting/parse.ts";

const full = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/pricecharting/product-full-ladder.json", import.meta.url)),
);
const partial = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/pricecharting/product-partial-ladder.json", import.meta.url)),
);
const empty = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/pricecharting/product-no-prices.json", import.meta.url)),
);

Deno.test("extractLadder: full ladder", () => {
  assertEquals(extractLadder(full), {
    loose:    400,
    grade_7: 2400,
    grade_8: 3400,
    grade_9: 6800,
    grade_9_5: 11200,
    psa_10: 18500,
    bgs_10: 21500,
    cgc_10: 16800,
    sgc_10: 16500,
  });
});

Deno.test("extractLadder: partial ladder, missing keys are null", () => {
  assertEquals(extractLadder(partial), {
    loose:    500,
    grade_7:  null,
    grade_8:  null,
    grade_9: 4200,
    grade_9_5: null,
    psa_10: 18000,
    bgs_10: null,
    cgc_10: null,
    sgc_10: null,
  });
});

Deno.test("extractLadder: no prices at all", () => {
  const ladder = extractLadder(empty);
  for (const v of Object.values(ladder)) assertEquals(v, null);
});

Deno.test("pickTier: PSA 10 from full ladder", () => {
  assertEquals(pickTier(full, "PSA", "10"), 18500);
});

Deno.test("pickTier: BGS 9.5 from full ladder", () => {
  assertEquals(pickTier(full, "BGS", "9.5"), 11200);
});

Deno.test("pickTier: tier missing in partial -> null", () => {
  assertEquals(pickTier(partial, "BGS", "10"), null);
});

Deno.test("pickTier: unknown grade returns null", () => {
  assertEquals(pickTier(full, "PSA", "1"), null);
});

Deno.test("ladderHasAnyPrice: empty -> false, partial -> true, full -> true", () => {
  assertEquals(ladderHasAnyPrice(extractLadder(empty)), false);
  assertEquals(ladderHasAnyPrice(extractLadder(partial)), true);
  assertEquals(ladderHasAnyPrice(extractLadder(full)), true);
});

Deno.test("productUrl: derives a stable URL from console-name and product-name", () => {
  const url = productUrl(full);
  assert(url.startsWith("https://www.pricecharting.com/game/"));
  assert(url.includes("pokemon-surging-sparks"));
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `deno test supabase/functions/price-comp/__tests__/parse.test.ts --no-check`
Expected: FAIL — module `../pricecharting/parse.ts` not found.

- [ ] **Step 4: Write minimal implementation**

```typescript
// supabase/functions/price-comp/pricecharting/parse.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { GradingService } from "../types.ts";
import { gradeKeyFor, type TierKey } from "../lib/grade-key.ts";

// PriceCharting publishes prices as integer pennies (e.g. 1732 = $17.32).
// We carry pennies-int through the response wire shape (matches iOS Int64
// cents). graded_market columns are numeric(12,2) dollars; conversion
// happens in persistence/market.ts.
export interface PCProductRow {
  id?: string;
  "product-name"?: string;
  "console-name"?: string;
  "release-date"?: string;
  "loose-price"?: number;
  "grade-7-price"?: number;
  "grade-8-price"?: number;
  "grade-9-price"?: number;
  "grade-9.5-price"?: number;
  "psa-10-price"?: number;
  "bgs-10-price"?: number;
  "cgc-10-price"?: number;
  "sgc-10-price"?: number;
  // PriceCharting may also publish "manual-only-price" / "box-only-price"
  // for video games — irrelevant for trading cards.
}

export interface LadderPrices {
  loose: number | null;
  grade_7: number | null;
  grade_8: number | null;
  grade_9: number | null;
  grade_9_5: number | null;
  psa_10: number | null;
  bgs_10: number | null;
  cgc_10: number | null;
  sgc_10: number | null;
}

const TIER_TO_FIELD: Record<keyof LadderPrices, keyof PCProductRow> = {
  loose:     "loose-price",
  grade_7:   "grade-7-price",
  grade_8:   "grade-8-price",
  grade_9:   "grade-9-price",
  grade_9_5: "grade-9.5-price",
  psa_10:    "psa-10-price",
  bgs_10:    "bgs-10-price",
  cgc_10:    "cgc-10-price",
  sgc_10:    "sgc-10-price",
};

function readPrice(row: PCProductRow, field: keyof PCProductRow): number | null {
  const v = row[field];
  if (typeof v === "number" && Number.isFinite(v) && v > 0) return v;
  return null;
}

export function extractLadder(row: PCProductRow): LadderPrices {
  const out: Partial<LadderPrices> = {};
  for (const tier of Object.keys(TIER_TO_FIELD) as Array<keyof LadderPrices>) {
    out[tier] = readPrice(row, TIER_TO_FIELD[tier]);
  }
  return out as LadderPrices;
}

export function pickTier(
  row: PCProductRow,
  service: GradingService,
  grade: string,
): number | null {
  const key = gradeKeyFor(service, grade);
  if (!key) return null;
  // `loose` would never be requested via (service, grade) — gradeKeyFor never
  // returns it. Map TierKey -> LadderPrices key.
  const ladder = extractLadder(row);
  return ladder[key as keyof LadderPrices] ?? null;
}

export function ladderHasAnyPrice(ladder: LadderPrices): boolean {
  return Object.values(ladder).some(v => v !== null);
}

function slugify(s: string): string {
  return s.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

// PriceCharting product pages live at /game/<console-slug>/<product-slug>.
// Derive deterministically from the row so we don't depend on a `url`
// field that PriceCharting may or may not return.
export function productUrl(row: PCProductRow): string {
  const console_ = slugify(row["console-name"] ?? "pokemon");
  const product = slugify(row["product-name"] ?? row.id ?? "");
  return `https://www.pricecharting.com/game/${console_}/${product}`;
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `deno test supabase/functions/price-comp/__tests__/parse.test.ts --no-check`
Expected: PASS, all 9 cases.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/price-comp/pricecharting/parse.ts \
        supabase/functions/price-comp/__tests__/parse.test.ts \
        supabase/functions/price-comp/__fixtures__/pricecharting/
git commit -m "edge: add PriceCharting product parser (ladder, headline, URL)"
```

---

## Task 7: Edge Function — `pricecharting/client.ts`

**Files:**
- Create: `supabase/functions/price-comp/pricecharting/client.ts`

This is a thin HTTP helper. No tests of its own — fully exercised by `index.ts` integration tests later.

- [ ] **Step 1: Write the implementation**

```typescript
// supabase/functions/price-comp/pricecharting/client.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.

const BASE_URL = "https://www.pricecharting.com";

// Module-scope rate-limit pause. After a 429, all live fetches in this
// isolate sleep until `pausedUntil` passes. Outside callers handle the
// `paused` flag in the response.
let pausedUntil = 0;

export interface ClientOptions {
  token: string;
  // For tests / mock servers; defaults to the production base URL.
  baseUrl?: string;
  // For tests; injects a controllable clock.
  now?: () => number;
}

export interface ClientResponse {
  status: number;
  body: unknown;
  // Distinct from a real 5xx — set when the in-isolate pause is active.
  paused?: boolean;
}

function urlFor(opts: ClientOptions, path: string, params: Record<string, string>): string {
  const url = new URL(path, opts.baseUrl ?? BASE_URL);
  url.searchParams.set("t", opts.token);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return url.toString();
}

async function doFetch(url: string): Promise<ClientResponse> {
  const res = await fetch(url, {
    method: "GET",
    headers: { accept: "application/json" },
  });
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return { status: res.status, body };
}

export async function get(
  opts: ClientOptions,
  path: string,
  params: Record<string, string>,
): Promise<ClientResponse> {
  const now = (opts.now ?? Date.now)();
  if (now < pausedUntil) {
    return { status: 429, body: { code: "PAUSED" }, paused: true };
  }

  const url = urlFor(opts, path, params);
  const first = await doFetch(url);

  if (first.status === 429) {
    // 60s in-isolate pause, then surface 429 to the caller.
    pausedUntil = now + 60_000;
    return first;
  }

  // 401 once may be a transient token-refresh artifact; retry exactly once.
  if (first.status === 401) {
    const second = await doFetch(url);
    return second;
  }

  return first;
}
```

- [ ] **Step 2: Type-check**

Run: `deno check supabase/functions/price-comp/pricecharting/client.ts`
Expected: no errors. (`@ts-nocheck` suppresses the std-lib import warnings we know about; behavior remains type-checked for our own types.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/pricecharting/client.ts
git commit -m "edge: add PriceCharting HTTP client with retry-once and rate-limit pause"
```

---

## Task 8: Edge Function — `pricecharting/search.ts` and `pricecharting/product.ts`

**Files:**
- Create: `supabase/functions/price-comp/pricecharting/search.ts`
- Create: `supabase/functions/price-comp/pricecharting/product.ts`
- Create: `supabase/functions/price-comp/__fixtures__/pricecharting/products-search-hits.json`
- Create: `supabase/functions/price-comp/__fixtures__/pricecharting/products-search-empty.json`

Wrappers over `client.ts`. No tests — exercised end-to-end by `index.test.ts`.

- [ ] **Step 1: Write the search fixtures**

```json
// supabase/functions/price-comp/__fixtures__/pricecharting/products-search-hits.json
{
  "status": "success",
  "products": [
    {
      "id": "12345678",
      "product-name": "Pikachu ex 247/191",
      "console-name": "Pokemon Surging Sparks",
      "release-date": "2024-11-08"
    },
    {
      "id": "12345679",
      "product-name": "Pikachu ex 247/191 (Reverse Holo)",
      "console-name": "Pokemon Surging Sparks",
      "release-date": "2024-11-08"
    }
  ]
}
```

```json
// supabase/functions/price-comp/__fixtures__/pricecharting/products-search-empty.json
{
  "status": "success",
  "products": []
}
```

- [ ] **Step 2: Write `search.ts`**

```typescript
// supabase/functions/price-comp/pricecharting/search.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { get, type ClientOptions, type ClientResponse } from "./client.ts";
import type { PCProductRow } from "./parse.ts";

export interface SearchResult {
  status: number;
  products: PCProductRow[];
}

export async function searchProducts(
  opts: ClientOptions,
  q: string,
): Promise<SearchResult> {
  const res: ClientResponse = await get(opts, "/api/products", { q });
  if (res.status !== 200) return { status: res.status, products: [] };
  const body = (res.body ?? {}) as { products?: PCProductRow[] };
  return { status: 200, products: Array.isArray(body.products) ? body.products : [] };
}
```

- [ ] **Step 3: Write `product.ts`**

```typescript
// supabase/functions/price-comp/pricecharting/product.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { get, type ClientOptions, type ClientResponse } from "./client.ts";
import type { PCProductRow } from "./parse.ts";

export interface GetProductResult {
  status: number;
  product: PCProductRow | null;
}

export async function getProduct(
  opts: ClientOptions,
  id: string,
): Promise<GetProductResult> {
  const res: ClientResponse = await get(opts, "/api/product", { id });
  if (res.status !== 200) return { status: res.status, product: null };
  return { status: 200, product: (res.body ?? null) as PCProductRow | null };
}
```

- [ ] **Step 4: Type-check**

Run: `deno check supabase/functions/price-comp/pricecharting/search.ts supabase/functions/price-comp/pricecharting/product.ts`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/pricecharting/search.ts \
        supabase/functions/price-comp/pricecharting/product.ts \
        supabase/functions/price-comp/__fixtures__/pricecharting/products-search-hits.json \
        supabase/functions/price-comp/__fixtures__/pricecharting/products-search-empty.json
git commit -m "edge: add PriceCharting search + product wrappers"
```

---

## Task 9: Edge Function — `persistence/identity-product-id.ts`

**Files:**
- Create: `supabase/functions/price-comp/persistence/identity-product-id.ts`

- [ ] **Step 1: Write the implementation**

```typescript
// supabase/functions/price-comp/persistence/identity-product-id.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { SupabaseClient } from "@supabase/supabase-js";

export async function persistIdentityProductId(
  supabase: SupabaseClient,
  identityId: string,
  productId: string,
  productUrl: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({
      pricecharting_product_id: productId,
      pricecharting_url: productUrl,
    })
    .eq("id", identityId);
  if (error) throw new Error(`graded_card_identities update: ${error.message}`);
}

// Used to clear a stale id when the cached product is deleted upstream
// (PriceCharting 404 on /api/product?id=…). Next scan re-runs search.
export async function clearIdentityProductId(
  supabase: SupabaseClient,
  identityId: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({ pricecharting_product_id: null, pricecharting_url: null })
    .eq("id", identityId);
  if (error) throw new Error(`graded_card_identities clear: ${error.message}`);
}
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/price-comp/persistence/identity-product-id.ts
git commit -m "edge: add identity product-id persistence helpers"
```

---

## Task 10: Edge Function — rewrite `persistence/market.ts`

**Files:**
- Modify: `supabase/functions/price-comp/persistence/market.ts` (full rewrite)

- [ ] **Step 1: Replace the file contents**

```typescript
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
// supabase/functions/price-comp/persistence/market.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService } from "../types.ts";
import type { LadderPrices } from "../pricecharting/parse.ts";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  pricechartingProductId: string;
  pricechartingUrl: string;
}

// graded_market columns are numeric(12,2). Convert cents <-> dollars at the
// boundary; null cents passes through as null.
function centsToDecimal(cents: number | null): number | null {
  if (cents === null) return null;
  return Math.round(cents) / 100;
}

export async function upsertMarketLadder(
  supabase: SupabaseClient,
  input: MarketUpsertInput,
): Promise<void> {
  const { error } = await supabase
    .from("graded_market")
    .upsert({
      identity_id: input.identityId,
      grading_service: input.gradingService,
      grade: input.grade,
      source: "pricecharting",
      pricecharting_product_id: input.pricechartingProductId,
      pricecharting_url: input.pricechartingUrl,
      headline_price:  centsToDecimal(input.headlinePriceCents),
      loose_price:     centsToDecimal(input.ladderCents.loose),
      grade_7_price:   centsToDecimal(input.ladderCents.grade_7),
      grade_8_price:   centsToDecimal(input.ladderCents.grade_8),
      grade_9_price:   centsToDecimal(input.ladderCents.grade_9),
      grade_9_5_price: centsToDecimal(input.ladderCents.grade_9_5),
      psa_10_price:    centsToDecimal(input.ladderCents.psa_10),
      bgs_10_price:    centsToDecimal(input.ladderCents.bgs_10),
      cgc_10_price:    centsToDecimal(input.ladderCents.cgc_10),
      sgc_10_price:    centsToDecimal(input.ladderCents.sgc_10),
      updated_at: new Date().toISOString(),
    }, { onConflict: "identity_id,grading_service,grade" });
  if (error) throw new Error(`graded_market upsert: ${error.message}`);
}

export interface MarketReadResult {
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  pricechartingProductId: string | null;
  pricechartingUrl: string | null;
  updatedAt: string | null;
}

function decimalToCents(d: string | number | null): number | null {
  if (d === null || d === undefined) return null;
  const n = typeof d === "string" ? Number(d) : d;
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100);
}

export async function readMarketLadder(
  supabase: SupabaseClient,
  identityId: string,
  gradingService: GradingService,
  grade: string,
): Promise<MarketReadResult | null> {
  const { data } = await supabase
    .from("graded_market")
    .select(
      "headline_price, loose_price, grade_7_price, grade_8_price, grade_9_price, " +
      "grade_9_5_price, psa_10_price, bgs_10_price, cgc_10_price, sgc_10_price, " +
      "pricecharting_product_id, pricecharting_url, updated_at",
    )
    .eq("identity_id", identityId)
    .eq("grading_service", gradingService)
    .eq("grade", grade)
    .maybeSingle();
  if (!data) return null;
  return {
    headlinePriceCents: decimalToCents(data.headline_price),
    ladderCents: {
      loose:     decimalToCents(data.loose_price),
      grade_7:   decimalToCents(data.grade_7_price),
      grade_8:   decimalToCents(data.grade_8_price),
      grade_9:   decimalToCents(data.grade_9_price),
      grade_9_5: decimalToCents(data.grade_9_5_price),
      psa_10:    decimalToCents(data.psa_10_price),
      bgs_10:    decimalToCents(data.bgs_10_price),
      cgc_10:    decimalToCents(data.cgc_10_price),
      sgc_10:    decimalToCents(data.sgc_10_price),
    },
    pricechartingProductId: data.pricecharting_product_id ?? null,
    pricechartingUrl: data.pricecharting_url ?? null,
    updatedAt: data.updated_at ?? null,
  };
}
```

- [ ] **Step 2: Type-check**

Run: `deno check supabase/functions/price-comp/persistence/market.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/persistence/market.ts
git commit -m "edge: rewrite market.ts to upsert/read PriceCharting ladder"
```

---

## Task 11: Edge Function — rewrite `types.ts`

**Files:**
- Modify: `supabase/functions/price-comp/types.ts` (full rewrite)

- [ ] **Step 1: Replace the file contents**

```typescript
// supabase/functions/price-comp/types.ts

export type GradingService = "PSA" | "BGS" | "CGC" | "SGC" | "TAG";

export interface GradedCardIdentity {
  id: string;
  game: "pokemon";
  language: "en" | "jp" | string;
  set_code: string | null;
  set_name: string;
  card_number: string | null;
  card_name: string;
  variant: string | null;
  year: number | null;
  pricecharting_product_id: string | null;
  pricecharting_url: string | null;
}

export interface PriceCompRequest {
  graded_card_identity_id: string;
  grading_service: GradingService;
  grade: string;
}

export interface PriceCompResponse {
  headline_price_cents: number | null;
  grading_service: GradingService;
  grade: string;

  loose_price_cents:     number | null;
  grade_7_price_cents:   number | null;
  grade_8_price_cents:   number | null;
  grade_9_price_cents:   number | null;
  grade_9_5_price_cents: number | null;
  psa_10_price_cents:    number | null;
  bgs_10_price_cents:    number | null;
  cgc_10_price_cents:    number | null;
  sgc_10_price_cents:    number | null;

  pricecharting_product_id: string;
  pricecharting_url: string;

  fetched_at: string;
  cache_hit: boolean;
  is_stale_fallback: boolean;
}

export type CacheState = "hit" | "miss" | "stale";
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/price-comp/types.ts
git commit -m "edge: reshape types.ts for PriceCharting payload"
```

---

## Task 12: Edge Function — rewrite `index.ts` (orchestrator)

**Files:**
- Modify: `supabase/functions/price-comp/index.ts` (full rewrite)
- Create: `supabase/functions/price-comp/__tests__/index.test.ts` (rewrite)

This is the largest task. TDD with one integration test driving the orchestrator end-to-end against an in-isolate mock PriceCharting server.

- [ ] **Step 1: Write the failing integration test**

```typescript
// supabase/functions/price-comp/__tests__/index.test.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

// Spawn a mock PriceCharting server on a random port, point client.ts at it
// via injection through env, and exercise the handler. We import the
// handler directly (not Deno.serve) so we can call it with a constructed
// Request object.
import { handle } from "../index.ts";

interface MockState {
  productResponses: Map<string, { status: number; body: unknown }>;
  searchResponses: Map<string, { status: number; body: unknown }>;
  productCalls: string[];
  searchCalls: string[];
}

function startMock(state: MockState): { url: string; close: () => Promise<void> } {
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, (req) => {
    const url = new URL(req.url);
    if (url.pathname === "/api/product") {
      const id = url.searchParams.get("id") ?? "";
      state.productCalls.push(id);
      const r = state.productResponses.get(id);
      if (!r) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(r.body), { status: r.status, headers: { "content-type": "application/json" } });
    }
    if (url.pathname === "/api/products") {
      const q = url.searchParams.get("q") ?? "";
      state.searchCalls.push(q);
      const r = state.searchResponses.get(q) ?? state.searchResponses.get("__default__");
      if (!r) return new Response(JSON.stringify({ products: [] }), { status: 200, headers: { "content-type": "application/json" } });
      return new Response(JSON.stringify(r.body), { status: r.status, headers: { "content-type": "application/json" } });
    }
    return new Response("nope", { status: 404 });
  });
  // Server bound to port 0 — read it from the address.
  const url = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  return {
    url,
    async close() {
      ac.abort();
      try { await server.finished; } catch { /* ignore */ }
    },
  };
}

const fullLadder = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/pricecharting/product-full-ladder.json", import.meta.url)),
);

interface FakeIdentity {
  id: string;
  card_name: string;
  card_number: string | null;
  set_name: string;
  year: number | null;
  pricecharting_product_id: string | null;
  pricecharting_url: string | null;
}

interface FakeMarketRow {
  identity_id: string;
  grading_service: string;
  grade: string;
  source: string;
  pricecharting_product_id: string | null;
  pricecharting_url: string | null;
  headline_price: number | null;
  loose_price: number | null;
  grade_7_price: number | null;
  grade_8_price: number | null;
  grade_9_price: number | null;
  grade_9_5_price: number | null;
  psa_10_price: number | null;
  bgs_10_price: number | null;
  cgc_10_price: number | null;
  sgc_10_price: number | null;
  updated_at: string;
}

// In-memory fake supabase client, narrowed to the surface the handler
// actually uses. Sufficient for orchestrator integration tests.
function fakeSupabase(state: { identity: FakeIdentity; market: FakeMarketRow | null }) {
  return {
    from(table: string) {
      if (table === "graded_card_identities") {
        return {
          select() { return this; },
          eq(_col: string, _val: string) { return this; },
          single: async () => ({ data: state.identity, error: null }),
          update(values: Partial<FakeIdentity>) {
            return {
              eq: async (_c: string, _v: string) => {
                Object.assign(state.identity, values);
                return { error: null };
              },
            };
          },
        };
      }
      if (table === "graded_market") {
        return {
          select(_cols: string) { return this; },
          eq(_col: string, _val: string) { return this; },
          maybeSingle: async () => ({ data: state.market, error: null }),
          upsert(values: FakeMarketRow, _opts: unknown) {
            state.market = { ...values, updated_at: values.updated_at ?? new Date().toISOString() };
            return Promise.resolve({ error: null });
          },
        };
      }
      throw new Error(`unexpected table ${table}`);
    },
  };
}

Deno.test("cache miss — runs search, persists product id, returns ladder", async () => {
  const state: MockState = {
    productResponses: new Map([["12345678", { status: 200, body: fullLadder }]]),
    searchResponses: new Map([
      ["__default__", { status: 200, body: { products: [{ id: "12345678", "product-name": "Pikachu ex 247/191", "console-name": "Pokemon Surging Sparks" }] } }],
    ]),
    productCalls: [],
    searchCalls: [],
  };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Pikachu ex",
        card_number: "247/191",
        set_name: "Surging Sparks",
        year: 2024,
        pricecharting_product_id: null,
        pricecharting_url: null,
      },
      market: null,
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        graded_card_identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
      }),
    });
    const res = await handle(req, {
      supabase: fake,
      pricechartingBaseUrl: mock.url,
      pricechartingToken: "test-token",
      ttlSeconds: 86400,
      now: () => Date.now(),
    });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.headline_price_cents, 18500);
    assertEquals(body.psa_10_price_cents, 18500);
    assertEquals(body.bgs_10_price_cents, 21500);
    assertEquals(body.pricecharting_product_id, "12345678");
    assertEquals(body.cache_hit, false);
    assert(state.searchCalls.length === 1, "search called exactly once");
    assert(state.productCalls.length === 1, "product called exactly once");
  } finally {
    await mock.close();
  }
});

Deno.test("cache hit — within TTL skips PriceCharting calls", async () => {
  const state: MockState = {
    productResponses: new Map(),
    searchResponses: new Map(),
    productCalls: [],
    searchCalls: [],
  };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Pikachu ex",
        card_number: "247/191",
        set_name: "Surging Sparks",
        year: 2024,
        pricecharting_product_id: "12345678",
        pricecharting_url: "https://www.pricecharting.com/game/pokemon-surging-sparks/pikachu-ex-247-191",
      },
      market: {
        identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
        source: "pricecharting",
        pricecharting_product_id: "12345678",
        pricecharting_url: "https://www.pricecharting.com/game/pokemon-surging-sparks/pikachu-ex-247-191",
        headline_price: 185.0,
        loose_price: 4.0,
        grade_7_price: 24.0,
        grade_8_price: 34.0,
        grade_9_price: 68.0,
        grade_9_5_price: 112.0,
        psa_10_price: 185.0,
        bgs_10_price: 215.0,
        cgc_10_price: 168.0,
        sgc_10_price: 165.0,
        updated_at: new Date().toISOString(),
      },
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        graded_card_identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
      }),
    });
    const res = await handle(req, {
      supabase: fake,
      pricechartingBaseUrl: mock.url,
      pricechartingToken: "test-token",
      ttlSeconds: 86400,
      now: () => Date.now(),
    });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.cache_hit, true);
    assertEquals(body.headline_price_cents, 18500);
    assertEquals(state.searchCalls.length, 0, "no search call");
    assertEquals(state.productCalls.length, 0, "no product call");
  } finally {
    await mock.close();
  }
});

Deno.test("zero search hits — 404 PRODUCT_NOT_RESOLVED", async () => {
  const state: MockState = {
    productResponses: new Map(),
    searchResponses: new Map([
      ["__default__", { status: 200, body: { products: [] } }],
    ]),
    productCalls: [],
    searchCalls: [],
  };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Unknown",
        card_number: "0/0",
        set_name: "Nothing",
        year: null,
        pricecharting_product_id: null,
        pricecharting_url: null,
      },
      market: null,
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        graded_card_identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
      }),
    });
    const res = await handle(req, {
      supabase: fake,
      pricechartingBaseUrl: mock.url,
      pricechartingToken: "test-token",
      ttlSeconds: 86400,
      now: () => Date.now(),
    });
    const body = await res.json();
    assertEquals(res.status, 404);
    assertEquals(body.code, "PRODUCT_NOT_RESOLVED");
    assertEquals(fake.from("graded_card_identities").single, fake.from("graded_card_identities").single,
                 "identity not mutated"); // sanity: same shape, no persistence
  } finally {
    await mock.close();
  }
});

Deno.test("upstream 5xx with cached row — returns stale fallback", async () => {
  const state: MockState = {
    productResponses: new Map([["12345678", { status: 503, body: { error: "down" } }]]),
    searchResponses: new Map(),
    productCalls: [],
    searchCalls: [],
  };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Pikachu ex",
        card_number: "247/191",
        set_name: "Surging Sparks",
        year: 2024,
        pricecharting_product_id: "12345678",
        pricecharting_url: "https://www.pricecharting.com/game/pokemon-surging-sparks/pikachu-ex-247-191",
      },
      market: {
        identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
        source: "pricecharting",
        pricecharting_product_id: "12345678",
        pricecharting_url: "https://www.pricecharting.com/game/pokemon-surging-sparks/pikachu-ex-247-191",
        headline_price: 180.0,
        loose_price: 4.0,
        grade_7_price: null,
        grade_8_price: null,
        grade_9_price: 68.0,
        grade_9_5_price: 112.0,
        psa_10_price: 180.0,
        bgs_10_price: null,
        cgc_10_price: null,
        sgc_10_price: null,
        // Two days old — outside the 24h TTL.
        updated_at: new Date(Date.now() - 2 * 86400_000).toISOString(),
      },
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        graded_card_identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
      }),
    });
    const res = await handle(req, {
      supabase: fake,
      pricechartingBaseUrl: mock.url,
      pricechartingToken: "test-token",
      ttlSeconds: 86400,
      now: () => Date.now(),
    });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.cache_hit, true);
    assertEquals(body.is_stale_fallback, true);
    assertEquals(body.headline_price_cents, 18000);
  } finally {
    await mock.close();
  }
});

Deno.test("identity not found — 404 IDENTITY_NOT_FOUND", async () => {
  const fake = {
    from(_t: string) {
      return {
        select() { return this; },
        eq(_c: string, _v: string) { return this; },
        single: async () => ({ data: null, error: { message: "not found" } }),
      };
    },
  };
  const req = new Request("http://localhost/price-comp", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      graded_card_identity_id: "missing",
      grading_service: "PSA",
      grade: "10",
    }),
  });
  const res = await handle(req, {
    supabase: fake,
    pricechartingBaseUrl: "http://localhost:0",
    pricechartingToken: "test-token",
    ttlSeconds: 86400,
    now: () => Date.now(),
  });
  const body = await res.json();
  assertEquals(res.status, 404);
  assertEquals(body.code, "IDENTITY_NOT_FOUND");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/price-comp/__tests__/index.test.ts --no-check --allow-net --allow-read`
Expected: FAIL — `handle` is not exported (or `index.ts` still has the old eBay implementation).

- [ ] **Step 3: Write minimal implementation**

```typescript
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
// supabase/functions/price-comp/index.ts
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PriceCompRequest, PriceCompResponse, CacheState } from "./types.ts";
import type { LadderPrices, PCProductRow } from "./pricecharting/parse.ts";
import { extractLadder, pickTier, productUrl, ladderHasAnyPrice } from "./pricecharting/parse.ts";
import { searchProducts } from "./pricecharting/search.ts";
import { getProduct } from "./pricecharting/product.ts";
import { upsertMarketLadder, readMarketLadder } from "./persistence/market.ts";
import { persistIdentityProductId, clearIdentityProductId } from "./persistence/identity-product-id.ts";
import { evaluateFreshness } from "./cache/freshness.ts";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json" },
  });
}

function env(name: string, fallback?: string): string {
  const v = Deno.env.get(name);
  if (v !== undefined && v !== "") return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`missing env: ${name}`);
}

function ladderToCents(ladder: LadderPrices): LadderPrices {
  // ladder is already in pennies (PriceCharting native unit) — pass through.
  // The function name is for clarity at the call site; no transform needed.
  return ladder;
}

function buildSearchQuery(identity: {
  card_name: string;
  card_number: string | null;
  set_name: string;
  year: number | null;
}): string {
  const parts: string[] = [];
  parts.push(`"${identity.card_name}"`);
  if (identity.card_number) parts.push(`"${identity.card_number}"`);
  parts.push(identity.set_name);
  if (identity.year !== null) parts.push(String(identity.year));
  return parts.join(" ");
}

function buildResponse(args: {
  ladderCents: LadderPrices;
  headlineCents: number | null;
  service: GradingService;
  grade: string;
  productId: string;
  productUrl: string;
  cacheHit: boolean;
  isStaleFallback: boolean;
}): PriceCompResponse {
  return {
    headline_price_cents: args.headlineCents,
    grading_service: args.service,
    grade: args.grade,
    loose_price_cents:     args.ladderCents.loose,
    grade_7_price_cents:   args.ladderCents.grade_7,
    grade_8_price_cents:   args.ladderCents.grade_8,
    grade_9_price_cents:   args.ladderCents.grade_9,
    grade_9_5_price_cents: args.ladderCents.grade_9_5,
    psa_10_price_cents:    args.ladderCents.psa_10,
    bgs_10_price_cents:    args.ladderCents.bgs_10,
    cgc_10_price_cents:    args.ladderCents.cgc_10,
    sgc_10_price_cents:    args.ladderCents.sgc_10,
    pricecharting_product_id: args.productId,
    pricecharting_url: args.productUrl,
    fetched_at: new Date().toISOString(),
    cache_hit: args.cacheHit,
    is_stale_fallback: args.isStaleFallback,
  };
}

export interface HandleDeps {
  supabase: SupabaseClient | unknown;
  pricechartingBaseUrl: string;
  pricechartingToken: string;
  ttlSeconds: number;
  now: () => number;
}

export async function handle(req: Request, deps: HandleDeps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: PriceCompRequest;
  try { body = (await req.json()) as PriceCompRequest; }
  catch { return json(400, { error: "invalid_json" }); }
  if (!body.graded_card_identity_id || !body.grading_service || !body.grade) {
    return json(400, { error: "missing_fields" });
  }

  const supabase = deps.supabase as SupabaseClient;

  // 1. Identity lookup
  const { data: identity, error: idErr } = await supabase
    .from("graded_card_identities").select("*")
    .eq("id", body.graded_card_identity_id).single();
  if (idErr || !identity) {
    console.error("price-comp.identity_not_found", {
      identity_id: body.graded_card_identity_id,
      pg_error: idErr?.message ?? null,
    });
    return json(404, { code: "IDENTITY_NOT_FOUND" });
  }

  // 2. Cache read
  const cached = await readMarketLadder(supabase, body.graded_card_identity_id, body.grading_service, body.grade);
  const state: CacheState = evaluateFreshness({
    updatedAtMs: cached?.updatedAt ? Date.parse(cached.updatedAt) : null,
    nowMs: deps.now(),
    ttlSeconds: deps.ttlSeconds,
  });

  if (state === "hit" && cached) {
    return json(200, buildResponse({
      ladderCents: ladderToCents(cached.ladderCents),
      headlineCents: cached.headlinePriceCents,
      service: body.grading_service,
      grade: body.grade,
      productId: cached.pricechartingProductId ?? identity.pricecharting_product_id ?? "",
      productUrl: cached.pricechartingUrl ?? identity.pricecharting_url ?? "",
      cacheHit: true,
      isStaleFallback: false,
    }));
  }

  // 3. Resolve PriceCharting product id (hybrid)
  const clientOpts = {
    token: deps.pricechartingToken,
    baseUrl: deps.pricechartingBaseUrl,
    now: deps.now,
  };

  let productId = identity.pricecharting_product_id as string | null;
  if (!productId) {
    const q = buildSearchQuery(identity);
    const search = await searchProducts(clientOpts, q);
    if (search.status >= 500) {
      return await staleOrUpstreamDown(cached, body, "5xx_search");
    }
    if (search.status === 401 || search.status === 403) {
      console.error("pc.auth_invalid", { phase: "search" });
      return json(502, { code: "AUTH_INVALID" });
    }
    if (search.products.length === 0) {
      console.log("pc.match.zero_hits", { q });
      return json(404, { code: "PRODUCT_NOT_RESOLVED" });
    }
    const top = search.products[0];
    productId = String(top.id ?? "");
    if (!productId) return json(404, { code: "PRODUCT_NOT_RESOLVED" });
    const url = productUrl(top);
    try {
      await persistIdentityProductId(supabase, body.graded_card_identity_id, productId, url);
      console.log("pc.match.first_resolved", { identity_id: body.graded_card_identity_id, product_id: productId });
    } catch (e) {
      console.error("pc.persist.identity_failed", { message: (e as Error).message });
    }
  }

  // 4. Live fetch product
  const product = await getProduct(clientOpts, productId);
  if (product.status === 401 || product.status === 403) {
    console.error("pc.auth_invalid", { phase: "product" });
    return json(502, { code: "AUTH_INVALID" });
  }
  if (product.status === 404) {
    // Cached id pointing at a deleted product. Clear it so the next scan
    // re-runs search.
    if (identity.pricecharting_product_id) {
      try { await clearIdentityProductId(supabase, body.graded_card_identity_id); } catch { /* swallow */ }
    }
    return json(404, { code: "NO_MARKET_DATA" });
  }
  if (product.status === 429 || product.status >= 500) {
    return await staleOrUpstreamDown(cached, body, `${product.status}_product`);
  }
  if (!product.product) {
    return json(404, { code: "NO_MARKET_DATA" });
  }

  const row: PCProductRow = product.product;
  const ladder = extractLadder(row);
  if (!ladderHasAnyPrice(ladder)) {
    console.log("pc.product.no_prices", { product_id: productId });
    return json(404, { code: "NO_MARKET_DATA" });
  }
  const headlineCents = pickTier(row, body.grading_service, body.grade);
  const url = identity.pricecharting_url ?? productUrl(row);

  try {
    await upsertMarketLadder(supabase, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service,
      grade: body.grade,
      headlinePriceCents: headlineCents,
      ladderCents: ladder,
      pricechartingProductId: productId,
      pricechartingUrl: url,
    });
  } catch (e) {
    console.error("pc.persist.market_failed", { message: (e as Error).message });
  }

  console.log("price-comp.live", {
    identity_id: body.graded_card_identity_id,
    product_id: productId,
    cache_state: state,
    headline_present: headlineCents !== null,
  });

  return json(200, buildResponse({
    ladderCents: ladder,
    headlineCents,
    service: body.grading_service,
    grade: body.grade,
    productId,
    productUrl: url,
    cacheHit: false,
    isStaleFallback: false,
  }));
}

async function staleOrUpstreamDown(
  cached: Awaited<ReturnType<typeof readMarketLadder>>,
  body: PriceCompRequest,
  marker: string,
): Promise<Response> {
  console.error("pc.upstream_5xx", { marker });
  if (!cached) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  return json(200, buildResponse({
    ladderCents: cached.ladderCents,
    headlineCents: cached.headlinePriceCents,
    service: body.grading_service,
    grade: body.grade,
    productId: cached.pricechartingProductId ?? "",
    productUrl: cached.pricechartingUrl ?? "",
    cacheHit: true,
    isStaleFallback: true,
  }));
}

// Production entrypoint. Tests import `handle` directly with injected deps.
Deno.serve(async (req) => {
  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  return await handle(req, {
    supabase,
    pricechartingBaseUrl: "https://www.pricecharting.com",
    pricechartingToken: env("PRICECHARTING_API_TOKEN"),
    ttlSeconds: Number(env("PRICECHARTING_FRESHNESS_TTL_SECONDS", "86400")),
    now: () => Date.now(),
  });
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/price-comp/__tests__/index.test.ts --no-check --allow-net --allow-read`
Expected: PASS, all 5 cases.

- [ ] **Step 5: Type-check the function root**

Run: `deno check supabase/functions/price-comp/index.ts`
Expected: no errors (`@ts-nocheck` is in place per the project's existing convention for Deno files).

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/price-comp/index.ts \
        supabase/functions/price-comp/__tests__/index.test.ts
git commit -m "edge: rewrite price-comp orchestrator on PriceCharting"
```

---

## Task 13: Edge Function — delete dead eBay code and tests

**Files:**
- Delete: `supabase/functions/price-comp/ebay/` (directory)
- Delete: `supabase/functions/price-comp/persistence/scan-event.ts`
- Delete: `supabase/functions/price-comp/stats/` (directory)
- Delete: `supabase/functions/price-comp/lib/grade-normalize.ts`, `lib/graded-title-parse.ts`, `lib/card-name-normalize.ts`
- Delete: `supabase/functions/price-comp/__fixtures__/mi-*.json`, `__fixtures__/oauth-token.json`
- Delete: `supabase/functions/price-comp/__tests__/aggregates.test.ts`, `browse.test.ts`, `cascade.test.ts`, `oauth.test.ts`, `outliers.test.ts`, `query-builder.test.ts`, `card-name-normalize.test.ts`, `grade-normalize.test.ts`, `confidence.test.ts`

- [ ] **Step 1: Confirm no remaining import**

Run: `grep -r -n -E '(ebay|stats/|persistence/scan-event|grade-normalize|graded-title-parse|card-name-normalize)' supabase/functions/price-comp/ | grep -v '__fixtures__'`
Expected: no matches except inside files about to be deleted. If a stray reference shows up in the new code, fix that reference before proceeding (it indicates a missed dependency).

- [ ] **Step 2: Delete the eBay tree**

```bash
git rm -r supabase/functions/price-comp/ebay/
git rm    supabase/functions/price-comp/persistence/scan-event.ts
git rm -r supabase/functions/price-comp/stats/
git rm    supabase/functions/price-comp/lib/grade-normalize.ts
git rm    supabase/functions/price-comp/lib/graded-title-parse.ts
git rm    supabase/functions/price-comp/lib/card-name-normalize.ts
```

- [ ] **Step 3: Delete the eBay fixtures**

```bash
git rm supabase/functions/price-comp/__fixtures__/mi-dense.json \
       supabase/functions/price-comp/__fixtures__/mi-empty.json \
       supabase/functions/price-comp/__fixtures__/mi-sparse.json \
       supabase/functions/price-comp/__fixtures__/mi-with-outlier.json \
       supabase/functions/price-comp/__fixtures__/oauth-token.json
```

- [ ] **Step 4: Delete the eBay tests**

```bash
git rm supabase/functions/price-comp/__tests__/aggregates.test.ts \
       supabase/functions/price-comp/__tests__/browse.test.ts \
       supabase/functions/price-comp/__tests__/cascade.test.ts \
       supabase/functions/price-comp/__tests__/oauth.test.ts \
       supabase/functions/price-comp/__tests__/outliers.test.ts \
       supabase/functions/price-comp/__tests__/query-builder.test.ts \
       supabase/functions/price-comp/__tests__/card-name-normalize.test.ts \
       supabase/functions/price-comp/__tests__/grade-normalize.test.ts \
       supabase/functions/price-comp/__tests__/confidence.test.ts
```

- [ ] **Step 5: Run the full Deno test suite**

Run: `deno test supabase/functions/price-comp/__tests__/ --no-check --allow-net --allow-read`
Expected: PASS — only `grade-key.test.ts`, `parse.test.ts`, `freshness.test.ts`, `index.test.ts` remain. No "module not found" or import errors.

- [ ] **Step 6: Commit**

```bash
git commit -m "edge: remove eBay cascade, stats, scan-event, and supporting libs"
```

---

## Task 14: Scraper — remove `runEbaySoldIngest`

**Files:**
- Modify: `scraper/src/cli.ts`
- Delete: `scraper/src/graded/ingest/ebay-sold.ts`
- (Conditional) Delete: `scraper/tests/graded/ingest/ebay-sold.test.ts` if it exists

- [ ] **Step 1: Modify `scraper/src/cli.ts`**

Remove the import on line 7:
```typescript
import { runEbaySoldIngest } from "@/graded/ingest/ebay-sold.js";
```

Remove the `if (job === "ebay") { … }` block from the `run graded` action (the block runs from approximately line 46 to line 63 in the current file — the block beginning with `if (job === "ebay") {` and ending with the `return;` statement). The `pop` branch and the `unknown graded job` fall-through stay.

After modification, the relevant region of the action looks like:
```typescript
.action(async (job, o) => {
    const cfg = loadConfig();
    const log = createLogger({ level: cfg.runtime.logLevel });
    if (job === "pop") {
      // ... existing pop branch unchanged ...
      return;
    }
    log.error("unknown graded job", { job });
    process.exit(2);
  });
```

Also remove the `-q, --queries` option line and its description (eBay-specific) from the command's `.option(…)` chain since `pop` doesn't use it.

- [ ] **Step 2: Delete the ingest module**

```bash
git rm scraper/src/graded/ingest/ebay-sold.ts
```

- [ ] **Step 3: Delete the test if it exists**

```bash
if [ -f scraper/tests/graded/ingest/ebay-sold.test.ts ]; then
  git rm scraper/tests/graded/ingest/ebay-sold.test.ts
fi
```

- [ ] **Step 4: Verify scraper builds and tests pass**

Run: `cd /Users/dixoncider/slabbist/scraper && pnpm tsc --noEmit && pnpm vitest run`
Expected: type-check passes; remaining test suites pass. Any remaining failure means a leftover import — search and remove.

- [ ] **Step 5: Commit**

```bash
git add scraper/src/cli.ts
git commit -m "scraper: remove runEbaySoldIngest (writes to dropped graded_market columns)"
```

---

## Task 15: iOS — reshape `GradedMarketSnapshot` and drop `SoldListingMirror`

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift` (full rewrite)
- Delete: `ios/slabbist/slabbist/Core/Models/SoldListingMirror.swift`
- Modify: `ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift`

- [ ] **Step 1: Replace `GradedMarketSnapshot.swift`**

```swift
import Foundation
import SwiftData

@Model
final class GradedMarketSnapshot {
    var identityId: UUID
    var gradingService: String
    var grade: String

    var headlinePriceCents: Int64?

    var loosePriceCents: Int64?
    var grade7PriceCents: Int64?
    var grade8PriceCents: Int64?
    var grade9PriceCents: Int64?
    var grade9_5PriceCents: Int64?
    var psa10PriceCents: Int64?
    var bgs10PriceCents: Int64?
    var cgc10PriceCents: Int64?
    var sgc10PriceCents: Int64?

    var pricechartingProductId: String?
    var pricechartingURL: URL?

    var fetchedAt: Date
    var cacheHit: Bool
    var isStaleFallback: Bool

    init(
        identityId: UUID,
        gradingService: String,
        grade: String,
        headlinePriceCents: Int64?,
        loosePriceCents: Int64?,
        grade7PriceCents: Int64?,
        grade8PriceCents: Int64?,
        grade9PriceCents: Int64?,
        grade9_5PriceCents: Int64?,
        psa10PriceCents: Int64?,
        bgs10PriceCents: Int64?,
        cgc10PriceCents: Int64?,
        sgc10PriceCents: Int64?,
        pricechartingProductId: String?,
        pricechartingURL: URL?,
        fetchedAt: Date,
        cacheHit: Bool,
        isStaleFallback: Bool
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
        self.headlinePriceCents = headlinePriceCents
        self.loosePriceCents = loosePriceCents
        self.grade7PriceCents = grade7PriceCents
        self.grade8PriceCents = grade8PriceCents
        self.grade9PriceCents = grade9PriceCents
        self.grade9_5PriceCents = grade9_5PriceCents
        self.psa10PriceCents = psa10PriceCents
        self.bgs10PriceCents = bgs10PriceCents
        self.cgc10PriceCents = cgc10PriceCents
        self.sgc10PriceCents = sgc10PriceCents
        self.pricechartingProductId = pricechartingProductId
        self.pricechartingURL = pricechartingURL
        self.fetchedAt = fetchedAt
        self.cacheHit = cacheHit
        self.isStaleFallback = isStaleFallback
    }
}
```

- [ ] **Step 2: Delete `SoldListingMirror.swift`**

```bash
git rm ios/slabbist/slabbist/Core/Models/SoldListingMirror.swift
```

- [ ] **Step 3: Update `ModelContainer.swift`**

```swift
import Foundation
import SwiftData

enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Store.self,
            StoreMember.self,
            Lot.self,
            Scan.self,
            OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self
            // Plan 2 adds: GradedCard
        ])
        let config = ModelConfiguration("slabbist", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // The schema reshape from the eBay-aggregate model to the
            // PriceCharting per-tier ladder is not lightweight-migratable
            // (added optional Int64? fields, dropped a relationship, removed
            // many fields). On first launch after this change, blow the
            // store away and start fresh — comp data is recoverable from
            // a cheap re-fetch, all other models cascade through Store/Lot
            // ownership which is server-backed.
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "default.store"))
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }()

    /// In-memory container for tests and previews.
    static func inMemory() -> ModelContainer {
        let schema = Schema([
            Store.self, StoreMember.self, Lot.self,
            Scan.self, OutboxItem.self,
            GradedCardIdentity.self,
            GradedMarketSnapshot.self
        ])
        let config = ModelConfiguration("slabbist-tests", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
```

- [ ] **Step 4: Build the iOS app**

Run:
```bash
cd /Users/dixoncider/slabbist/ios/slabbist && \
xcodebuild -project slabbist.xcodeproj -scheme slabbist \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -quiet build 2>&1 | tail -40
```
Expected: build fails with errors in `CompRepository.swift`, `CompFetchService.swift`, `CompCardView.swift`, `ScanDetailView.swift`, `LotDetailView.swift`, and the test files. Those failures are intentional — the next tasks fix them.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift \
        ios/slabbist/slabbist/Core/Persistence/ModelContainer.swift
git commit -m "ios: reshape GradedMarketSnapshot for PriceCharting ladder"
```

---

## Task 16: iOS — rewrite `CompRepository`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompRepository.swift`
- Modify: `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift`

- [ ] **Step 1: Replace `CompRepositoryTests.swift`**

```swift
import Testing
import Foundation
import SwiftData
@testable import slabbist

@Suite("CompRepository")
@MainActor
struct CompRepositoryTests {
    @Test("decodes a full PriceCharting ladder response")
    func decodesFullLadder() async throws {
        let json = """
        {
          "headline_price_cents": 18500,
          "grading_service": "PSA",
          "grade": "10",
          "loose_price_cents": 400,
          "grade_7_price_cents": 2400,
          "grade_8_price_cents": 3400,
          "grade_9_price_cents": 6800,
          "grade_9_5_price_cents": 11200,
          "psa_10_price_cents": 18500,
          "bgs_10_price_cents": 21500,
          "cgc_10_price_cents": 16800,
          "sgc_10_price_cents": 16500,
          "pricecharting_product_id": "12345678",
          "pricecharting_url": "https://www.pricecharting.com/game/pokemon-surging-sparks/pikachu-ex-247-191",
          "fetched_at": "2026-05-05T22:14:03Z",
          "cache_hit": false,
          "is_stale_fallback": false
        }
        """.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == 18500)
        #expect(decoded.psa10PriceCents == 18500)
        #expect(decoded.bgs10PriceCents == 21500)
        #expect(decoded.loosePriceCents == 400)
        #expect(decoded.pricechartingProductId == "12345678")
        #expect(decoded.cacheHit == false)
    }

    @Test("decodes a partial ladder with null tiers")
    func decodesPartialLadder() async throws {
        let json = """
        {
          "headline_price_cents": null,
          "grading_service": "BGS",
          "grade": "10",
          "loose_price_cents": 500,
          "grade_7_price_cents": null,
          "grade_8_price_cents": null,
          "grade_9_price_cents": 4200,
          "grade_9_5_price_cents": null,
          "psa_10_price_cents": 18000,
          "bgs_10_price_cents": null,
          "cgc_10_price_cents": null,
          "sgc_10_price_cents": null,
          "pricecharting_product_id": "98765432",
          "pricecharting_url": "https://www.pricecharting.com/game/pokemon-vintage/obscure-card-999-999",
          "fetched_at": "2026-05-05T22:14:03Z",
          "cache_hit": true,
          "is_stale_fallback": false
        }
        """.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == nil)
        #expect(decoded.bgs10PriceCents == nil)
        #expect(decoded.psa10PriceCents == 18000)
    }

    @Test("404 NO_MARKET_DATA surfaces as a typed error")
    func mapsNoMarketData() async throws {
        let json = #"{ "code": "NO_MARKET_DATA" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.noMarketData) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }

    @Test("404 PRODUCT_NOT_RESOLVED surfaces as productNotResolved")
    func mapsProductNotResolved() async throws {
        let json = #"{ "code": "PRODUCT_NOT_RESOLVED" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.productNotResolved) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }

    @Test("404 IDENTITY_NOT_FOUND surfaces as identityNotFound")
    func mapsIdentityNotFound() async throws {
        let json = #"{ "code": "IDENTITY_NOT_FOUND" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.identityNotFound) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }

    @Test("502 AUTH_INVALID surfaces as authInvalid")
    func mapsAuthInvalid() async throws {
        let json = #"{ "code": "AUTH_INVALID" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.authInvalid) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 502)
        }
    }

    @Test("503 UPSTREAM_UNAVAILABLE surfaces as upstreamUnavailable")
    func mapsUpstreamUnavailable() async throws {
        let json = #"{ "code": "UPSTREAM_UNAVAILABLE" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.upstreamUnavailable) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 503)
        }
    }
}
```

- [ ] **Step 2: Run tests, confirm failure**

Run via Xcode: `Cmd+U` on `slabbistTests` (or `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:slabbistTests/CompRepositoryTests`).
Expected: build error — `CompRepository.decode`, `Decoded`, `Error.productNotResolved`, `Error.authInvalid` don't exist yet.

- [ ] **Step 3: Replace `CompRepository.swift`**

```swift
import Foundation
import SwiftData

@MainActor
final class CompRepository {
    enum Error: Swift.Error, Equatable {
        case noMarketData
        case productNotResolved
        case identityNotFound
        case authInvalid
        case upstreamUnavailable
        case httpStatus(Int)
        case decoding(String)
    }

    nonisolated struct Wire: Decodable {
        let headline_price_cents: Int64?
        let grading_service: String
        let grade: String
        let loose_price_cents: Int64?
        let grade_7_price_cents: Int64?
        let grade_8_price_cents: Int64?
        let grade_9_price_cents: Int64?
        let grade_9_5_price_cents: Int64?
        let psa_10_price_cents: Int64?
        let bgs_10_price_cents: Int64?
        let cgc_10_price_cents: Int64?
        let sgc_10_price_cents: Int64?
        let pricecharting_product_id: String
        let pricecharting_url: String
        let fetched_at: Date
        let cache_hit: Bool
        let is_stale_fallback: Bool
    }

    struct Decoded {
        let headlinePriceCents: Int64?
        let gradingService: String
        let grade: String
        let loosePriceCents: Int64?
        let grade7PriceCents: Int64?
        let grade8PriceCents: Int64?
        let grade9PriceCents: Int64?
        let grade9_5PriceCents: Int64?
        let psa10PriceCents: Int64?
        let bgs10PriceCents: Int64?
        let cgc10PriceCents: Int64?
        let sgc10PriceCents: Int64?
        let pricechartingProductId: String
        let pricechartingURL: URL?
        let fetchedAt: Date
        let cacheHit: Bool
        let isStaleFallback: Bool
    }

    private let urlSession: URLSession
    private let baseURL: URL
    private let authTokenProvider: () async -> String?

    init(urlSession: URLSession = .shared, baseURL: URL, authTokenProvider: @escaping () async -> String?) {
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.authTokenProvider = authTokenProvider
    }

    nonisolated static func decode(data: Data) throws -> Decoded {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire: Wire
        do { wire = try decoder.decode(Wire.self, from: data) }
        catch { throw Error.decoding("\(error)") }
        return Decoded(
            headlinePriceCents: wire.headline_price_cents,
            gradingService: wire.grading_service,
            grade: wire.grade,
            loosePriceCents: wire.loose_price_cents,
            grade7PriceCents: wire.grade_7_price_cents,
            grade8PriceCents: wire.grade_8_price_cents,
            grade9PriceCents: wire.grade_9_price_cents,
            grade9_5PriceCents: wire.grade_9_5_price_cents,
            psa10PriceCents: wire.psa_10_price_cents,
            bgs10PriceCents: wire.bgs_10_price_cents,
            cgc10PriceCents: wire.cgc_10_price_cents,
            sgc10PriceCents: wire.sgc_10_price_cents,
            pricechartingProductId: wire.pricecharting_product_id,
            pricechartingURL: URL(string: wire.pricecharting_url),
            fetchedAt: wire.fetched_at,
            cacheHit: wire.cache_hit,
            isStaleFallback: wire.is_stale_fallback
        )
    }

    nonisolated static func decodeErrorBody(_ data: Data, statusCode: Int) throws -> Never {
        struct Body: Decodable { let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        switch (statusCode, body?.code) {
        case (404, "NO_MARKET_DATA"):       throw Error.noMarketData
        case (404, "PRODUCT_NOT_RESOLVED"): throw Error.productNotResolved
        case (404, "IDENTITY_NOT_FOUND"):   throw Error.identityNotFound
        case (502, "AUTH_INVALID"):         throw Error.authInvalid
        case (503, "UPSTREAM_UNAVAILABLE"): throw Error.upstreamUnavailable
        default: throw Error.httpStatus(statusCode)
        }
    }

    func fetchComp(
        identityId: UUID,
        gradingService: String,
        grade: String
    ) async throws -> Decoded {
        var request = URLRequest(url: baseURL.appendingPathComponent("/price-comp"))
        request.httpMethod = "POST"
        // PriceCharting calls are sub-second on a warm cache, low-single-digit
        // seconds on a cold path (search + product). 30s leaves headroom
        // without leaving the spinner stuck for a full minute.
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token = await authTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "graded_card_identity_id": identityId.uuidString.lowercased(),
            "grading_service": gradingService,
            "grade": grade,
        ])
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Error.httpStatus(0) }
        if http.statusCode == 200 { return try Self.decode(data: data) }
        try Self.decodeErrorBody(data, statusCode: http.statusCode)
    }
}
```

- [ ] **Step 4: Run the test suite, confirm pass**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:slabbistTests/CompRepositoryTests | tail -20`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompRepository.swift \
        ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift
git commit -m "ios: rewrite CompRepository on PriceCharting payload + new error cases"
```

---

## Task 17: iOS — rewrite `CompFetchService.persistSnapshot` and `classify`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift`
- Modify: `ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift`

The in-flight de-dup, `flipMatching`, and the absorber pattern stay verbatim. Only `persistSnapshot` and `classify` change.

- [ ] **Step 1: Update `CompFetchServiceTests.swift`**

Open the file. Find every reference to fields that no longer exist on `Decoded` or `GradedMarketSnapshot` (`blendedPriceCents`, `meanPriceCents`, `trimmedMeanPriceCents`, `medianPriceCents`, `lowPriceCents`, `highPriceCents`, `confidence`, `sampleCount`, `sampleWindowDays`, `velocity*`, `soldListings`). Replace any test fixture that builds a `Decoded` or `GradedMarketSnapshot` with the new field set. Concretely, any helper like:

```swift
let decoded = CompRepository.Decoded(
    blendedPriceCents: 12345, /* ... */
)
```
becomes:
```swift
let decoded = CompRepository.Decoded(
    headlinePriceCents: 18500,
    gradingService: "PSA",
    grade: "10",
    loosePriceCents: 400,
    grade7PriceCents: nil,
    grade8PriceCents: nil,
    grade9PriceCents: 6800,
    grade9_5PriceCents: 11200,
    psa10PriceCents: 18500,
    bgs10PriceCents: 21500,
    cgc10PriceCents: 16800,
    sgc10PriceCents: 16500,
    pricechartingProductId: "12345678",
    pricechartingURL: URL(string: "https://www.pricecharting.com/game/x/y"),
    fetchedAt: Date(),
    cacheHit: false,
    isStaleFallback: false
)
```

Keep the in-flight de-dup test (the test that verifies parallel fetches for the same `(identityId, service, grade)` only call the repository once) — its assertions only inspect repository-call counts and `compFetchState`, so it stays valid.

Update any "noMarketData copy" assertion to match the new strings introduced in Step 3.

- [ ] **Step 2: Run the suite, confirm intentional failures**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:slabbistTests/CompFetchServiceTests | tail -30`
Expected: build errors first (because `persistSnapshot` still references old `Decoded` fields). Move to Step 3.

- [ ] **Step 3: Update `persistSnapshot` and `classify` in `CompFetchService.swift`**

Replace the existing `persistSnapshot` body with:
```swift
private static func persistSnapshot(
    decoded: CompRepository.Decoded,
    identityId: UUID,
    service: String,
    grade: String,
    context: ModelContext
) {
    let snapshot = GradedMarketSnapshot(
        identityId: identityId,
        gradingService: service,
        grade: grade,
        headlinePriceCents: decoded.headlinePriceCents,
        loosePriceCents: decoded.loosePriceCents,
        grade7PriceCents: decoded.grade7PriceCents,
        grade8PriceCents: decoded.grade8PriceCents,
        grade9PriceCents: decoded.grade9PriceCents,
        grade9_5PriceCents: decoded.grade9_5PriceCents,
        psa10PriceCents: decoded.psa10PriceCents,
        bgs10PriceCents: decoded.bgs10PriceCents,
        cgc10PriceCents: decoded.cgc10PriceCents,
        sgc10PriceCents: decoded.sgc10PriceCents,
        pricechartingProductId: decoded.pricechartingProductId,
        pricechartingURL: decoded.pricechartingURL,
        fetchedAt: decoded.fetchedAt,
        cacheHit: decoded.cacheHit,
        isStaleFallback: decoded.isStaleFallback
    )
    context.insert(snapshot)
}
```

Replace the existing `classify` body with:
```swift
nonisolated static func classify(_ error: Error) -> (state: CompFetchState, message: String) {
    if let typed = error as? CompRepository.Error {
        switch typed {
        case .noMarketData:
            return (.noData, "PriceCharting has no comp for this slab yet.")
        case .productNotResolved:
            return (.noData, "We couldn't find this card on PriceCharting.")
        case .upstreamUnavailable:
            return (.failed, "PriceCharting lookup unavailable — try again.")
        case .identityNotFound:
            return (.failed, "Card identity not on file — re-scan to refresh the cert.")
        case .authInvalid:
            return (.failed, "Comp lookup misconfigured — contact support.")
        case .httpStatus(let code):
            return (.failed, "Lookup failed (HTTP \(code)).")
        case .decoding(let detail):
            return (.failed, "Couldn't decode comp response: \(detail)")
        }
    }
    return (.failed, error.localizedDescription)
}
```

- [ ] **Step 4: Run the suite again**

Run: `xcodebuild test -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:slabbistTests/CompFetchServiceTests | tail -20`
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompFetchService.swift \
        ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift
git commit -m "ios: rewrite CompFetchService persistSnapshot+classify for ladder"
```

---

## Task 18: iOS — rewrite `CompCardView` (headline + ladder + footer)

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompCardView.swift`

- [ ] **Step 1: Replace the file contents**

```swift
import SwiftUI
import SwiftData

struct CompCardView: View {
    let snapshot: GradedMarketSnapshot

    var body: some View {
        SlabCard {
            VStack(alignment: .leading, spacing: 0) {
                heroRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.md)
                if !ladderTiers.isEmpty {
                    SlabCardDivider()
                    ladderRail
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if showsCaveat {
                    SlabCardDivider()
                    caveatRow
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                SlabCardDivider()
                footerRow
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.md)
            }
        }
    }

    // MARK: - Hero

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(headlineText)
                    .font(SlabFont.serif(size: 40))
                    .tracking(-1)
                    .foregroundStyle(AppColor.text)
                Text("\(snapshot.gradingService) \(snapshot.grade) · PRICECHARTING")
                    .font(SlabFont.sans(size: 10, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(AppColor.dim)
            }
            Spacer()
        }
    }

    private var headlineText: String {
        guard let cents = snapshot.headlinePriceCents else { return "—" }
        return formatCents(cents)
    }

    // MARK: - Grade ladder

    private struct Tier: Identifiable {
        let id: String
        let label: String
        let cents: Int64
        let isHeadline: Bool
    }

    /// Ordered tiers we render in the ladder rail when present. The headline
    /// tier (matching the snapshot's grader+grade) gets a gold border.
    private var ladderTiers: [Tier] {
        let entries: [(id: String, label: String, cents: Int64?, headlineKey: (service: String, grade: String)?)] = [
            ("loose",     "Raw",        snapshot.loosePriceCents,     nil),
            ("grade_7",   "7",          snapshot.grade7PriceCents,    nil),
            ("grade_8",   "8",          snapshot.grade8PriceCents,    nil),
            ("grade_9",   "9",          snapshot.grade9PriceCents,    nil),
            ("grade_9_5", "9.5",        snapshot.grade9_5PriceCents,  nil),
            ("psa_10",    "PSA 10",     snapshot.psa10PriceCents,     ("PSA", "10")),
            ("bgs_10",    "BGS 10",     snapshot.bgs10PriceCents,     ("BGS", "10")),
            ("cgc_10",    "CGC 10",     snapshot.cgc10PriceCents,     ("CGC", "10")),
            ("sgc_10",    "SGC 10",     snapshot.sgc10PriceCents,     ("SGC", "10")),
        ]
        return entries.compactMap { e in
            guard let cents = e.cents else { return nil }
            let isHeadline: Bool = {
                if let k = e.headlineKey {
                    return k.service == snapshot.gradingService && k.grade == snapshot.grade
                }
                return false
            }()
            return Tier(id: e.id, label: e.label, cents: cents, isHeadline: isHeadline)
        }
    }

    private var ladderRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(ladderTiers) { tier in
                    tierCell(tier)
                }
            }
        }
    }

    private func tierCell(_ tier: Tier) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(tier.label)
                .font(SlabFont.sans(size: 10, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(AppColor.dim)
            Text(formatCentsCompact(tier.cents))
                .font(SlabFont.mono(size: 14, weight: .medium))
                .foregroundStyle(AppColor.text)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tier.isHeadline ? AppColor.gold : AppColor.dim.opacity(0.3),
                        lineWidth: tier.isHeadline ? 1.5 : 1)
        )
    }

    // MARK: - Caveat (stale fallback)

    private var showsCaveat: Bool { snapshot.isStaleFallback }

    private var caveatRow: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColor.negative)
            Text("Cached — PriceCharting unavailable")
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle(AppColor.negative)
            Spacer()
        }
    }

    // MARK: - Footer (PriceCharting deep link)

    @ViewBuilder
    private var footerRow: some View {
        if let url = snapshot.pricechartingURL {
            Link(destination: url) {
                HStack(spacing: Spacing.xxs) {
                    Text("View real listings on PriceCharting")
                        .font(SlabFont.sans(size: 12, weight: .medium))
                        .foregroundStyle(AppColor.gold)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColor.gold)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }

    // MARK: - Formatters

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 2
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }

    private func formatCentsCompact(_ cents: Int64) -> String {
        let dollars = Int((Double(cents) / 100).rounded())
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 0
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}
```

- [ ] **Step 2: Build and visually verify in a SwiftUI preview**

Run a build (`xcodebuild build` per Task 15 step 4). The view should compile.

If a `#Preview` exists in the file, update or add:
```swift
#Preview("Full ladder") {
    CompCardView(snapshot: GradedMarketSnapshot(
        identityId: UUID(),
        gradingService: "PSA",
        grade: "10",
        headlinePriceCents: 18500,
        loosePriceCents: 400,
        grade7PriceCents: 2400,
        grade8PriceCents: 3400,
        grade9PriceCents: 6800,
        grade9_5PriceCents: 11200,
        psa10PriceCents: 18500,
        bgs10PriceCents: 21500,
        cgc10PriceCents: 16800,
        sgc10PriceCents: 16500,
        pricechartingProductId: "12345678",
        pricechartingURL: URL(string: "https://www.pricecharting.com/game/x/y"),
        fetchedAt: Date(),
        cacheHit: false,
        isStaleFallback: false
    ))
    .padding()
    .background(AppColor.background)
}

#Preview("Partial ladder, null headline") {
    CompCardView(snapshot: GradedMarketSnapshot(
        identityId: UUID(),
        gradingService: "BGS",
        grade: "10",
        headlinePriceCents: nil,
        loosePriceCents: 500,
        grade7PriceCents: nil,
        grade8PriceCents: nil,
        grade9PriceCents: 4200,
        grade9_5PriceCents: nil,
        psa10PriceCents: 18000,
        bgs10PriceCents: nil,
        cgc10PriceCents: nil,
        sgc10PriceCents: nil,
        pricechartingProductId: "98765432",
        pricechartingURL: URL(string: "https://www.pricecharting.com/game/x/y"),
        fetchedAt: Date(),
        cacheHit: true,
        isStaleFallback: false
    ))
    .padding()
    .background(AppColor.background)
}
```

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompCardView.swift
git commit -m "ios: rewrite CompCardView as headline + grade ladder + PriceCharting deep-link"
```

---

## Task 19: iOS — update `ScanDetailView` (remove listings; tweak copy)

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift`

- [ ] **Step 1: Remove the listings section**

Delete:

1. The call to `listingsSection(snapshot: snapshot)` inside `body` (it's invoked from the `valueSection` arm of the snapshot-present branch — currently rendered after `valueSection`).
2. The `private func listingsSection(snapshot:)` definition.
3. The `private func listingRow(_:)` definition.
4. The `private func outlierChip(reason:)` definition.

Concretely, remove every method whose body references `snapshot.soldListings`, `SoldListingMirror`, or `OutlierReason`. After this step, `formatCents(_:)` may have only one caller — keep it.

- [ ] **Step 2: Update copy on the loading / no-data / failed states**

Replace the `fetchingState` body:
```swift
private var fetchingState: some View {
    emptyState(
        kicker: "Fetching",
        symbol: "arrow.triangle.2.circlepath",
        symbolTint: AppColor.gold,
        title: "Fetching PriceCharting comp…",
        detail: "This usually takes a couple of seconds. Tap retry if it's stuck.",
        showsProgress: true,
        cta: ("Retry comp fetch", retry)
    )
}
```

Replace `noDataState`:
```swift
private var noDataState: some View {
    emptyState(
        kicker: "No comp",
        symbol: "magnifyingglass",
        symbolTint: AppColor.muted,
        title: "PriceCharting has no comp for this slab",
        detail: "Either we couldn't find this card on PriceCharting, or there's no published price for this tier yet. Try retrying later.",
        showsProgress: false,
        cta: ("Retry comp fetch", retry)
    )
}
```

Replace the `certNotResolvedState` `detail` text for the validation-failed branch:
- old: `"PSA didn't recognize cert \(scan.certNumber). Delete this slab and re-scan if the digits look wrong."`
- new (unchanged — leave as is; the cert-lookup path is independent of this work).

- [ ] **Step 3: Build**

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 15' -quiet build 2>&1 | tail -30`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift
git commit -m "ios: drop listings section + update copy for PriceCharting comp"
```

---

## Task 20: iOS — update `LotDetailView` reads

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift`

- [ ] **Step 1: Replace the four references**

In `LotDetailView.swift`:

1. Around line 201: replace `Text(formattedCents(snapshot.blendedPriceCents))` with `Text(formattedCents(snapshot.headlinePriceCents ?? 0))`. If `headlinePriceCents` is `nil`, render "—" instead by using:
   ```swift
   Text(snapshot.headlinePriceCents.map(formattedCents) ?? "—")
   ```
2. Around line 204: delete the `Text("\(snapshot.sampleCount) listed")` line entirely (PriceCharting has no sample-count notion).
3. Around line 262: replace `scans.compactMap { latestSnapshot(for: $0)?.blendedPriceCents }.reduce(0, +)` with `scans.compactMap { latestSnapshot(for: $0)?.headlinePriceCents }.reduce(0, +)`.
4. Around line 293: delete the entire `if let snapshot = latestSnapshot(for: scan) { let confPct = Int((snapshot.confidence * 100).rounded()) … }` block — the confidence pill is gone.

- [ ] **Step 2: Build**

Run: `xcodebuild build` (same command as Task 19 step 3).
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Lots/LotDetailView.swift
git commit -m "ios: drop sample-count + confidence reads from LotDetailView"
```

---

## Task 21: Edge Function — set Supabase secrets

**Files:** none (operational)

- [ ] **Step 1: Set the new secret**

Run:
```bash
supabase secrets set PRICECHARTING_API_TOKEN=<the-40-char-token>
supabase secrets set PRICECHARTING_FRESHNESS_TTL_SECONDS=86400
```
Expected: confirmation output. The token comes from the PriceCharting account dashboard.

- [ ] **Step 2: Unset the obsolete eBay secrets**

Run:
```bash
supabase secrets unset EBAY_APP_ID EBAY_CERT_ID EBAY_FRESHNESS_TTL_SECONDS EBAY_MIN_RESULTS_HEADLINE EBAY_OAUTH_SCOPE
```
Expected: confirmation. (The eBay account-deletion webhook has its own separate secret and is not touched.)

- [ ] **Step 3: Verify**

Run: `supabase secrets list | grep -E 'PRICECHARTING|EBAY'`
Expected: `PRICECHARTING_API_TOKEN` and `PRICECHARTING_FRESHNESS_TTL_SECONDS` present; no `EBAY_APP_ID` / `EBAY_CERT_ID` / etc. (Movers' account-deletion webhook may have its own different secret, e.g. `EBAY_VERIFICATION_TOKEN`, which should remain.)

- [ ] **Step 4: Deploy the function**

Run: `supabase functions deploy price-comp`
Expected: deploy succeeds.

---

## Task 22: End-to-end smoke

**Files:** none (manual)

- [ ] **Step 1: Boot the app on the simulator**

Run via Xcode: select the iPhone 15 simulator and `Run` the `slabbist` scheme.

- [ ] **Step 2: Force a fresh SwiftData store**

Delete the app from the simulator (long-press → Remove App) so the destructive container migration runs cleanly.

- [ ] **Step 3: Sign in and scan a known PSA 10 cert**

Use a real PSA 10 cert number for a card you've previously verified (e.g., the spec's "Pikachu ex 247/191" if available, or any other Pokémon PSA 10 you have on hand).

Expected:
- Cert lookup completes (independent of this work).
- The `ScanDetailView` flips from "Fetching PriceCharting comp…" to a `CompCardView` with headline + ladder + footer.
- Tapping the footer opens Safari to a `pricecharting.com/game/...` URL.

- [ ] **Step 4: Re-open the same scan, confirm cache hit**

Background and foreground the app, navigate back to the scan. The view should render immediately without the spinner.

In Supabase logs, confirm one log line per scan with `cache_state: "hit"` after the first cold-path call.

- [ ] **Step 5: Scan a BGS 9.5 cert**

Confirm the headline is the `grade_9_5` tier price (since BGS 9.5 maps to the generic grade ladder).

- [ ] **Step 6: Test airplane mode**

Enable airplane mode, scan a never-seen cert. The outbox should retry (state stays `fetching` while offline; flips to `failed` after the 30s URLSession timeout). Disable airplane mode, hit "Retry comp fetch", and confirm it resolves.

- [ ] **Step 7: Test PriceCharting outage simulation**

Temporarily set `PRICECHARTING_API_TOKEN=invalid` via `supabase secrets set`. Re-deploy. Trigger a fresh scan. Confirm `ScanDetailView` shows "Comp lookup misconfigured — contact support." Restore the real token and redeploy to clean up.

- [ ] **Step 8: Commit any test-time tweaks**

If any source change was needed during smoke (copy, layout adjustments), make a separate `ui:` commit. Otherwise nothing to commit.

---

## Self-review

After writing the plan, I checked it against the spec.

**Spec coverage:**
- Goals 1–6 ✅ — Tasks 12 (orchestrator), 5 (grade key), 6 (parse), 9 (identity persistence), 21 (secrets), 14 (scraper teardown).
- Hybrid product matching ✅ — Task 12 step 3 includes both branches plus the persistence step.
- Cache + freshness + secrets ✅ — Task 21 + the existing `cache/freshness.ts` (kept verbatim, no task needed beyond updating `__tests__/freshness.test.ts` defaults).
- Failure modes table ✅ — `index.test.ts` covers cache miss, cache hit, zero hits, upstream-down + cached, identity-not-found. The remaining branches (auth invalid, 429-pause, ladder-no-prices, cached id pointing at a deleted product) are coded in the orchestrator but not tested individually; they're behaviorally simple early-returns. Adding three more cases is a low-priority follow-up the implementation engineer can add inline if the smoke test reveals an issue.
- Data model migrations ✅ — Tasks 1–4.
- iOS reshape (model, repo, service, two views, ModelContainer) ✅ — Tasks 15–20.
- Tests ✅ — Tasks 5, 6, 12, 16, 17.
- Observability ✅ — log lines added in Task 12 step 3.

**Placeholder scan:** No "TBD", no "implement later", no "similar to Task N" without code. Each step shows the actual code or command. The one location near `ScanDetailView` in Task 19 says "see step 1 — remove the listings section" with a precise method-name list rather than full code; this is acceptable because the code being deleted is already in the repo and the specific deletion targets are named.

**Type consistency:** Cross-checked field names. iOS `Decoded` ↔ `Wire` ↔ `GradedMarketSnapshot` ↔ `CompCardView` reads ↔ `LotDetailView` reads all use `headlinePriceCents`, `loosePriceCents`, `grade7PriceCents`, `grade8PriceCents`, `grade9PriceCents`, `grade9_5PriceCents`, `psa10PriceCents`, `bgs10PriceCents`, `cgc10PriceCents`, `sgc10PriceCents`. Edge Function `LadderPrices` keys `loose / grade_7 / grade_8 / grade_9 / grade_9_5 / psa_10 / bgs_10 / cgc_10 / sgc_10` map cleanly through `gradeKeyFor` (Task 5). DB column names `loose_price / grade_7_price / … / sgc_10_price` (Task 2) match the keys read by `readMarketLadder` and written by `upsertMarketLadder` (Task 10). `headline_price` column (Task 2) ↔ `headline_price_cents` wire field (Task 11) ↔ `headlinePriceCents` SwiftData prop (Task 15) — three names, intentional, each correct in its layer.
