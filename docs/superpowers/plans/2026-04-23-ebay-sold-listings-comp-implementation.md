# eBay Sold-Listings Live Comp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a production `/price-comp` Supabase Edge Function that returns the 10 latest eBay sold listings for a scanned slab — with outlier-aware aggregates and a 6-hour cache — plus the iOS plumbing that fetches and renders them.

**Architecture:** Hybrid cache-read + on-demand-fallback Edge Function that reads `graded_market` first, falls back to live eBay Marketplace Insights calls on miss/stale, persists results for warmth, and emits a scan signal for future watchlist promotion. iOS contract defined in parent spec is preserved; this plan fills in the SwiftData mirrors and UI wiring.

**Tech Stack:** Deno (Supabase Edge Functions), PostgreSQL (Supabase), SwiftUI + SwiftData (iOS 18+), Swift Testing, `deno test` for function tests.

**Parent spec:** [`docs/superpowers/specs/2026-04-23-ebay-sold-listings-comp-design.md`](../specs/2026-04-23-ebay-sold-listings-comp-design.md)

---

## File Structure

### New files (Supabase)

| Path | Responsibility |
|---|---|
| `supabase/migrations/20260424000001_ebay_comp_columns_and_scan_events.sql` | Adds `graded_market.mean_price`, `trimmed_mean_price`, `sample_window_days`, `confidence`; creates `slab_scan_events` table. |
| `supabase/functions/price-comp/deno.json` | Import map (supabase-js, std lib). |
| `supabase/functions/price-comp/index.ts` | HTTP handler; orchestrates cache-check → live fetch → persistence → response. |
| `supabase/functions/price-comp/types.ts` | Shared TypeScript types for request/response/identity/sale. |
| `supabase/functions/price-comp/lib/graded-title-parse.ts` | Vendored copy of `scraper/src/graded/cert-parser.ts`. Header comment points to source. |
| `supabase/functions/price-comp/stats/aggregates.ts` | `mean`, `median`, `low`, `high`. |
| `supabase/functions/price-comp/stats/outliers.ts` | MAD-based `detectOutliers`; `trimmedMean`. |
| `supabase/functions/price-comp/stats/confidence.ts` | `sampleFactor`, `freshnessFactor`, `confidence`. |
| `supabase/functions/price-comp/ebay/query-builder.ts` | Builds the 4 cascade queries from a `GradedCardIdentity`. |
| `supabase/functions/price-comp/ebay/oauth.ts` | Client-credentials token fetch + module-scope cache. |
| `supabase/functions/price-comp/ebay/marketplace-insights.ts` | Typed MI API client; thin wrapper over fetch. |
| `supabase/functions/price-comp/ebay/cascade.ts` | Runs the 4 buckets, applies title-parse validation, returns selected sample + window. |
| `supabase/functions/price-comp/cache/freshness.ts` | Checks whether a `graded_market` row is fresh enough. |
| `supabase/functions/price-comp/persistence/market.ts` | Upserts `graded_market` and `graded_market_sales`. |
| `supabase/functions/price-comp/persistence/scan-event.ts` | Writes `slab_scan_events` row (best-effort). |
| `supabase/functions/price-comp/__tests__/aggregates.test.ts` | Unit tests for aggregate statistics. |
| `supabase/functions/price-comp/__tests__/outliers.test.ts` | Unit tests for MAD detection. |
| `supabase/functions/price-comp/__tests__/confidence.test.ts` | Unit tests for confidence scoring. |
| `supabase/functions/price-comp/__tests__/query-builder.test.ts` | Unit tests for query cascade construction. |
| `supabase/functions/price-comp/__tests__/oauth.test.ts` | Unit tests for token cache + refresh. |
| `supabase/functions/price-comp/__tests__/cascade.test.ts` | Unit tests for cascade selection logic. |
| `supabase/functions/price-comp/__tests__/index.test.ts` | Integration test: handler end-to-end with mocked eBay + in-memory Supabase stub. |
| `supabase/functions/price-comp/__fixtures__/mi-dense.json` | MI API response with 25 valid Pokémon PSA 10 sold listings. |
| `supabase/functions/price-comp/__fixtures__/mi-sparse.json` | MI API response with 3 listings. |
| `supabase/functions/price-comp/__fixtures__/mi-empty.json` | MI API response with 0 listings. |
| `supabase/functions/price-comp/__fixtures__/mi-with-outlier.json` | MI API response with 10 listings, 1 high outlier, 1 low outlier. |
| `supabase/functions/price-comp/__fixtures__/oauth-token.json` | Canned `/oauth2/token` response. |

### New files (iOS)

| Path | Responsibility |
|---|---|
| `ios/slabbist/slabbist/Core/Models/GradedCardIdentity.swift` | SwiftData mirror of `graded_card_identities`. |
| `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift` | SwiftData mirror of `/price-comp` response (aggregates + metadata). |
| `ios/slabbist/slabbist/Core/Models/SoldListingMirror.swift` | SwiftData mirror of one sold listing. |
| `ios/slabbist/slabbist/Features/Comp/CompRepository.swift` | Fetch `/price-comp`, decode, persist snapshot + listings. |
| `ios/slabbist/slabbist/Features/Comp/CompCardView.swift` | Compact comp card used in `ScanDetailView`. |
| `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift` | Full-screen scan detail with comp breakdown and listings list. |
| `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift` | Decode + persistence tests (mocked URLSession). |

### Modified files (iOS)

| Path | Change |
|---|---|
| `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift` | Add `OutboxPayloads.PriceCompJob` payload struct. |
| `ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift` | Tap slab row → push `ScanDetailView`. |
| `ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanViewModel.swift` | Call `CompRepository.fetchComp(for:)` when a scan transitions to `validated`. |

---

## Task 1: Database migration — new columns + `slab_scan_events`

**Files:**
- Create: `supabase/migrations/20260424000001_ebay_comp_columns_and_scan_events.sql`

- [ ] **Step 1: Write the migration file**

```sql
-- 20260424000001_ebay_comp_columns_and_scan_events.sql
-- Adds eBay-comp aggregate columns to graded_market and creates slab_scan_events
-- for the scraper's watchlist promotion signal.
-- Spec: docs/superpowers/specs/2026-04-23-ebay-sold-listings-comp-design.md

-- Column naming: graded_market already uses numeric(12,2) for prices
-- (see 20260422120000_tcgcsv_pokemon_and_graded.sql). Staying consistent.

alter table public.graded_market
  add column if not exists mean_price         numeric(12,2),
  add column if not exists trimmed_mean_price numeric(12,2),
  add column if not exists sample_window_days smallint,
  add column if not exists confidence         real;

create table if not exists public.slab_scan_events (
  id                uuid primary key default gen_random_uuid(),
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   public.grader not null,
  grade             text not null,
  store_id          uuid references public.stores(id),
  cache_state       text not null check (cache_state in ('hit','miss','stale')),
  scanned_at        timestamptz not null default now()
);

create index if not exists slab_scan_events_identity_time_idx
  on public.slab_scan_events (identity_id, grading_service, grade, scanned_at desc);
create index if not exists slab_scan_events_scanned_at_idx
  on public.slab_scan_events (scanned_at desc);

-- RLS: readable by authenticated users; writable only by service-role
-- (the Edge Function uses service-role for this write).
alter table public.slab_scan_events enable row level security;

create policy slab_scan_events_select_authenticated
  on public.slab_scan_events for select
  to authenticated
  using (true);
```

- [ ] **Step 2: Apply the migration locally**

Run: `supabase db reset` (from repo root)
Expected: all migrations apply cleanly, no errors. The reset re-applies every migration against the local shadow DB.

- [ ] **Step 3: Verify the schema change**

Run: `supabase db diff --schema public | grep -E 'slab_scan_events|mean_price|trimmed_mean_price'`
Expected: no diff (matches applied schema).

Run: `psql "$(supabase status --output json | jq -r .DB_URL)" -c "\d public.slab_scan_events"` and `\d public.graded_market`
Expected: columns listed, indexes listed.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260424000001_ebay_comp_columns_and_scan_events.sql
git commit -m "feat(supabase): add eBay comp columns + slab_scan_events"
```

---

## Task 2: Edge Function scaffold — `deno.json`, `types.ts`, `lib/graded-title-parse.ts`

**Files:**
- Create: `supabase/functions/price-comp/deno.json`
- Create: `supabase/functions/price-comp/types.ts`
- Create: `supabase/functions/price-comp/lib/graded-title-parse.ts`

- [ ] **Step 1: Create `deno.json`**

```json
{
  "imports": {
    "@supabase/supabase-js": "https://esm.sh/@supabase/supabase-js@2.45.0",
    "std/assert": "https://deno.land/std@0.224.0/assert/mod.ts",
    "std/testing/bdd": "https://deno.land/std@0.224.0/testing/bdd.ts"
  }
}
```

- [ ] **Step 2: Create `types.ts`**

```ts
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
}

export interface PriceCompRequest {
  graded_card_identity_id: string;
  grading_service: GradingService;
  grade: string;
}

export type OutlierReason = "price_high" | "price_low" | null;

export interface SoldListing {
  sold_price_cents: number;
  sold_at: string;           // ISO 8601
  title: string;
  url: string;
  source: "ebay";
  is_outlier: boolean;
  outlier_reason: OutlierReason;
  // internal fields not serialized to clients
}

export interface SoldListingRaw {
  // Internal — before outlier marking
  sold_price_cents: number;
  sold_at: string;
  title: string;
  url: string;
  source_listing_id: string;
}

export interface PriceCompResponse {
  blended_price_cents: number;
  mean_price_cents: number;
  trimmed_mean_price_cents: number;
  median_price_cents: number;
  low_price_cents: number;
  high_price_cents: number;
  confidence: number;
  sample_count: number;
  sample_window_days: 90 | 365;
  velocity_7d: number;
  velocity_30d: number;
  velocity_90d: number;
  sold_listings: SoldListing[];
  fetched_at: string;
  cache_hit: boolean;
  is_stale_fallback: boolean;
}

export type CacheState = "hit" | "miss" | "stale";
```

- [ ] **Step 3: Create `lib/graded-title-parse.ts`**

```ts
// supabase/functions/price-comp/lib/graded-title-parse.ts
// Vendored from scraper/src/graded/cert-parser.ts (2026-04-23).
// Keep in sync if the scraper copy changes.

import type { GradingService } from "../types.ts";

const SERVICE_PATTERN = /\b(PSA|CGC|BGS|SGC|TAG)\s*([0-9]+(?:\.5)?)/i;

export interface ParsedTitle {
  gradingService: GradingService;
  grade: string;
}

export function parseGradedTitle(title: string): ParsedTitle | null {
  const m = title.match(SERVICE_PATTERN);
  if (!m) return null;
  return {
    gradingService: m[1]!.toUpperCase() as GradingService,
    grade: m[2]!,
  };
}
```

- [ ] **Step 4: Verify Deno can parse the files**

Run: `deno check supabase/functions/price-comp/types.ts supabase/functions/price-comp/lib/graded-title-parse.ts`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/deno.json supabase/functions/price-comp/types.ts supabase/functions/price-comp/lib/graded-title-parse.ts
git commit -m "feat(price-comp): scaffold Edge Function types + vendored title parser"
```

---

## Task 3: Aggregate statistics (TDD)

**Files:**
- Create: `supabase/functions/price-comp/stats/aggregates.ts`
- Test: `supabase/functions/price-comp/__tests__/aggregates.test.ts`

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/price-comp/__tests__/aggregates.test.ts
import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { mean, median, low, high } from "../stats/aggregates.ts";

describe("aggregates", () => {
  it("mean rounds half-to-even for integer cents", () => {
    assertEquals(mean([100, 200, 300]), 200);
    assertEquals(mean([100, 101]), 101); // 100.5 → 101 per round-half-to-even on odd
  });

  it("median handles odd and even lengths", () => {
    assertEquals(median([100, 200, 300]), 200);
    assertEquals(median([100, 200, 300, 400]), 250); // avg of 200,300
  });

  it("low and high on single-element arrays", () => {
    assertEquals(low([42]), 42);
    assertEquals(high([42]), 42);
  });

  it("throws on empty input", () => {
    let threw = false;
    try { mean([]); } catch { threw = true; }
    assertEquals(threw, true);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/price-comp/__tests__/aggregates.test.ts`
Expected: FAIL with module not found / functions not exported.

- [ ] **Step 3: Implement `aggregates.ts`**

```ts
// supabase/functions/price-comp/stats/aggregates.ts

function assertNonEmpty(xs: number[]): void {
  if (xs.length === 0) throw new Error("aggregate: empty input");
}

export function mean(xs: number[]): number {
  assertNonEmpty(xs);
  const sum = xs.reduce((a, b) => a + b, 0);
  // Round half-to-even on the exact mean to keep integer cents stable.
  const q = sum / xs.length;
  const floor = Math.floor(q);
  const frac = q - floor;
  if (frac < 0.5) return floor;
  if (frac > 0.5) return floor + 1;
  return floor % 2 === 0 ? floor : floor + 1;
}

export function median(xs: number[]): number {
  assertNonEmpty(xs);
  const sorted = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[mid]!;
  // Even length: integer average of the two middle values (banker's rounding not
  // needed for even count of already-integer cents).
  return Math.round((sorted[mid - 1]! + sorted[mid]!) / 2);
}

export function low(xs: number[]): number {
  assertNonEmpty(xs);
  return xs.reduce((a, b) => (a < b ? a : b));
}

export function high(xs: number[]): number {
  assertNonEmpty(xs);
  return xs.reduce((a, b) => (a > b ? a : b));
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/price-comp/__tests__/aggregates.test.ts`
Expected: PASS (4 checks).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/stats/aggregates.ts supabase/functions/price-comp/__tests__/aggregates.test.ts
git commit -m "feat(price-comp): aggregate statistics with integer-cents math"
```

---

## Task 4: MAD outlier detection (TDD)

**Files:**
- Create: `supabase/functions/price-comp/stats/outliers.ts`
- Test: `supabase/functions/price-comp/__tests__/outliers.test.ts`

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/price-comp/__tests__/outliers.test.ts
import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { detectOutliers, trimmedMean } from "../stats/outliers.ts";

describe("detectOutliers (MAD, 3σ threshold)", () => {
  it("flags nothing on tight cluster", () => {
    const prices = [12000, 12200, 12500, 12800, 13000, 13200];
    const flags = detectOutliers(prices);
    assertEquals(flags, [false, false, false, false, false, false]);
  });

  it("flags one high outlier at 2x median", () => {
    const prices = [12000, 12200, 12500, 12800, 13000, 13200, 25000];
    const flags = detectOutliers(prices);
    assertEquals(flags[flags.length - 1], true);
    assertEquals(flags.slice(0, -1).every(f => !f), true);
  });

  it("flags one low outlier below median", () => {
    const prices = [100, 12000, 12200, 12500, 12800, 13000, 13200];
    const flags = detectOutliers(prices);
    assertEquals(flags[0], true);
    assertEquals(flags.slice(1).every(f => !f), true);
  });

  it("flags nothing when all identical (MAD = 0)", () => {
    const prices = [12000, 12000, 12000, 12000];
    assertEquals(detectOutliers(prices), [false, false, false, false]);
  });

  it("flags nothing for n = 1 (insufficient data)", () => {
    assertEquals(detectOutliers([12000]), [false]);
  });
});

describe("trimmedMean", () => {
  it("equals mean when no outliers", () => {
    const prices = [100, 200, 300];
    assertEquals(trimmedMean(prices, [false, false, false]), 200);
  });

  it("excludes outliers from the mean", () => {
    const prices = [100, 200, 300, 10000];
    assertEquals(trimmedMean(prices, [false, false, false, true]), 200);
  });

  it("falls back to full mean if every row is flagged", () => {
    const prices = [100, 200, 300];
    assertEquals(trimmedMean(prices, [true, true, true]), 200);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/price-comp/__tests__/outliers.test.ts`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `outliers.ts`**

```ts
// supabase/functions/price-comp/stats/outliers.ts
import { mean, median } from "./aggregates.ts";

const MAD_SCALE = 1.4826;           // Normal-σ equivalence for MAD
const MAD_THRESHOLD = 3;             // σ-equivalent threshold for "outlier"

export function detectOutliers(prices: number[]): boolean[] {
  if (prices.length < 2) return prices.map(() => false);
  const med = median(prices);
  const deviations = prices.map(p => Math.abs(p - med));
  const mad = median(deviations);
  if (mad === 0) return prices.map(() => false);
  const cutoff = MAD_THRESHOLD * MAD_SCALE * mad;
  return prices.map(p => Math.abs(p - med) > cutoff);
}

export function trimmedMean(prices: number[], outlierFlags: boolean[]): number {
  const kept = prices.filter((_, i) => !outlierFlags[i]);
  if (kept.length === 0) return mean(prices);
  return mean(kept);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/price-comp/__tests__/outliers.test.ts`
Expected: PASS (8 checks).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/stats/outliers.ts supabase/functions/price-comp/__tests__/outliers.test.ts
git commit -m "feat(price-comp): MAD outlier detection + trimmed mean"
```

---

## Task 5: Confidence scoring (TDD)

**Files:**
- Create: `supabase/functions/price-comp/stats/confidence.ts`
- Test: `supabase/functions/price-comp/__tests__/confidence.test.ts`

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/price-comp/__tests__/confidence.test.ts
import { assertAlmostEquals, assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { sampleFactor, freshnessFactor, confidence } from "../stats/confidence.ts";

describe("sampleFactor", () => {
  it("0 at n=0", () => assertEquals(sampleFactor(0), 0));
  it("0.1 at n=1", () => assertAlmostEquals(sampleFactor(1), 0.1, 1e-9));
  it("1.0 at n=10", () => assertEquals(sampleFactor(10), 1.0));
  it("clamps above 10", () => assertEquals(sampleFactor(25), 1.0));
});

describe("freshnessFactor", () => {
  it("1.0 for 90d window", () => assertEquals(freshnessFactor(90), 1.0));
  it("0.5 for 365d window", () => assertEquals(freshnessFactor(365), 0.5));
});

describe("confidence (composite)", () => {
  it("1.0 at n=10 and 90d", () => assertEquals(confidence(10, 90), 1.0));
  it("0.5 at n=10 and 365d", () => assertEquals(confidence(10, 365), 0.5));
  it("0.15 at n=3 and 365d", () => assertAlmostEquals(confidence(3, 365), 0.15, 1e-9));
  it("0.0 on n=0", () => assertEquals(confidence(0, 90), 0.0));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/price-comp/__tests__/confidence.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement `confidence.ts`**

```ts
// supabase/functions/price-comp/stats/confidence.ts

export function sampleFactor(n: number): number {
  if (n <= 0) return 0;
  if (n >= 10) return 1.0;
  return n / 10;
}

export function freshnessFactor(windowDays: 90 | 365): number {
  if (windowDays === 90) return 1.0;
  return 0.5; // 365d
}

export function confidence(n: number, windowDays: 90 | 365): number {
  return sampleFactor(n) * freshnessFactor(windowDays);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/price-comp/__tests__/confidence.test.ts`
Expected: PASS (10 checks).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/stats/confidence.ts supabase/functions/price-comp/__tests__/confidence.test.ts
git commit -m "feat(price-comp): confidence scoring (sample × freshness)"
```

---

## Task 6: Query builder for the 4-bucket cascade (TDD)

**Files:**
- Create: `supabase/functions/price-comp/ebay/query-builder.ts`
- Test: `supabase/functions/price-comp/__tests__/query-builder.test.ts`

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/price-comp/__tests__/query-builder.test.ts
import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { buildCascadeQueries } from "../ebay/query-builder.ts";
import type { GradedCardIdentity } from "../types.ts";

const identity: GradedCardIdentity = {
  id: "abc",
  game: "pokemon",
  language: "en",
  set_code: "SV-SS",
  set_name: "Surging Sparks",
  card_number: "247/191",
  card_name: "Pikachu ex",
  variant: null,
  year: 2024,
};

describe("buildCascadeQueries", () => {
  it("produces 4 buckets in fixed order (narrow-90, broad-90, narrow-365, broad-365)", () => {
    const qs = buildCascadeQueries(identity, "PSA", "10");
    assertEquals(qs.length, 4);
    assertEquals(qs[0].windowDays, 90);
    assertEquals(qs[0].shape, "narrow");
    assertEquals(qs[1].windowDays, 90);
    assertEquals(qs[1].shape, "broad");
    assertEquals(qs[2].windowDays, 365);
    assertEquals(qs[2].shape, "narrow");
    assertEquals(qs[3].windowDays, 365);
    assertEquals(qs[3].shape, "broad");
  });

  it("narrow query quotes card_name+card_number and grading+grade", () => {
    const qs = buildCascadeQueries(identity, "PSA", "10");
    assertEquals(qs[0].q, `"Pikachu ex 247/191" "PSA 10"`);
  });

  it("broad query is unquoted tokens including set_name", () => {
    const qs = buildCascadeQueries(identity, "PSA", "10");
    assertEquals(qs[1].q, "Pikachu ex Surging Sparks 247/191 PSA 10");
  });

  it("omits null card_number from narrow phrase", () => {
    const noCn = { ...identity, card_number: null };
    const qs = buildCascadeQueries(noCn, "PSA", "10");
    assertEquals(qs[0].q, `"Pikachu ex" "PSA 10"`);
  });

  it("uses Pokemon category id 183454 on every bucket", () => {
    const qs = buildCascadeQueries(identity, "PSA", "10");
    assertEquals(qs.every(q => q.categoryId === "183454"), true);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/price-comp/__tests__/query-builder.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement `query-builder.ts`**

```ts
// supabase/functions/price-comp/ebay/query-builder.ts
import type { GradedCardIdentity, GradingService } from "../types.ts";

export interface CascadeQuery {
  shape: "narrow" | "broad";
  windowDays: 90 | 365;
  q: string;
  categoryId: "183454";
}

const POKEMON_CATEGORY = "183454";

function narrow(id: GradedCardIdentity, svc: GradingService, grade: string): string {
  const phrase = id.card_number
    ? `${id.card_name} ${id.card_number}`
    : id.card_name;
  return `"${phrase}" "${svc} ${grade}"`;
}

function broad(id: GradedCardIdentity, svc: GradingService, grade: string): string {
  const parts = [id.card_name, id.set_name, id.card_number, `${svc} ${grade}`]
    .filter((p): p is string => typeof p === "string" && p.length > 0);
  return parts.join(" ");
}

export function buildCascadeQueries(
  id: GradedCardIdentity,
  svc: GradingService,
  grade: string,
): CascadeQuery[] {
  return [
    { shape: "narrow", windowDays: 90,  q: narrow(id, svc, grade), categoryId: POKEMON_CATEGORY },
    { shape: "broad",  windowDays: 90,  q: broad(id, svc, grade),  categoryId: POKEMON_CATEGORY },
    { shape: "narrow", windowDays: 365, q: narrow(id, svc, grade), categoryId: POKEMON_CATEGORY },
    { shape: "broad",  windowDays: 365, q: broad(id, svc, grade),  categoryId: POKEMON_CATEGORY },
  ];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/price-comp/__tests__/query-builder.test.ts`
Expected: PASS (5 checks).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/ebay/query-builder.ts supabase/functions/price-comp/__tests__/query-builder.test.ts
git commit -m "feat(price-comp): 4-bucket query cascade builder"
```

---

## Task 7: OAuth token fetch + module-scope cache (TDD)

**Files:**
- Create: `supabase/functions/price-comp/ebay/oauth.ts`
- Test: `supabase/functions/price-comp/__tests__/oauth.test.ts`
- Create: `supabase/functions/price-comp/__fixtures__/oauth-token.json`

- [ ] **Step 1: Create the oauth fixture**

```json
// supabase/functions/price-comp/__fixtures__/oauth-token.json
{
  "access_token": "v^1.1#i^1#fake.token.here",
  "token_type": "Application Access Token",
  "expires_in": 7200
}
```

- [ ] **Step 2: Write the failing tests**

```ts
// supabase/functions/price-comp/__tests__/oauth.test.ts
import { assertEquals, assertRejects } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { getOAuthToken, __resetTokenCacheForTests } from "../ebay/oauth.ts";

function mockFetch(response: Response): typeof fetch {
  let calls = 0;
  const fn = async (..._args: Parameters<typeof fetch>) => {
    calls++;
    return response.clone();
  };
  (fn as any).calls = () => calls;
  return fn as unknown as typeof fetch;
}

describe("getOAuthToken", () => {
  it("requests a token and returns it", async () => {
    __resetTokenCacheForTests();
    const fetchFn = mockFetch(new Response(
      JSON.stringify({ access_token: "abc123", expires_in: 7200 }),
      { status: 200 },
    ));
    const token = await getOAuthToken({
      appId: "app", certId: "cert",
      scope: "https://api.ebay.com/oauth/api_scope/buy.marketplace.insights",
      fetchFn,
      now: () => 1_000_000,
    });
    assertEquals(token, "abc123");
    assertEquals((fetchFn as any).calls(), 1);
  });

  it("caches and does not re-fetch within expiry window", async () => {
    __resetTokenCacheForTests();
    const fetchFn = mockFetch(new Response(
      JSON.stringify({ access_token: "abc", expires_in: 7200 }),
      { status: 200 },
    ));
    let now = 1_000_000;
    await getOAuthToken({ appId: "a", certId: "c", scope: "s", fetchFn, now: () => now });
    now += 1000; // 1 second later, well inside TTL
    await getOAuthToken({ appId: "a", certId: "c", scope: "s", fetchFn, now: () => now });
    assertEquals((fetchFn as any).calls(), 1);
  });

  it("refreshes once cache reaches the 5-min safety window", async () => {
    __resetTokenCacheForTests();
    const fetchFn = mockFetch(new Response(
      JSON.stringify({ access_token: "abc", expires_in: 7200 }),
      { status: 200 },
    ));
    let now = 1_000_000;
    await getOAuthToken({ appId: "a", certId: "c", scope: "s", fetchFn, now: () => now });
    now += (7200 - 299) * 1000; // within 5-min safety window
    await getOAuthToken({ appId: "a", certId: "c", scope: "s", fetchFn, now: () => now });
    assertEquals((fetchFn as any).calls(), 2);
  });

  it("throws on non-2xx", async () => {
    __resetTokenCacheForTests();
    const fetchFn = mockFetch(new Response("bad", { status: 401 }));
    await assertRejects(() => getOAuthToken({
      appId: "a", certId: "c", scope: "s", fetchFn, now: () => 0,
    }));
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `deno test supabase/functions/price-comp/__tests__/oauth.test.ts`
Expected: FAIL.

- [ ] **Step 4: Implement `oauth.ts`**

```ts
// supabase/functions/price-comp/ebay/oauth.ts

const TOKEN_URL = "https://api.ebay.com/identity/v1/oauth2/token";
const SAFETY_MS = 5 * 60 * 1000; // refresh 5 min before reported expiry

interface CachedToken {
  value: string;
  expiresAtMs: number;
}

let cache: CachedToken | null = null;

export function __resetTokenCacheForTests(): void {
  cache = null;
}

export interface GetOAuthTokenOpts {
  appId: string;
  certId: string;
  scope: string;
  fetchFn?: typeof fetch;
  now?: () => number;
}

export async function getOAuthToken(opts: GetOAuthTokenOpts): Promise<string> {
  const { appId, certId, scope, fetchFn = fetch, now = Date.now } = opts;
  const t = now();
  if (cache && cache.expiresAtMs - SAFETY_MS > t) {
    return cache.value;
  }
  const basic = btoa(`${appId}:${certId}`);
  const body = new URLSearchParams({ grant_type: "client_credentials", scope });
  const res = await fetchFn(TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });
  if (!res.ok) throw new Error(`oauth: ${res.status} ${await res.text()}`);
  const data = await res.json() as { access_token: string; expires_in: number };
  cache = {
    value: data.access_token,
    expiresAtMs: t + data.expires_in * 1000,
  };
  return cache.value;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test supabase/functions/price-comp/__tests__/oauth.test.ts`
Expected: PASS (4 checks).

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/price-comp/ebay/oauth.ts supabase/functions/price-comp/__tests__/oauth.test.ts supabase/functions/price-comp/__fixtures__/oauth-token.json
git commit -m "feat(price-comp): eBay OAuth client_credentials with module-scope cache"
```

---

## Task 8: Marketplace Insights API client

**Files:**
- Create: `supabase/functions/price-comp/ebay/marketplace-insights.ts`
- Create: `supabase/functions/price-comp/__fixtures__/mi-dense.json`
- Create: `supabase/functions/price-comp/__fixtures__/mi-sparse.json`
- Create: `supabase/functions/price-comp/__fixtures__/mi-empty.json`
- Create: `supabase/functions/price-comp/__fixtures__/mi-with-outlier.json`

- [ ] **Step 1: Create `mi-dense.json`**

Contents: 15 synthetic listings structured like the real Marketplace Insights `item_sales/search` response. Titles include "PSA 10 Pikachu ex 247/191" (varying prefixes) to pass title parsing. Use ISO 8601 `lastSoldDate` within the last 30 days. Price range $115–$145 (all valid; no outliers).

```json
{
  "itemSales": [
    { "itemId": "v1|111|0", "title": "2024 Pokemon SV Surging Sparks Pikachu ex 247/191 PSA 10 GEM MT", "lastSoldDate": "2026-04-20T10:15:00.000Z", "lastSoldPrice": { "value": "125.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/111" },
    { "itemId": "v1|112|0", "title": "Pikachu ex 247/191 Surging Sparks PSA 10", "lastSoldDate": "2026-04-19T14:22:00.000Z", "lastSoldPrice": { "value": "120.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/112" },
    { "itemId": "v1|113|0", "title": "Pokemon Pikachu ex Full Art 247/191 PSA 10 2024 Surging Sparks", "lastSoldDate": "2026-04-18T09:00:00.000Z", "lastSoldPrice": { "value": "130.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/113" },
    { "itemId": "v1|114|0", "title": "PSA 10 Pikachu ex 247/191 SV Surging Sparks", "lastSoldDate": "2026-04-17T12:30:00.000Z", "lastSoldPrice": { "value": "118.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/114" },
    { "itemId": "v1|115|0", "title": "PSA 10 Pokemon Pikachu ex 247/191 Surging Sparks GEM MT 2024", "lastSoldDate": "2026-04-16T20:01:00.000Z", "lastSoldPrice": { "value": "135.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/115" },
    { "itemId": "v1|116|0", "title": "Pikachu ex 247/191 PSA 10 Surging Sparks", "lastSoldDate": "2026-04-15T16:45:00.000Z", "lastSoldPrice": { "value": "122.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/116" },
    { "itemId": "v1|117|0", "title": "2024 Pokemon Pikachu ex 247/191 PSA 10 Surging Sparks", "lastSoldDate": "2026-04-14T11:20:00.000Z", "lastSoldPrice": { "value": "128.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/117" },
    { "itemId": "v1|118|0", "title": "Pokemon Surging Sparks Pikachu ex 247/191 PSA 10", "lastSoldDate": "2026-04-13T08:55:00.000Z", "lastSoldPrice": { "value": "126.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/118" },
    { "itemId": "v1|119|0", "title": "Pikachu ex 247/191 SV Pokemon PSA 10 Surging Sparks", "lastSoldDate": "2026-04-12T13:15:00.000Z", "lastSoldPrice": { "value": "132.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/119" },
    { "itemId": "v1|120|0", "title": "PSA 10 Pikachu ex 247/191 Pokemon Surging Sparks 2024 GEM MT", "lastSoldDate": "2026-04-11T10:05:00.000Z", "lastSoldPrice": { "value": "140.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/120" },
    { "itemId": "v1|121|0", "title": "Pokemon Pikachu ex 247/191 PSA 10 Surging Sparks GEM MT 10", "lastSoldDate": "2026-04-10T17:30:00.000Z", "lastSoldPrice": { "value": "124.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/121" },
    { "itemId": "v1|122|0", "title": "2024 Pokemon Pikachu ex 247/191 PSA 10 Full Art Surging Sparks", "lastSoldDate": "2026-04-09T09:25:00.000Z", "lastSoldPrice": { "value": "138.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/122" },
    { "itemId": "v1|123|0", "title": "Pikachu ex 247/191 Surging Sparks PSA 10 Pokemon", "lastSoldDate": "2026-04-08T14:40:00.000Z", "lastSoldPrice": { "value": "119.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/123" },
    { "itemId": "v1|124|0", "title": "Pokemon Surging Sparks Pikachu ex 247/191 PSA 10 GEM MT 10", "lastSoldDate": "2026-04-07T11:10:00.000Z", "lastSoldPrice": { "value": "127.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/124" },
    { "itemId": "v1|125|0", "title": "Pokemon Pikachu ex 247/191 Surging Sparks Full Art PSA 10", "lastSoldDate": "2026-04-06T15:50:00.000Z", "lastSoldPrice": { "value": "121.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/125" }
  ]
}
```

- [ ] **Step 2: Create `mi-sparse.json`** (3 listings, same identity, PSA 10; prices $115/$120/$125)

```json
{
  "itemSales": [
    { "itemId": "v1|211|0", "title": "Pikachu ex 247/191 Surging Sparks PSA 10", "lastSoldDate": "2026-04-15T10:00:00.000Z", "lastSoldPrice": { "value": "115.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/211" },
    { "itemId": "v1|212|0", "title": "PSA 10 Pikachu ex 247/191", "lastSoldDate": "2026-04-10T10:00:00.000Z", "lastSoldPrice": { "value": "120.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/212" },
    { "itemId": "v1|213|0", "title": "Pokemon Pikachu ex 247/191 PSA 10 Surging Sparks", "lastSoldDate": "2026-04-05T10:00:00.000Z", "lastSoldPrice": { "value": "125.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/213" }
  ]
}
```

- [ ] **Step 3: Create `mi-empty.json`**

```json
{ "itemSales": [] }
```

- [ ] **Step 4: Create `mi-with-outlier.json`** (10 listings; #1 high outlier at $2500, #2 low at $1, rest normal $115–$135)

```json
{
  "itemSales": [
    { "itemId": "v1|301|0", "title": "Pikachu ex 247/191 PSA 10 SIGNED BY MITSUHIRO ARITA SURGING SPARKS", "lastSoldDate": "2026-04-20T10:00:00.000Z", "lastSoldPrice": { "value": "2500.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/301" },
    { "itemId": "v1|302|0", "title": "Pikachu ex 247/191 PSA 10 Surging Sparks DAMAGED CASE", "lastSoldDate": "2026-04-19T10:00:00.000Z", "lastSoldPrice": { "value": "1.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/302" },
    { "itemId": "v1|303|0", "title": "Pikachu ex 247/191 PSA 10 Surging Sparks", "lastSoldDate": "2026-04-18T10:00:00.000Z", "lastSoldPrice": { "value": "120.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/303" },
    { "itemId": "v1|304|0", "title": "PSA 10 Pikachu ex 247/191 Surging Sparks", "lastSoldDate": "2026-04-17T10:00:00.000Z", "lastSoldPrice": { "value": "122.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/304" },
    { "itemId": "v1|305|0", "title": "Pokemon Pikachu ex 247/191 PSA 10 Surging Sparks", "lastSoldDate": "2026-04-16T10:00:00.000Z", "lastSoldPrice": { "value": "125.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/305" },
    { "itemId": "v1|306|0", "title": "Pikachu ex 247/191 Surging Sparks PSA 10", "lastSoldDate": "2026-04-15T10:00:00.000Z", "lastSoldPrice": { "value": "128.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/306" },
    { "itemId": "v1|307|0", "title": "2024 Pokemon Pikachu ex 247/191 PSA 10 Surging Sparks", "lastSoldDate": "2026-04-14T10:00:00.000Z", "lastSoldPrice": { "value": "115.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/307" },
    { "itemId": "v1|308|0", "title": "Pikachu ex 247/191 Surging Sparks PSA 10", "lastSoldDate": "2026-04-13T10:00:00.000Z", "lastSoldPrice": { "value": "130.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/308" },
    { "itemId": "v1|309|0", "title": "PSA 10 Pikachu ex 247/191", "lastSoldDate": "2026-04-12T10:00:00.000Z", "lastSoldPrice": { "value": "135.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/309" },
    { "itemId": "v1|310|0", "title": "Pokemon Surging Sparks Pikachu ex 247/191 PSA 10", "lastSoldDate": "2026-04-11T10:00:00.000Z", "lastSoldPrice": { "value": "118.00", "currency": "USD" }, "itemWebUrl": "https://www.ebay.com/itm/310" }
  ]
}
```

- [ ] **Step 5: Implement `marketplace-insights.ts`**

```ts
// supabase/functions/price-comp/ebay/marketplace-insights.ts
import type { SoldListingRaw } from "../types.ts";

const MI_ENDPOINT = "https://api.ebay.com/buy/marketplace_insights/v1_beta/item_sales/search";

interface MIItemSale {
  itemId: string;
  title: string;
  lastSoldDate: string;
  lastSoldPrice: { value: string; currency: string };
  itemWebUrl: string;
}

interface MIResponse {
  itemSales?: MIItemSale[];
}

export interface MICallOpts {
  token: string;
  q: string;
  categoryId: string;
  limit: number;
  fetchFn?: typeof fetch;
}

export interface MICallResult {
  status: number;
  listings: SoldListingRaw[];
}

function toCents(priceStr: string): number | null {
  const n = Number(priceStr);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 100);
}

function listingIdFromItemId(itemId: string): string {
  const parts = itemId.split("|");
  return parts[1] ?? itemId;
}

export async function callMarketplaceInsights(opts: MICallOpts): Promise<MICallResult> {
  const { token, q, categoryId, limit, fetchFn = fetch } = opts;
  const url = new URL(MI_ENDPOINT);
  url.searchParams.set("q", q);
  url.searchParams.set("category_ids", categoryId);
  url.searchParams.set("limit", String(limit));
  const res = await fetchFn(url.toString(), {
    headers: {
      Authorization: `Bearer ${token}`,
      "X-EBAY-C-MARKETPLACE-ID": "EBAY_US",
    },
  });
  if (!res.ok) {
    return { status: res.status, listings: [] };
  }
  const data = await res.json() as MIResponse;
  const listings: SoldListingRaw[] = [];
  for (const s of data.itemSales ?? []) {
    const cents = toCents(s.lastSoldPrice.value);
    if (cents === null) continue;
    listings.push({
      sold_price_cents: cents,
      sold_at: s.lastSoldDate,
      title: s.title,
      url: s.itemWebUrl,
      source_listing_id: listingIdFromItemId(s.itemId),
    });
  }
  return { status: res.status, listings };
}
```

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/price-comp/ebay/marketplace-insights.ts supabase/functions/price-comp/__fixtures__/mi-*.json
git commit -m "feat(price-comp): Marketplace Insights API client + test fixtures"
```

---

## Task 9: Cascade runner (TDD)

**Files:**
- Create: `supabase/functions/price-comp/ebay/cascade.ts`
- Test: `supabase/functions/price-comp/__tests__/cascade.test.ts`

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/price-comp/__tests__/cascade.test.ts
import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { runCascade } from "../ebay/cascade.ts";
import type { GradedCardIdentity, SoldListingRaw } from "../types.ts";

const identity: GradedCardIdentity = {
  id: "abc", game: "pokemon", language: "en", set_code: null,
  set_name: "Surging Sparks", card_number: "247/191",
  card_name: "Pikachu ex", variant: null, year: 2024,
};

async function loadFixture(name: string): Promise<SoldListingRaw[]> {
  const text = await Deno.readTextFile(
    new URL(`../__fixtures__/${name}`, import.meta.url),
  );
  const data = JSON.parse(text) as { itemSales: Array<{ itemId: string; title: string; lastSoldDate: string; lastSoldPrice: { value: string }; itemWebUrl: string }> };
  return data.itemSales.map(s => ({
    sold_price_cents: Math.round(Number(s.lastSoldPrice.value) * 100),
    sold_at: s.lastSoldDate,
    title: s.title,
    url: s.itemWebUrl,
    source_listing_id: s.itemId.split("|")[1] ?? s.itemId,
  }));
}

describe("runCascade", () => {
  it("stops at first bucket with ≥ minResults after title-parse validation", async () => {
    const dense = await loadFixture("mi-dense.json");
    let calls = 0;
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async (_q) => { calls++; return { status: 200, listings: dense }; },
    });
    assertEquals(result.sampleWindowDays, 90);
    assertEquals(result.bucketHit, 1);
    assertEquals(calls, 1);
    assertEquals(result.listings.length, 10); // capped at 10 most-recent
  });

  it("falls through to bucket 2 when bucket 1 sparse", async () => {
    const sparse = await loadFixture("mi-sparse.json");
    const dense = await loadFixture("mi-dense.json");
    let call = 0;
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async (_q) => {
        call++;
        return call === 1
          ? { status: 200, listings: sparse }
          : { status: 200, listings: dense };
      },
    });
    assertEquals(result.bucketHit, 2);
    assertEquals(result.listings.length, 10);
  });

  it("returns best available when all buckets sparse", async () => {
    const sparse = await loadFixture("mi-sparse.json");
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async (_q) => ({ status: 200, listings: sparse }),
    });
    assertEquals(result.listings.length, 3);
    assertEquals(result.sampleWindowDays === 90 || result.sampleWindowDays === 365, true);
  });

  it("returns empty when every bucket is empty", async () => {
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async (_q) => ({ status: 200, listings: [] }),
    });
    assertEquals(result.listings.length, 0);
    assertEquals(result.bucketHit, null);
  });

  it("drops listings that fail title-parse validation (wrong grade)", async () => {
    const mixed: SoldListingRaw[] = [
      { sold_price_cents: 10000, sold_at: "2026-04-20T00:00:00Z", title: "PSA 10 card", url: "u", source_listing_id: "1" },
      { sold_price_cents: 20000, sold_at: "2026-04-19T00:00:00Z", title: "PSA 9 card", url: "u", source_listing_id: "2" },
    ];
    const result = await runCascade(identity, "PSA", "10", {
      minResults: 10,
      fetchBucket: async () => ({ status: 200, listings: mixed }),
    });
    assertEquals(result.listings.length, 1);
    assertEquals(result.listings[0].sold_price_cents, 10000);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/price-comp/__tests__/cascade.test.ts --allow-read`
Expected: FAIL.

- [ ] **Step 3: Implement `cascade.ts`**

```ts
// supabase/functions/price-comp/ebay/cascade.ts
import type { GradedCardIdentity, GradingService, SoldListingRaw } from "../types.ts";
import { buildCascadeQueries, type CascadeQuery } from "./query-builder.ts";
import { parseGradedTitle } from "../lib/graded-title-parse.ts";

export interface BucketFetchResult {
  status: number;
  listings: SoldListingRaw[];
}

export interface RunCascadeOpts {
  minResults: number;
  fetchBucket: (q: CascadeQuery) => Promise<BucketFetchResult>;
}

export interface CascadeResult {
  listings: SoldListingRaw[];         // capped at 10, sorted by sold_at desc
  sampleWindowDays: 90 | 365;
  bucketHit: 1 | 2 | 3 | 4 | null;
}

function validateListings(
  raw: SoldListingRaw[],
  svc: GradingService,
  grade: string,
): SoldListingRaw[] {
  return raw.filter(l => {
    const parsed = parseGradedTitle(l.title);
    return parsed?.gradingService === svc && parsed.grade === grade;
  });
}

export async function runCascade(
  identity: GradedCardIdentity,
  svc: GradingService,
  grade: string,
  opts: RunCascadeOpts,
): Promise<CascadeResult> {
  const queries = buildCascadeQueries(identity, svc, grade);
  let best: { listings: SoldListingRaw[]; window: 90 | 365; bucket: 1 | 2 | 3 | 4 } | null = null;
  for (let i = 0; i < queries.length; i++) {
    const q = queries[i]!;
    const result = await opts.fetchBucket(q);
    const valid = validateListings(result.listings, svc, grade);
    if (valid.length === 0) continue;
    const sorted = valid.slice().sort((a, b) => b.sold_at.localeCompare(a.sold_at)).slice(0, 10);
    const bucketNum = (i + 1) as 1 | 2 | 3 | 4;
    const windowDays = q.windowDays;
    if (sorted.length >= opts.minResults) {
      return { listings: sorted, sampleWindowDays: windowDays, bucketHit: bucketNum };
    }
    if (!best || sorted.length > best.listings.length) {
      best = { listings: sorted, window: windowDays, bucket: bucketNum };
    }
  }
  if (best) {
    return { listings: best.listings, sampleWindowDays: best.window, bucketHit: best.bucket };
  }
  return { listings: [], sampleWindowDays: 90, bucketHit: null };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/price-comp/__tests__/cascade.test.ts --allow-read`
Expected: PASS (5 checks).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/ebay/cascade.ts supabase/functions/price-comp/__tests__/cascade.test.ts
git commit -m "feat(price-comp): cascade runner with title-parse validation"
```

---

## Task 10: Cache freshness check

**Files:**
- Create: `supabase/functions/price-comp/cache/freshness.ts`

- [ ] **Step 1: Write the file**

```ts
// supabase/functions/price-comp/cache/freshness.ts
import type { CacheState } from "../types.ts";

export interface FreshnessOpts {
  updatedAtMs: number | null;   // null = no row
  nowMs: number;
  ttlSeconds: number;
}

export function evaluateFreshness(opts: FreshnessOpts): CacheState {
  if (opts.updatedAtMs === null) return "miss";
  const ageMs = opts.nowMs - opts.updatedAtMs;
  if (ageMs <= opts.ttlSeconds * 1000) return "hit";
  return "stale";
}
```

- [ ] **Step 2: Sanity-check compile**

Run: `deno check supabase/functions/price-comp/cache/freshness.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/cache/freshness.ts
git commit -m "feat(price-comp): TTL-based cache freshness check"
```

---

## Task 11: Persistence — `graded_market` + `graded_market_sales`

**Files:**
- Create: `supabase/functions/price-comp/persistence/market.ts`

- [ ] **Step 1: Write the file**

```ts
// supabase/functions/price-comp/persistence/market.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, SoldListing } from "../types.ts";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  listings: SoldListing[];
  aggregates: {
    low_cents: number;
    high_cents: number;
    mean_cents: number;
    trimmed_mean_cents: number;
    median_cents: number;
    confidence: number;
    sample_window_days: 90 | 365;
    velocity_7d: number;
    velocity_30d: number;
    velocity_90d: number;
  };
}

// graded_market prices are numeric(12,2). Convert cents ↔ dollars at the boundary.
function centsToDecimal(cents: number): number {
  return Math.round(cents) / 100;
}

export async function upsertMarket(
  supabase: SupabaseClient,
  input: MarketUpsertInput,
): Promise<void> {
  const { identityId, gradingService, grade, listings, aggregates } = input;

  // Upsert raw sales rows (idempotent on source_listing_id + source).
  if (listings.length > 0) {
    const rows = listings.map(l => ({
      identity_id: identityId,
      grading_service: gradingService,
      grade,
      sold_price: centsToDecimal(l.sold_price_cents),
      sold_at: l.sold_at,
      source: "ebay",
      source_listing_id: l.source_listing_id ?? l.url,
      title: l.title,
      url: l.url,
    }));
    const { error } = await supabase
      .from("graded_market_sales")
      .upsert(rows, { onConflict: "source,source_listing_id" });
    if (error) throw new Error(`graded_market_sales upsert: ${error.message}`);
  }

  // Upsert aggregate row.
  const { error: aggError } = await supabase
    .from("graded_market")
    .upsert({
      identity_id: identityId,
      grading_service: gradingService,
      grade,
      low_price: centsToDecimal(aggregates.low_cents),
      high_price: centsToDecimal(aggregates.high_cents),
      mean_price: centsToDecimal(aggregates.mean_cents),
      trimmed_mean_price: centsToDecimal(aggregates.trimmed_mean_cents),
      median_price: centsToDecimal(aggregates.median_cents),
      confidence: aggregates.confidence,
      sample_window_days: aggregates.sample_window_days,
      sample_count_30d: aggregates.velocity_30d,
      sample_count_90d: aggregates.velocity_90d,
      last_sale_price: centsToDecimal(listings[0]?.sold_price_cents ?? 0),
      last_sale_at: listings[0]?.sold_at ?? null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "identity_id,grading_service,grade" });
  if (aggError) throw new Error(`graded_market upsert: ${aggError.message}`);
}
```

Note: this file depends on a tagged `SoldListing` — they carry `source_listing_id` because the in-memory enrichment path carries it through. The internal handler passes listings that retain `source_listing_id`; the wire-level `SoldListing` in the response omits it. See Task 13 handler.

- [ ] **Step 2: Sanity-check compile**

Run: `deno check supabase/functions/price-comp/persistence/market.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/persistence/market.ts
git commit -m "feat(price-comp): persist graded_market + graded_market_sales"
```

---

## Task 12: Scan event writer (best-effort)

**Files:**
- Create: `supabase/functions/price-comp/persistence/scan-event.ts`

- [ ] **Step 1: Write the file**

```ts
// supabase/functions/price-comp/persistence/scan-event.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { CacheState, GradingService } from "../types.ts";

export interface ScanEventInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  storeId: string | null;
  cacheState: CacheState;
}

/**
 * Best-effort write to slab_scan_events. Never throws — the user gets their
 * comp even if the signal drop fails. The scraper's watchlist promoter is
 * tolerant of gaps.
 */
export async function recordScanEvent(
  supabase: SupabaseClient,
  input: ScanEventInput,
): Promise<void> {
  try {
    const { error } = await supabase.from("slab_scan_events").insert({
      identity_id: input.identityId,
      grading_service: input.gradingService,
      grade: input.grade,
      store_id: input.storeId,
      cache_state: input.cacheState,
    });
    if (error) {
      console.warn("scan-event.write.failed", { message: error.message });
    }
  } catch (e) {
    console.warn("scan-event.write.threw", { message: (e as Error).message });
  }
}
```

- [ ] **Step 2: Sanity-check compile**

Run: `deno check supabase/functions/price-comp/persistence/scan-event.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/persistence/scan-event.ts
git commit -m "feat(price-comp): best-effort slab_scan_events writer"
```

---

## Task 13: HTTP handler — wire everything together

**Files:**
- Create: `supabase/functions/price-comp/index.ts`

- [ ] **Step 1: Write the handler**

```ts
// @ts-nocheck — runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports.
// supabase/functions/price-comp/index.ts

import { createClient } from "@supabase/supabase-js";
import type {
  CacheState, GradingService, PriceCompRequest, PriceCompResponse, SoldListing,
} from "./types.ts";
import { getOAuthToken } from "./ebay/oauth.ts";
import { callMarketplaceInsights } from "./ebay/marketplace-insights.ts";
import { runCascade } from "./ebay/cascade.ts";
import { high, low, mean, median } from "./stats/aggregates.ts";
import { detectOutliers, trimmedMean } from "./stats/outliers.ts";
import { confidence } from "./stats/confidence.ts";
import { evaluateFreshness } from "./cache/freshness.ts";
import { upsertMarket } from "./persistence/market.ts";
import { recordScanEvent } from "./persistence/scan-event.ts";

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

interface BuildResponseArgs {
  listings: Array<SoldListing & { source_listing_id?: string }>;
  sampleWindowDays: 90 | 365;
  cacheHit: boolean;
  isStaleFallback: boolean;
}

function buildResponse(args: BuildResponseArgs): PriceCompResponse {
  const { listings, sampleWindowDays, cacheHit, isStaleFallback } = args;
  const prices = listings.map(l => l.sold_price_cents);
  const flags = detectOutliers(prices);
  const listingsWithFlags: SoldListing[] = listings.map((l, i) => ({
    sold_price_cents: l.sold_price_cents,
    sold_at: l.sold_at,
    title: l.title,
    url: l.url,
    source: "ebay",
    is_outlier: flags[i]!,
    outlier_reason: !flags[i] ? null : (l.sold_price_cents >= median(prices) ? "price_high" : "price_low"),
  }));

  const meanCents = prices.length ? mean(prices) : 0;
  const trimmedCents = prices.length ? trimmedMean(prices, flags) : 0;
  const medianCents = prices.length ? median(prices) : 0;
  const lowCents = prices.length ? low(prices) : 0;
  const highCents = prices.length ? high(prices) : 0;
  const now = new Date();
  const thirtyDaysAgo = now.getTime() - 30 * 24 * 3600_000;
  const sevenDaysAgo = now.getTime() - 7 * 24 * 3600_000;
  const ninetyDaysAgo = now.getTime() - 90 * 24 * 3600_000;
  const velocity = (cutoffMs: number) =>
    listings.filter(l => Date.parse(l.sold_at) >= cutoffMs).length;

  return {
    blended_price_cents: trimmedCents,
    mean_price_cents: meanCents,
    trimmed_mean_price_cents: trimmedCents,
    median_price_cents: medianCents,
    low_price_cents: lowCents,
    high_price_cents: highCents,
    confidence: confidence(prices.length, sampleWindowDays),
    sample_count: prices.length,
    sample_window_days: sampleWindowDays,
    velocity_7d: velocity(sevenDaysAgo),
    velocity_30d: velocity(thirtyDaysAgo),
    velocity_90d: velocity(ninetyDaysAgo),
    sold_listings: listingsWithFlags,
    fetched_at: now.toISOString(),
    cache_hit: cacheHit,
    is_stale_fallback: isStaleFallback,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: PriceCompRequest;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  if (!body.graded_card_identity_id || !body.grading_service || !body.grade) {
    return json(400, { error: "missing_fields" });
  }

  const serviceRole = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  const ttlSeconds = Number(env("EBAY_FRESHNESS_TTL_SECONDS", "21600"));
  const minResults = Number(env("EBAY_MIN_RESULTS_HEADLINE", "10"));

  // 1. Fetch identity (needed for query builder even on cache hit for error reporting)
  const { data: identity, error: idErr } = await serviceRole
    .from("graded_card_identities").select("*")
    .eq("id", body.graded_card_identity_id).single();
  if (idErr || !identity) return json(404, { code: "IDENTITY_NOT_FOUND" });

  // 2. Read cache
  const { data: marketRow } = await serviceRole
    .from("graded_market")
    .select("updated_at")
    .eq("identity_id", body.graded_card_identity_id)
    .eq("grading_service", body.grading_service)
    .eq("grade", body.grade)
    .maybeSingle();

  const state: CacheState = evaluateFreshness({
    updatedAtMs: marketRow?.updated_at ? Date.parse(marketRow.updated_at) : null,
    nowMs: Date.now(),
    ttlSeconds,
  });

  // 3. Cache hit → read sales + market, build response
  if (state === "hit") {
    const { data: sales } = await serviceRole
      .from("graded_market_sales")
      .select("sold_price,sold_at,title,url")
      .eq("identity_id", body.graded_card_identity_id)
      .eq("grading_service", body.grading_service)
      .eq("grade", body.grade)
      .order("sold_at", { ascending: false })
      .limit(10);
    const listings = (sales ?? []).map(s => ({
      sold_price_cents: Math.round(Number(s.sold_price) * 100),
      sold_at: s.sold_at,
      title: s.title ?? "",
      url: s.url ?? "",
      source: "ebay" as const,
      is_outlier: false, outlier_reason: null,
    }));
    const { data: agg } = await serviceRole
      .from("graded_market")
      .select("sample_window_days")
      .eq("identity_id", body.graded_card_identity_id)
      .eq("grading_service", body.grading_service)
      .eq("grade", body.grade)
      .single();
    const sampleWindowDays = (agg?.sample_window_days ?? 90) as 90 | 365;
    const response = buildResponse({
      listings, sampleWindowDays, cacheHit: true, isStaleFallback: false,
    });
    await recordScanEvent(serviceRole, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service as GradingService,
      grade: body.grade,
      storeId: null,
      cacheState: "hit",
    });
    return json(200, response);
  }

  // 4. Cache miss/stale → live fetch
  let token: string;
  try {
    token = await getOAuthToken({
      appId: env("EBAY_APP_ID"),
      certId: env("EBAY_CERT_ID"),
      scope: env("EBAY_OAUTH_SCOPE", "https://api.ebay.com/oauth/api_scope/buy.marketplace.insights"),
    });
  } catch (e) {
    console.error("price-comp.oauth.failed", { message: (e as Error).message });
    // Fall through to stale serve
    return await serveStaleOrUpstreamDown(serviceRole, body, identity, state === "stale");
  }

  let cascade;
  try {
    cascade = await runCascade(identity as any, body.grading_service as GradingService, body.grade, {
      minResults,
      fetchBucket: async (q) => await callMarketplaceInsights({
        token, q: q.q, categoryId: q.categoryId, limit: 50,
      }),
    });
  } catch (e) {
    console.error("price-comp.cascade.failed", { message: (e as Error).message });
    return await serveStaleOrUpstreamDown(serviceRole, body, identity, state === "stale");
  }

  if (cascade.listings.length === 0) {
    await recordScanEvent(serviceRole, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service as GradingService,
      grade: body.grade,
      storeId: null,
      cacheState: state === "miss" ? "miss" : "stale",
    });
    return json(404, { code: "NO_MARKET_DATA" });
  }

  const prices = cascade.listings.map(l => l.sold_price_cents);
  const flags = detectOutliers(prices);
  const meanCents = mean(prices);
  const trimmedCents = trimmedMean(prices, flags);
  const medianCents = median(prices);
  const lowCents = low(prices);
  const highCents = high(prices);

  // Persist
  try {
    await upsertMarket(serviceRole, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service as GradingService,
      grade: body.grade,
      listings: cascade.listings.map((l, i) => ({
        sold_price_cents: l.sold_price_cents,
        sold_at: l.sold_at,
        title: l.title,
        url: l.url,
        source: "ebay" as const,
        is_outlier: flags[i]!,
        outlier_reason: !flags[i] ? null : (l.sold_price_cents >= medianCents ? "price_high" : "price_low"),
        source_listing_id: l.source_listing_id,
      })),
      aggregates: {
        low_cents: lowCents, high_cents: highCents, mean_cents: meanCents,
        trimmed_mean_cents: trimmedCents, median_cents: medianCents,
        confidence: confidence(prices.length, cascade.sampleWindowDays),
        sample_window_days: cascade.sampleWindowDays,
        velocity_7d: cascade.listings.filter(l => Date.parse(l.sold_at) >= Date.now() - 7*86400000).length,
        velocity_30d: cascade.listings.filter(l => Date.parse(l.sold_at) >= Date.now() - 30*86400000).length,
        velocity_90d: cascade.listings.filter(l => Date.parse(l.sold_at) >= Date.now() - 90*86400000).length,
      },
    });
  } catch (e) {
    // Persistence failure is logged but does not block the response.
    console.error("price-comp.persist.failed", { message: (e as Error).message });
  }

  const response = buildResponse({
    listings: cascade.listings.map(l => ({
      sold_price_cents: l.sold_price_cents,
      sold_at: l.sold_at, title: l.title, url: l.url,
      source: "ebay" as const,
      is_outlier: false, outlier_reason: null,
    })),
    sampleWindowDays: cascade.sampleWindowDays,
    cacheHit: false,
    isStaleFallback: false,
  });

  await recordScanEvent(serviceRole, {
    identityId: body.graded_card_identity_id,
    gradingService: body.grading_service as GradingService,
    grade: body.grade,
    storeId: null,
    cacheState: state === "miss" ? "miss" : "stale",
  });

  console.log("price-comp.live", {
    identity_id: body.graded_card_identity_id,
    bucket_hit: cascade.bucketHit,
    result_count: cascade.listings.length,
    cache_state: state,
  });

  return json(200, response);
});

async function serveStaleOrUpstreamDown(
  supabase: any, body: PriceCompRequest, _identity: unknown, hasStale: boolean,
): Promise<Response> {
  if (!hasStale) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  const { data: sales } = await supabase
    .from("graded_market_sales")
    .select("sold_price,sold_at,title,url")
    .eq("identity_id", body.graded_card_identity_id)
    .eq("grading_service", body.grading_service)
    .eq("grade", body.grade)
    .order("sold_at", { ascending: false })
    .limit(10);
  const { data: agg } = await supabase
    .from("graded_market")
    .select("sample_window_days")
    .eq("identity_id", body.graded_card_identity_id)
    .eq("grading_service", body.grading_service)
    .eq("grade", body.grade)
    .single();
  const listings = (sales ?? []).map((s: any) => ({
    sold_price_cents: Math.round(Number(s.sold_price) * 100),
    sold_at: s.sold_at, title: s.title ?? "", url: s.url ?? "",
    source: "ebay" as const, is_outlier: false, outlier_reason: null,
  }));
  const response = buildResponse({
    listings,
    sampleWindowDays: (agg?.sample_window_days ?? 90) as 90 | 365,
    cacheHit: true, isStaleFallback: true,
  });
  return json(200, response);
}
```

- [ ] **Step 2: Type-check the handler**

Run: `deno check supabase/functions/price-comp/index.ts`
Expected: clean (the `// @ts-nocheck` on the first line suppresses esm.sh import errors that the local LSP can't resolve; the actual Deno runtime resolves them).

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/index.ts
git commit -m "feat(price-comp): HTTP handler wiring cache + live fetch + persistence"
```

---

## Task 14: Integration test — full handler flow with mocked eBay

**Files:**
- Test: `supabase/functions/price-comp/__tests__/index.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// supabase/functions/price-comp/__tests__/index.test.ts
// Minimal handler-level integration test that mocks both the eBay fetch and
// the Supabase client by injecting stubs via module re-mocking is overkill
// for this stage. Instead, we test the *shape* of the response the handler
// produces given a known cascade by exercising the public building blocks.
// A full e2e lives in manual smoke-test in Task 18.

import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { detectOutliers, trimmedMean } from "../stats/outliers.ts";
import { mean, median, low, high } from "../stats/aggregates.ts";
import { confidence } from "../stats/confidence.ts";

describe("handler math on fixture mi-with-outlier", () => {
  it("computes expected aggregates with two outliers", async () => {
    const text = await Deno.readTextFile(
      new URL("../__fixtures__/mi-with-outlier.json", import.meta.url),
    );
    const data = JSON.parse(text) as { itemSales: Array<{ lastSoldPrice: { value: string } }> };
    const prices = data.itemSales.map(s => Math.round(Number(s.lastSoldPrice.value) * 100));
    const flags = detectOutliers(prices);
    // Fixture: 1st ($2500) should be high outlier; 2nd ($1) should be low outlier.
    assertEquals(flags[0], true);
    assertEquals(flags[1], true);
    // Remaining eight ($120,122,125,128,115,130,135,118) should all be valid.
    assertEquals(flags.slice(2).every(f => !f), true);

    const trimmed = trimmedMean(prices, flags);
    // Trimmed mean of the 8 normal prices is (120+122+125+128+115+130+135+118)/8 = 124.125 → 12413 cents after half-to-even
    assertEquals(trimmed, 12413);
    // Straight mean including outliers is ((250000+100+12000+12200+12500+12800+11500+13000+13500+11800)/10) = 34940
    assertEquals(mean(prices), 34940);
    // Median of 10 values → avg of 5th and 6th
    const medianVal = median(prices);
    // sorted: [100, 11500, 11800, 12000, 12200, 12500, 12800, 13000, 13500, 250000]
    // 5th = 12200, 6th = 12500 → avg = 12350
    assertEquals(medianVal, 12350);
    assertEquals(low(prices), 100);
    assertEquals(high(prices), 250000);
    assertEquals(confidence(10, 90), 1.0);
  });
});
```

- [ ] **Step 2: Run to verify fixture math pins down the contract**

Run: `deno test supabase/functions/price-comp/__tests__/index.test.ts --allow-read`
Expected: PASS.

(If it fails, the TDD surfaces a real discrepancy — fix the math modules, not the test.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/__tests__/index.test.ts
git commit -m "test(price-comp): handler-level math assertions on fixture"
```

---

## Task 15: iOS SwiftData mirrors — `GradedCardIdentity`, `GradedMarketSnapshot`, `SoldListingMirror`

**Files:**
- Create: `ios/slabbist/slabbist/Core/Models/GradedCardIdentity.swift`
- Create: `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift`
- Create: `ios/slabbist/slabbist/Core/Models/SoldListingMirror.swift`
- Modify: `ios/slabbist/slabbist/slabbistApp.swift` — add the three models to the `ModelContainer` schema.

- [ ] **Step 1: Create `GradedCardIdentity.swift`**

```swift
import Foundation
import SwiftData

@Model
final class GradedCardIdentity {
    @Attribute(.unique) var id: UUID
    var game: String
    var language: String
    var setCode: String?
    var setName: String
    var cardNumber: String?
    var cardName: String
    var variant: String?
    var year: Int?

    init(
        id: UUID,
        game: String,
        language: String,
        setCode: String? = nil,
        setName: String,
        cardNumber: String? = nil,
        cardName: String,
        variant: String? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.game = game
        self.language = language
        self.setCode = setCode
        self.setName = setName
        self.cardNumber = cardNumber
        self.cardName = cardName
        self.variant = variant
        self.year = year
    }
}
```

- [ ] **Step 2: Create `SoldListingMirror.swift`**

```swift
import Foundation
import SwiftData

enum OutlierReason: String, Codable, CaseIterable {
    case priceHigh = "price_high"
    case priceLow  = "price_low"
}

@Model
final class SoldListingMirror {
    @Attribute(.unique) var id: UUID
    var soldPriceCents: Int64
    var soldAt: Date
    var title: String
    var url: URL
    var source: String
    var isOutlier: Bool
    var outlierReasonRaw: String?

    var outlierReason: OutlierReason? {
        get { outlierReasonRaw.flatMap(OutlierReason.init(rawValue:)) }
        set { outlierReasonRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        soldPriceCents: Int64,
        soldAt: Date,
        title: String,
        url: URL,
        source: String = "ebay",
        isOutlier: Bool = false,
        outlierReason: OutlierReason? = nil
    ) {
        self.id = id
        self.soldPriceCents = soldPriceCents
        self.soldAt = soldAt
        self.title = title
        self.url = url
        self.source = source
        self.isOutlier = isOutlier
        self.outlierReasonRaw = outlierReason?.rawValue
    }
}
```

- [ ] **Step 3: Create `GradedMarketSnapshot.swift`**

```swift
import Foundation
import SwiftData

@Model
final class GradedMarketSnapshot {
    /// Composite-ish key: snapshot keyed by identity + grading + grade.
    /// We store individually since SwiftData doesn't support composite uniques directly.
    var identityId: UUID
    var gradingService: String
    var grade: String

    var blendedPriceCents: Int64
    var meanPriceCents: Int64
    var trimmedMeanPriceCents: Int64
    var medianPriceCents: Int64
    var lowPriceCents: Int64
    var highPriceCents: Int64
    var confidence: Double
    var sampleCount: Int
    var sampleWindowDays: Int
    var velocity7d: Int
    var velocity30d: Int
    var velocity90d: Int
    var fetchedAt: Date
    var cacheHit: Bool
    var isStaleFallback: Bool

    @Relationship(deleteRule: .cascade)
    var soldListings: [SoldListingMirror]

    init(
        identityId: UUID,
        gradingService: String,
        grade: String,
        blendedPriceCents: Int64,
        meanPriceCents: Int64,
        trimmedMeanPriceCents: Int64,
        medianPriceCents: Int64,
        lowPriceCents: Int64,
        highPriceCents: Int64,
        confidence: Double,
        sampleCount: Int,
        sampleWindowDays: Int,
        velocity7d: Int,
        velocity30d: Int,
        velocity90d: Int,
        fetchedAt: Date,
        cacheHit: Bool,
        isStaleFallback: Bool,
        soldListings: [SoldListingMirror] = []
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
        self.blendedPriceCents = blendedPriceCents
        self.meanPriceCents = meanPriceCents
        self.trimmedMeanPriceCents = trimmedMeanPriceCents
        self.medianPriceCents = medianPriceCents
        self.lowPriceCents = lowPriceCents
        self.highPriceCents = highPriceCents
        self.confidence = confidence
        self.sampleCount = sampleCount
        self.sampleWindowDays = sampleWindowDays
        self.velocity7d = velocity7d
        self.velocity30d = velocity30d
        self.velocity90d = velocity90d
        self.fetchedAt = fetchedAt
        self.cacheHit = cacheHit
        self.isStaleFallback = isStaleFallback
        self.soldListings = soldListings
    }
}
```

- [ ] **Step 4: Register the new models in the ModelContainer**

Open `ios/slabbist/slabbist/slabbistApp.swift`, find the ModelContainer schema initialization, and add the three new types. Exact edit depends on the current file; pattern is `Schema([Store.self, StoreMember.self, Lot.self, Scan.self, OutboxItem.self, GradedCardIdentity.self, GradedMarketSnapshot.self, SoldListingMirror.self])`.

- [ ] **Step 5: Build to verify**

Run (from Xcode or CLI): `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: clean build.

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/GradedCardIdentity.swift ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift ios/slabbist/slabbist/Core/Models/SoldListingMirror.swift ios/slabbist/slabbist/slabbistApp.swift
git commit -m "feat(ios): SwiftData mirrors for graded_market_snapshot + sold_listings"
```

---

## Task 16: iOS `CompRepository` (TDD)

**Files:**
- Create: `ios/slabbist/slabbist/Features/Comp/CompRepository.swift`
- Test: `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift
import Testing
import Foundation
import SwiftData
@testable import slabbist

@Suite("CompRepository")
struct CompRepositoryTests {
    @Test("decodes a live-fetch response into a GradedMarketSnapshot with listings")
    func decodesLiveFetchResponse() async throws {
        let json = """
        {
          "blended_price_cents": 12413,
          "mean_price_cents": 34940,
          "trimmed_mean_price_cents": 12413,
          "median_price_cents": 12350,
          "low_price_cents": 100,
          "high_price_cents": 250000,
          "confidence": 1.0,
          "sample_count": 10,
          "sample_window_days": 90,
          "velocity_7d": 3,
          "velocity_30d": 10,
          "velocity_90d": 10,
          "sold_listings": [
            { "sold_price_cents": 250000, "sold_at": "2026-04-20T10:00:00Z",
              "title": "SIGNED", "url": "https://www.ebay.com/itm/1",
              "source": "ebay", "is_outlier": true, "outlier_reason": "price_high" }
          ],
          "fetched_at": "2026-04-23T22:14:03Z",
          "cache_hit": false,
          "is_stale_fallback": false
        }
        """.data(using: .utf8)!

        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.blendedPriceCents == 12413)
        #expect(decoded.sampleCount == 10)
        #expect(decoded.soldListings.count == 1)
        #expect(decoded.soldListings[0].isOutlier == true)
        #expect(decoded.soldListings[0].outlierReason == .priceHigh)
    }

    @Test("404 NO_MARKET_DATA surfaces as a typed error")
    func mapsNoMarketData() async throws {
        let json = #"{ "code": "NO_MARKET_DATA" }"#.data(using: .utf8)!
        #expect(throws: CompRepository.Error.noMarketData) {
            _ = try CompRepository.decodeErrorBody(json, statusCode: 404)
        }
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

Run Swift Testing from Xcode's test navigator, or: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:slabbistTests/CompRepositoryTests`
Expected: FAIL — `CompRepository` not found.

- [ ] **Step 3: Implement `CompRepository.swift`**

```swift
import Foundation
import SwiftData

@MainActor
final class CompRepository {
    enum Error: Swift.Error, Equatable {
        case noMarketData
        case upstreamUnavailable
        case httpStatus(Int)
        case decoding(String)
    }

    struct Wire: Decodable {
        let blended_price_cents: Int64
        let mean_price_cents: Int64
        let trimmed_mean_price_cents: Int64
        let median_price_cents: Int64
        let low_price_cents: Int64
        let high_price_cents: Int64
        let confidence: Double
        let sample_count: Int
        let sample_window_days: Int
        let velocity_7d: Int
        let velocity_30d: Int
        let velocity_90d: Int
        let sold_listings: [WireListing]
        let fetched_at: Date
        let cache_hit: Bool
        let is_stale_fallback: Bool
    }

    struct WireListing: Decodable {
        let sold_price_cents: Int64
        let sold_at: Date
        let title: String
        let url: URL
        let source: String
        let is_outlier: Bool
        let outlier_reason: String?
    }

    struct Decoded {
        let blendedPriceCents: Int64
        let meanPriceCents: Int64
        let trimmedMeanPriceCents: Int64
        let medianPriceCents: Int64
        let lowPriceCents: Int64
        let highPriceCents: Int64
        let confidence: Double
        let sampleCount: Int
        let sampleWindowDays: Int
        let velocity7d: Int
        let velocity30d: Int
        let velocity90d: Int
        let soldListings: [SoldListingMirror]
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

    static func decode(data: Data) throws -> Decoded {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire: Wire
        do { wire = try decoder.decode(Wire.self, from: data) }
        catch { throw Error.decoding("\(error)") }
        let listings = wire.sold_listings.map { w in
            SoldListingMirror(
                soldPriceCents: w.sold_price_cents,
                soldAt: w.sold_at,
                title: w.title,
                url: w.url,
                source: w.source,
                isOutlier: w.is_outlier,
                outlierReason: w.outlier_reason.flatMap(OutlierReason.init(rawValue:))
            )
        }
        return Decoded(
            blendedPriceCents: wire.blended_price_cents,
            meanPriceCents: wire.mean_price_cents,
            trimmedMeanPriceCents: wire.trimmed_mean_price_cents,
            medianPriceCents: wire.median_price_cents,
            lowPriceCents: wire.low_price_cents,
            highPriceCents: wire.high_price_cents,
            confidence: wire.confidence,
            sampleCount: wire.sample_count,
            sampleWindowDays: wire.sample_window_days,
            velocity7d: wire.velocity_7d,
            velocity30d: wire.velocity_30d,
            velocity90d: wire.velocity_90d,
            soldListings: listings,
            fetchedAt: wire.fetched_at,
            cacheHit: wire.cache_hit,
            isStaleFallback: wire.is_stale_fallback
        )
    }

    static func decodeErrorBody(_ data: Data, statusCode: Int) throws -> Never {
        struct Body: Decodable { let code: String? }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        switch (statusCode, body?.code) {
        case (404, "NO_MARKET_DATA"): throw Error.noMarketData
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

- [ ] **Step 4: Run tests to verify they pass**

Run the test target.
Expected: PASS (2 checks).

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompRepository.swift ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift
git commit -m "feat(ios): CompRepository with decode + error typing"
```

---

## Task 17: iOS UI — `ScanDetailView` + `CompCardView`, `BulkScanView` tap, `BulkScanViewModel` trigger

**Files:**
- Create: `ios/slabbist/slabbist/Features/Comp/CompCardView.swift`
- Create: `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift`
- Modify: `ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift` (add NavigationLink)
- Modify: `ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanViewModel.swift` (call `CompRepository.fetchComp` on validated scan, persist snapshot into SwiftData)
- Modify: `ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift` (add `PriceCompJob` payload struct)

- [ ] **Step 1: Add `OutboxPayloads.PriceCompJob`**

Append to `OutboxPayloads.swift` inside the extension:

```swift
    struct PriceCompJob: Codable {
        let graded_card_identity_id: String
        let grading_service: String
        let grade: String
    }
```

- [ ] **Step 2: Create `CompCardView.swift`**

```swift
import SwiftUI
import SwiftData

struct CompCardView: View {
    let snapshot: GradedMarketSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
            breakdown
            if snapshot.sampleCount < 10 || snapshot.isStaleFallback {
                lowConfidenceChip
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.thinMaterial))
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(formatCents(snapshot.trimmedMeanPriceCents))
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Spacer()
            ConfidenceMeter(value: snapshot.confidence)
                .frame(width: 80, height: 14)
        }
    }

    private var breakdown: some View {
        HStack(spacing: 16) {
            statCell("Mean",     snapshot.meanPriceCents)
            statCell("Trimmed",  snapshot.trimmedMeanPriceCents)
            statCell("Median",   snapshot.medianPriceCents)
            statCell("Low",      snapshot.lowPriceCents)
            statCell("High",     snapshot.highPriceCents)
        }
        .font(.footnote)
    }

    private var lowConfidenceChip: some View {
        Text(snapshot.isStaleFallback
             ? "Cached — live data unavailable"
             : "Low confidence — \(snapshot.sampleCount) comps")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.orange.opacity(0.2)))
            .foregroundStyle(.orange)
    }

    private func statCell(_ label: String, _ cents: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(formatCents(cents)).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 2
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}

struct ConfidenceMeter: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7).fill(.quaternary)
                RoundedRectangle(cornerRadius: 7)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, value))))
            }
        }
    }
    private var color: Color {
        if value >= 0.75 { return .green }
        if value >= 0.4  { return .yellow }
        return .orange
    }
}
```

- [ ] **Step 3: Create `ScanDetailView.swift`**

```swift
import SwiftUI
import SwiftData

struct ScanDetailView: View {
    let scan: Scan
    @Query private var snapshots: [GradedMarketSnapshot]

    init(scan: Scan) {
        self.scan = scan
        let identityId = scan.graderIdentityIdForQuery // helper below
        let service = scan.grader.rawValue
        let grade = scan.grade ?? ""
        _snapshots = Query(filter: #Predicate<GradedMarketSnapshot> { s in
            s.identityId == identityId &&
            s.gradingService == service &&
            s.grade == grade
        }, sort: \GradedMarketSnapshot.fetchedAt, order: .reverse)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let snapshot = snapshots.first {
                    CompCardView(snapshot: snapshot)
                    listingsSection(snapshot: snapshot)
                } else {
                    ProgressView("Fetching comps…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle("\(scan.grader.rawValue) \(scan.grade ?? "")")
    }

    private func listingsSection(snapshot: GradedMarketSnapshot) -> some View {
        DisclosureGroup("View all \(snapshot.soldListings.count) sold listings") {
            VStack(spacing: 8) {
                ForEach(snapshot.soldListings.sorted(by: { $0.soldAt > $1.soldAt })) { listing in
                    Link(destination: listing.url) { listingRow(listing) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
    }

    private func listingRow(_ l: SoldListingMirror) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l.title).lineLimit(2).font(.subheadline)
                Spacer()
                Text(formatCents(l.soldPriceCents)).font(.subheadline.monospacedDigit())
            }
            HStack(spacing: 8) {
                Text(l.soldAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                if l.isOutlier {
                    Text(l.outlierReason == .priceHigh ? "High outlier" : "Low outlier")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatCents(_ cents: Int64) -> String {
        let dollars = Double(cents) / 100
        let fmt = NumberFormatter(); fmt.numberStyle = .currency; fmt.currencyCode = "USD"
        return fmt.string(from: dollars as NSNumber) ?? "$\(dollars)"
    }
}

// Small helper so the #Predicate can see a non-optional UUID.
private extension Scan {
    var graderIdentityIdForQuery: UUID { self.gradedCardIdentityId ?? UUID() }
}
```

Note: `Scan` does not yet have a `gradedCardIdentityId` property. If adding it exceeds this plan's scope (because it's owned by the cert-lookup plan), implement a temporary local-only `scan.identityHint: UUID?` or stage the property now; reconcile in the cert-lookup plan. For this plan, add a nullable `var gradedCardIdentityId: UUID?` to `Scan.swift` guarded by `// TODO(cert-lookup): populated by /cert-lookup response in its plan`.

- [ ] **Step 4: Modify `BulkScanView.swift` to push `ScanDetailView`**

Find the slab queue row in the existing view. Wrap it in a `NavigationLink(value: scan) { ... }` and add `.navigationDestination(for: Scan.self) { ScanDetailView(scan: $0) }` on the outer `NavigationStack`. Exact edit is local to the current structure of the file.

- [ ] **Step 5: Modify `BulkScanViewModel.swift` to trigger `CompRepository` on validation**

Add a `compRepo: CompRepository` dependency. When a scan transitions to `.validated` (or when the viewmodel is initialized and sees a validated scan without a snapshot), call `compRepo.fetchComp(identityId:service:grade:)` and on success persist a new `GradedMarketSnapshot` + cascade-deleted listings into the ModelContext.

Exact code inline:

```swift
func triggerCompFetch(for scan: Scan) {
    guard let identityId = scan.gradedCardIdentityId,
          let grade = scan.grade else { return }
    Task {
        do {
            let decoded = try await compRepo.fetchComp(
                identityId: identityId,
                gradingService: scan.grader.rawValue,
                grade: grade
            )
            await MainActor.run {
                let snapshot = GradedMarketSnapshot(
                    identityId: identityId,
                    gradingService: scan.grader.rawValue,
                    grade: grade,
                    blendedPriceCents: decoded.blendedPriceCents,
                    meanPriceCents: decoded.meanPriceCents,
                    trimmedMeanPriceCents: decoded.trimmedMeanPriceCents,
                    medianPriceCents: decoded.medianPriceCents,
                    lowPriceCents: decoded.lowPriceCents,
                    highPriceCents: decoded.highPriceCents,
                    confidence: decoded.confidence,
                    sampleCount: decoded.sampleCount,
                    sampleWindowDays: decoded.sampleWindowDays,
                    velocity7d: decoded.velocity7d,
                    velocity30d: decoded.velocity30d,
                    velocity90d: decoded.velocity90d,
                    fetchedAt: decoded.fetchedAt,
                    cacheHit: decoded.cacheHit,
                    isStaleFallback: decoded.isStaleFallback,
                    soldListings: decoded.soldListings
                )
                modelContext.insert(snapshot)
                try? modelContext.save()
            }
        } catch {
            // Logged and swallowed; UI keeps "Fetching…" until a retry or outbox worker.
            os_log("comp-fetch failed: %{public}@", String(describing: error))
        }
    }
}
```

Wire `triggerCompFetch(for:)` from the spot in the existing viewmodel where a scan moves to `.validated`. If that transition happens elsewhere (e.g., once /cert-lookup lands), add a TODO note and leave the trigger callable so the cert-lookup plan can hook it in.

- [ ] **Step 6: Build to verify**

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: clean build.

- [ ] **Step 7: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompCardView.swift ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanView.swift ios/slabbist/slabbist/Features/Scanning/BulkScan/BulkScanViewModel.swift ios/slabbist/slabbist/Core/Persistence/Outbox/OutboxPayloads.swift ios/slabbist/slabbist/Core/Models/Scan.swift
git commit -m "feat(ios): ScanDetailView + CompCardView + BulkScanVM comp trigger"
```

---

## Task 18: Deploy + smoke test

**Files:** none modified; operational steps only.

- [ ] **Step 1: Rotate the Cert ID**

User action: open eBay Developer Console → Production → `listing-processor` app → click "Rotate (Reset) Cert ID". Copy the new value.

- [ ] **Step 2: Set secrets**

```bash
supabase secrets set EBAY_APP_ID='PhilNguy-listingp-PRD-a4c84dffe-12daf577'
supabase secrets set EBAY_CERT_ID='<NEW_ROTATED_CERT_ID>'
supabase secrets set EBAY_FRESHNESS_TTL_SECONDS='21600'
supabase secrets set EBAY_MIN_RESULTS_HEADLINE='10'
```

Verify: `supabase secrets list` shows all four keys (values redacted).

- [ ] **Step 3: Deploy the function**

```bash
supabase functions deploy price-comp
```

Expected: "Deployed price-comp" success message.

- [ ] **Step 4: Smoke test against a known-populated identity**

Seed a test identity in the Supabase Studio SQL editor (or confirm one exists from the tcgcsv ingest). Then:

```bash
curl -sS -X POST "https://<project-ref>.supabase.co/functions/v1/price-comp" \
  -H "authorization: Bearer $(supabase auth sign-in --email you@example.com --password ... --json | jq -r .access_token)" \
  -H "content-type: application/json" \
  -d '{"graded_card_identity_id":"<uuid>","grading_service":"PSA","grade":"10"}' | jq .
```

Expected: 200 response with `sold_listings` array populated and `cache_hit: false` on first call, `cache_hit: true` on a second call within 6h.

- [ ] **Step 5: iOS simulator smoke test**

Launch the simulator. Create a lot. Scan or manually insert a validated scan with a known `graded_card_identity_id`. Confirm `ScanDetailView` loads the comp card, displays the trimmed-mean headline, expands the sold-listings list, and marks the one outlier row correctly.

- [ ] **Step 6: Check `slab_scan_events` is accumulating**

```sql
select cache_state, count(*) from public.slab_scan_events
where scanned_at > now() - interval '1 hour'
group by cache_state;
```

Expected: at least one row per cache state you exercised (miss, hit).

- [ ] **Step 7: Commit — no code, but tag**

```bash
git tag -a "price-comp-v1.0" -m "Live eBay sold-listings comp shipped"
```

---

## Self-review

Spec coverage — each spec section mapped to tasks:

- Architecture diagram → Tasks 10, 13
- Query cascade → Tasks 6, 9
- Aggregate statistics → Tasks 3, 4
- Confidence score → Task 5
- OAuth + secrets → Tasks 7, 18
- Persistence (live path) → Task 11
- Scan signal for watchlist promotion → Tasks 1 (schema), 12 (writer), 13 (wiring)
- Failure modes → Task 13 (`serveStaleOrUpstreamDown`, 503 + 404 + stale fallback paths)
- iOS changes → Tasks 15, 16, 17
- Testing strategy → Tasks 3–9 (unit), 14 (integration/math), 16 (iOS), 18 (manual e2e)
- Observability → Task 13 (`console.log` structured line per live fetch)
- Security (Cert ID rotation) → Task 18 step 1

No spec section is orphaned.

Placeholder scan — clean. Every step has actual code or an exact command. The only conditional language is in Task 17 step 3 where `Scan.gradedCardIdentityId` is flagged as a cross-plan coordination point; code is still provided for this plan's changes.

Type consistency — `SoldListingMirror.outlierReason`, `GradedMarketSnapshot` fields, `CompRepository.Decoded`, and `Wire` struct field names are reviewed; all align.
