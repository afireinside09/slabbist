# Poketrace Graded-Pricing Comp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `poketrace.com` as a second graded-pricing data source alongside the existing `pokemonpricetracker.com` (PPT) integration. Every scanned slab fans out to both providers in parallel from the existing `price-comp` Edge Function. The iOS comp screen shows a side-by-side per-source comparison and a reconciled headline equal to the average of the two sources.

**Architecture:** Existing `price-comp` Edge Function gains a parallel branch that fetches from Poketrace in `Promise.allSettled` alongside the existing PPT branch. Database changes: `graded_market` primary key extends to include `source` so PPT and Poketrace rows coexist; new `pt_*` columns hold Poketrace's richer `TierPrice` dimensions; `graded_card_identities` gets a `poketrace_card_id` cache. iOS persists two `GradedMarketSnapshot` rows per scan (one per source) and the comp card renders a side-by-side cell + sparkline-source toggle. PPT data, schema, and code paths stay intact.

**Tech Stack:** Deno (Edge Function), SwiftUI + SwiftData (iOS), PostgreSQL via Supabase migrations, Poketrace REST API (`https://api.poketrace.com/v1`, `X-API-Key` header).

**Spec:** [`docs/superpowers/specs/2026-05-08-poketrace-comp-design.md`](../specs/2026-05-08-poketrace-comp-design.md)

---

## Prerequisites

- A Poketrace API key (any plan tier) — set via `supabase secrets set POKETRACE_API_KEY=...` once Phase 6 lands.
- Supabase CLI authenticated against the slabbist project.
- Xcode 16+ with the slabbist workspace cleanly building on `main`.
- Memory note `feedback_supabase_migration_ledger`: when `supabase db push` reports "relation already exists" / "constraint already exists", `INSERT INTO supabase_migrations.schema_migrations (version) VALUES ('<ts>')` rather than re-running DDL.
- Memory note `feedback_live_decode_round_trip`: the actual iOS decoder must round-trip a real edge-function response before declaring the cutover done. Phase 7 enforces this.

---

## File Structure

**Created:**
- `supabase/functions/price-comp/poketrace/client.ts` — fetch wrapper with `X-API-Key`, per-call timeout, retry-once on 5xx.
- `supabase/functions/price-comp/poketrace/match.ts` — `tcgplayer_ids` cross-walk + UUID cache on `graded_card_identities.poketrace_card_id`.
- `supabase/functions/price-comp/poketrace/prices.ts` — `GET /cards/{id}` and tier extraction from `data.prices.<source>.<tier>`.
- `supabase/functions/price-comp/poketrace/history.ts` — `GET /cards/{id}/prices/{tier}/history?period=30d`.
- `supabase/functions/price-comp/poketrace/parse.ts` — `TierPrice` value object → DB column mapping (dollars → cents).
- `supabase/functions/price-comp/__tests__/poketrace-parse.test.ts`
- `supabase/functions/price-comp/__tests__/poketrace-match.test.ts`
- `supabase/functions/price-comp/__tests__/poketrace-tier-key.test.ts`
- `supabase/functions/price-comp/__tests__/index-fanout.test.ts`
- `supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-card.json`
- `supabase/functions/price-comp/__fixtures__/poketrace/charizard-psa10-history-30d.json`
- `supabase/migrations/<ts>_add_poketrace_to_graded_market.sql`

**Modified:**
- `supabase/functions/price-comp/types.ts` — add `PoketraceBlock`, `ReconciledBlock`, widen `PriceCompResponse`.
- `supabase/functions/price-comp/persistence/market.ts` — add `source` parameter; `onConflict` includes source.
- `supabase/functions/price-comp/persistence/identity-product-id.ts` — add `persistIdentityPoketraceCardId` / `clearIdentityPoketraceCardId`.
- `supabase/functions/price-comp/index.ts` — fan out to Poketrace via `Promise.allSettled`; build new envelope.
- `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift` — add `source` + `pt_*` columns; bump init.
- `ios/slabbist/slabbist/Features/Comp/CompRepository.swift` — extend `Wire` / `Decoded` with `poketrace`/`reconciled` blocks; preserve back-compat decoder.
- `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift` — persist 2 snapshots; surface reconciled headline on `Scan`.
- `ios/slabbist/slabbist/Features/Comp/CompCardView.swift` — side-by-side source row, source caption, sparkline toggle.
- `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift` — both-source / one-source / source-missing decoder tests.

---

## Phase 0 — Live API probe

The Poketrace docs page is sparse and JS-rendered. The OpenAPI 1.7.0 spec at `https://api.poketrace.com/v1/openapi.json` gives the schema (`Card`, `TierPrice`, `PriceHistoryResponse`) but does not show *which* source key in `data.prices` carries the graded tiers for US cards. The spec's claim that graded tiers live under `data.prices.ebay.<TIER>` **must be reconciled against a live response before any Deno code lands.**

### Task 0: Probe live Poketrace API and capture baseline fixtures

**Files:**
- Create: `supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-search.json`
- Create: `supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-card.json`
- Create: `supabase/functions/price-comp/__fixtures__/poketrace/charizard-psa10-history-30d.json`
- Modify: `docs/superpowers/specs/2026-05-08-poketrace-comp-design.md` — only if the spec's claim about `data.prices.<source>.<TIER>` differs from reality; bump an "Update history" entry recording the change.

- [ ] **Step 1: Verify the API key is exported**

```bash
echo "${POKETRACE_API_KEY:?key not set}" | wc -c
# Expected: a count > 1. If 0, export it first:
#   export POKETRACE_API_KEY=<key from poketrace.com dashboard>
```

- [ ] **Step 2: Probe `/health` to confirm auth works**

```bash
curl -sS -i 'https://api.poketrace.com/v1/health' \
  -H "X-API-Key: ${POKETRACE_API_KEY}" | head -20
# Expected: HTTP/2 200 with a small JSON body. If 401/403, fix the key and retry.
```

- [ ] **Step 3: Search for a known card by name to capture a UUID**

```bash
mkdir -p supabase/functions/price-comp/__fixtures__/poketrace
curl -sS -G 'https://api.poketrace.com/v1/cards' \
  --data-urlencode 'search=charizard' \
  --data-urlencode 'set=base-set' \
  --data-urlencode 'limit=5' \
  --data-urlencode 'has_graded=true' \
  -H "X-API-Key: ${POKETRACE_API_KEY}" \
  -o supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-search.json

# Inspect to confirm at least one result includes the holo Charizard
jq '.data[] | {id, name, cardNumber, set: .set.slug, hasGraded}' \
  supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-search.json
```

Expected: at least one entry with `name == "Charizard"`, `cardNumber == "4"`, `set.slug == "base-set"`, `hasGraded == true`. Note the `id` (UUID).

- [ ] **Step 4: Fetch the card detail to inspect the prices shape**

```bash
CARD_ID="$(jq -r '.data[] | select(.name=="Charizard" and .cardNumber=="4") | .id' \
  supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-search.json | head -1)"
echo "CARD_ID=$CARD_ID"

curl -sS "https://api.poketrace.com/v1/cards/${CARD_ID}" \
  -H "X-API-Key: ${POKETRACE_API_KEY}" \
  -o supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-card.json

# Walk the prices tree
jq '.data.prices | to_entries | map({source: .key, tiers: (.value | keys)})' \
  supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-card.json
```

Expected: an array showing which top-level source keys exist (e.g. `ebay`, `tcgplayer`) and which tier strings each contains. The graded tiers (`PSA_10`, `PSA_9`, etc.) should appear under one source. **Record the source key name** (likely `ebay`).

- [ ] **Step 5: Verify a TierPrice has the documented shape**

```bash
jq '.data.prices | to_entries[] | .value.PSA_10 // empty' \
  supabase/functions/price-comp/__fixtures__/poketrace/charizard-base-set-card.json
```

Expected: an object with at minimum `avg`, `low`, `high`, and one of `trend`/`confidence`/`saleCount`. Any of `avg1d`, `avg7d`, `avg30d`, `median3d`, `median7d`, `median30d` may also be present. Confirm values are decimal dollars (e.g. `180.50`), not cents.

- [ ] **Step 6: Fetch 30d history for the PSA 10 tier**

```bash
curl -sS -G "https://api.poketrace.com/v1/cards/${CARD_ID}/prices/PSA_10/history" \
  --data-urlencode 'period=30d' \
  --data-urlencode 'limit=50' \
  -H "X-API-Key: ${POKETRACE_API_KEY}" \
  -o supabase/functions/price-comp/__fixtures__/poketrace/charizard-psa10-history-30d.json

jq '.data | length, .data[0]' \
  supabase/functions/price-comp/__fixtures__/poketrace/charizard-psa10-history-30d.json
```

Expected: a `data` array (at least one element) where each element has `date`, `source`, `avg`. Record the count.

- [ ] **Step 7: Reconcile fixture against the spec**

Compare findings to spec assumptions:

| Spec claim | Verify against fixture |
|---|---|
| Graded tiers live under `data.prices.ebay.<TIER>` | Run the jq above. Note the actual source key name. |
| Tier strings are `PSA_10`, `PSA_9_5`, `BGS_10`, `CGC_10`, `SGC_10` | Confirm exact casing. |
| Values are decimal dollars | Confirm — multiply by 100 to convert to cents. |
| History entries are `{date, source, avg}` | Confirm shape; note if `avg` can be `null`. |

If the source key is **not** `ebay`, edit the spec at section "Edge Function Changes" → "prices.ts" and update the description. Bump an `Update history` line at the bottom of the spec.

- [ ] **Step 8: Commit fixtures**

```bash
git add supabase/functions/price-comp/__fixtures__/poketrace/
# Also stage the spec edit if any
git status --short
git commit -m "chore(price-comp): capture poketrace baseline fixtures"
```

---

## Phase 1 — Database migration

### Task 1: Add `poketrace_card_id` to identities and extend `graded_market` for the second source

**Files:**
- Create: `supabase/migrations/<ts>_add_poketrace_to_graded_market.sql` — replace `<ts>` with `date -u +%Y%m%d%H%M%S` at run time.

- [ ] **Step 1: Generate the timestamped migration filename**

```bash
TS="$(date -u +%Y%m%d%H%M%S)"
echo "Migration timestamp: $TS"
# Write down the timestamp; it's used in Step 2 and again in any
# manual schema_migrations INSERT later.
MIG="supabase/migrations/${TS}_add_poketrace_to_graded_market.sql"
echo "Migration path: $MIG"
```

- [ ] **Step 2: Write the migration**

Create the file at the path printed above with this exact content:

```sql
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
```

- [ ] **Step 3: Apply the migration locally (or to the dev project)**

```bash
supabase db push
# Expected: "Applying migration <ts>_add_poketrace_to_graded_market.sql"
# then "Finished supabase db push.".
#
# If the output reports "constraint already exists" because the ledger
# is out of sync, follow the memory note feedback_supabase_migration_ledger:
#   psql "$SUPABASE_DB_URL" -c "INSERT INTO supabase_migrations.schema_migrations (version) VALUES ('<ts>')"
```

- [ ] **Step 4: Verify the schema change**

```bash
psql "$SUPABASE_DB_URL" -c "
  select column_name, data_type, is_nullable
    from information_schema.columns
   where table_schema='public' and table_name='graded_market'
     and (column_name like 'pt_%' or column_name in ('source'))
   order by column_name;
"
# Expected: rows for pt_avg, pt_avg_1d, pt_avg_30d, pt_avg_7d, pt_confidence,
# pt_high, pt_low, pt_median_30d, pt_median_3d, pt_median_7d, pt_sale_count,
# pt_trend, source.

psql "$SUPABASE_DB_URL" -c "
  select conname, pg_get_constraintdef(oid)
    from pg_constraint
   where conrelid = 'public.graded_market'::regclass
     and contype = 'p';
"
# Expected: constraint name 'graded_market_pkey' over
# (identity_id, grading_service, grade, source).

psql "$SUPABASE_DB_URL" -c "
  select column_name from information_schema.columns
   where table_schema='public' and table_name='graded_card_identities'
     and column_name like 'poketrace%';
"
# Expected: poketrace_card_id, poketrace_card_id_resolved_at.
```

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/
git commit -m "feat(db): add poketrace_card_id and pt_* columns to graded tables"
```

---

## Phase 2 — Edge Function shared layer

### Task 2: Add poketrace tier-key helper

**Files:**
- Create: `supabase/functions/price-comp/lib/poketrace-tier-key.ts`
- Create: `supabase/functions/price-comp/__tests__/poketrace-tier-key.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/price-comp/__tests__/poketrace-tier-key.test.ts`:

```ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { poketraceTierKey } from "../lib/poketrace-tier-key.ts";

Deno.test("poketraceTierKey: PSA + 10 → PSA_10", () => {
  assertEquals(poketraceTierKey("PSA", "10"), "PSA_10");
});

Deno.test("poketraceTierKey: PSA + 9.5 → PSA_9_5", () => {
  assertEquals(poketraceTierKey("PSA", "9.5"), "PSA_9_5");
});

Deno.test("poketraceTierKey: BGS + 10 → BGS_10", () => {
  assertEquals(poketraceTierKey("BGS", "10"), "BGS_10");
});

Deno.test("poketraceTierKey: lowercase grading service is normalized", () => {
  assertEquals(poketraceTierKey("psa", "10"), "PSA_10");
});

Deno.test("poketraceTierKey: SGC + 9.5 → SGC_9_5", () => {
  assertEquals(poketraceTierKey("SGC", "9.5"), "SGC_9_5");
});

Deno.test("poketraceTierKey: TAG + 1.5 → TAG_1_5", () => {
  assertEquals(poketraceTierKey("TAG", "1.5"), "TAG_1_5");
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd supabase/functions/price-comp
deno test __tests__/poketrace-tier-key.test.ts
```

Expected: FAIL with module-not-found ("Cannot find module '../lib/poketrace-tier-key.ts'").

- [ ] **Step 3: Implement the helper**

Create `supabase/functions/price-comp/lib/poketrace-tier-key.ts`:

```ts
// supabase/functions/price-comp/lib/poketrace-tier-key.ts
//
// Build a Poketrace tier key from a (gradingService, grade) pair as the
// app stores them on graded_market. Poketrace's tier strings replace
// '.' with '_' in the grade portion.
//
//   ('PSA', '10')  -> 'PSA_10'
//   ('PSA', '9.5') -> 'PSA_9_5'
//   ('BGS', '10')  -> 'BGS_10'
//
// Documented at https://poketrace.com/docs/markets-tiers.

import type { GradingService } from "../types.ts";

export function poketraceTierKey(
  service: GradingService | string,
  grade: string,
): string {
  return `${service.toUpperCase()}_${grade.replace(".", "_")}`;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
deno test __tests__/poketrace-tier-key.test.ts
```

Expected: PASS — 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/lib/poketrace-tier-key.ts \
        supabase/functions/price-comp/__tests__/poketrace-tier-key.test.ts
git commit -m "feat(price-comp): add poketrace tier-key helper"
```

---

### Task 3: Extend `types.ts` with Poketrace and Reconciled response blocks

**Files:**
- Modify: `supabase/functions/price-comp/types.ts`

- [ ] **Step 1: Append new exports to `types.ts`**

Add at the END of `supabase/functions/price-comp/types.ts` (after the existing `CacheState` export):

```ts

// ---- Poketrace (second source) ---------------------------------------------

export interface PoketraceTierFields {
  avg_cents:        number | null;
  low_cents:        number | null;
  high_cents:       number | null;
  avg_1d_cents:     number | null;
  avg_7d_cents:     number | null;
  avg_30d_cents:    number | null;
  median_3d_cents:  number | null;
  median_7d_cents:  number | null;
  median_30d_cents: number | null;
  trend:            "up" | "down" | "stable" | null;
  confidence:       "high" | "medium" | "low" | null;
  sale_count:       number | null;
}

export interface PoketraceBlock extends PoketraceTierFields {
  card_id: string;
  tier:    string;                 // e.g. "PSA_10"
  price_history: PriceHistoryWirePoint[];
  fetched_at: string;
}

export type ReconciledSource = "avg" | "ppt-only" | "poketrace-only";

export interface ReconciledBlock {
  headline_price_cents: number | null;
  source: ReconciledSource;
}

// Wider response envelope. The legacy fields at the top remain populated for
// the PPT branch so existing iOS clients on v1 keep working until the new
// CompRepository decoder ships.
export interface PriceCompResponseV2 extends PriceCompResponse {
  poketrace: PoketraceBlock | null;
  reconciled: ReconciledBlock;
}
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/price-comp/types.ts
git commit -m "feat(price-comp): add Poketrace and Reconciled response types"
```

There is no test for this step — types alone cannot be exercised at runtime. They are exercised by Tasks 8, 9, and the iOS decoder tests in Phase 5.

---

### Task 4: Extend `persistence/market.ts` to take a `source` argument

**Files:**
- Modify: `supabase/functions/price-comp/persistence/market.ts`

- [ ] **Step 1: Add the source parameter and matching upsert / read changes**

In `supabase/functions/price-comp/persistence/market.ts`:

Replace the existing `MarketUpsertInput` interface (lines 7–16) with:

```ts
export type MarketSource = "pokemonpricetracker" | "poketrace";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  source: MarketSource;
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  priceHistory: PriceHistoryPoint[];
  pptTCGPlayerId: string;
  pptUrl: string;
  poketrace?: {
    avgCents:        number | null;
    lowCents:        number | null;
    highCents:       number | null;
    avg1dCents:      number | null;
    avg7dCents:      number | null;
    avg30dCents:     number | null;
    median3dCents:   number | null;
    median7dCents:   number | null;
    median30dCents:  number | null;
    trend:           "up" | "down" | "stable" | null;
    confidence:      "high" | "medium" | "low" | null;
    saleCount:       number | null;
  };
}
```

Replace the body of `upsertMarketLadder` (lines 23–50) with:

```ts
export async function upsertMarketLadder(
  supabase: SupabaseClient,
  input: MarketUpsertInput,
): Promise<void> {
  const isPpt = input.source === "pokemonpricetracker";
  const row: Record<string, unknown> = {
    identity_id: input.identityId,
    grading_service: input.gradingService,
    grade: input.grade,
    source: input.source,
    price_history: input.priceHistory,
    headline_price: centsToDecimal(input.headlinePriceCents),
    updated_at: new Date().toISOString(),
  };

  if (isPpt) {
    Object.assign(row, {
      ppt_tcgplayer_id: input.pptTCGPlayerId,
      ppt_url: input.pptUrl,
      loose_price:    centsToDecimal(input.ladderCents.loose),
      psa_7_price:    centsToDecimal(input.ladderCents.psa_7),
      psa_8_price:    centsToDecimal(input.ladderCents.psa_8),
      psa_9_price:    centsToDecimal(input.ladderCents.psa_9),
      psa_9_5_price:  centsToDecimal(input.ladderCents.psa_9_5),
      psa_10_price:   centsToDecimal(input.ladderCents.psa_10),
      bgs_10_price:   centsToDecimal(input.ladderCents.bgs_10),
      cgc_10_price:   centsToDecimal(input.ladderCents.cgc_10),
      sgc_10_price:   centsToDecimal(input.ladderCents.sgc_10),
    });
  } else if (input.poketrace) {
    Object.assign(row, {
      pt_avg:        centsToDecimal(input.poketrace.avgCents),
      pt_low:        centsToDecimal(input.poketrace.lowCents),
      pt_high:       centsToDecimal(input.poketrace.highCents),
      pt_avg_1d:     centsToDecimal(input.poketrace.avg1dCents),
      pt_avg_7d:     centsToDecimal(input.poketrace.avg7dCents),
      pt_avg_30d:    centsToDecimal(input.poketrace.avg30dCents),
      pt_median_3d:  centsToDecimal(input.poketrace.median3dCents),
      pt_median_7d:  centsToDecimal(input.poketrace.median7dCents),
      pt_median_30d: centsToDecimal(input.poketrace.median30dCents),
      pt_trend:      input.poketrace.trend,
      pt_confidence: input.poketrace.confidence,
      pt_sale_count: input.poketrace.saleCount,
    });
  }

  const { error } = await supabase
    .from("graded_market")
    .upsert(row, { onConflict: "identity_id,grading_service,grade,source" });
  if (error) throw new Error(`graded_market upsert: ${error.message}`);
}
```

Replace the `readMarketLadder` signature (lines 68–73) and body to take a `source`:

```ts
export async function readMarketLadder(
  supabase: SupabaseClient,
  identityId: string,
  gradingService: GradingService,
  grade: string,
  source: MarketSource = "pokemonpricetracker",
): Promise<MarketReadResult | null> {
  const { data } = await supabase
    .from("graded_market")
    .select(
      "headline_price, loose_price, " +
      "psa_7_price, psa_8_price, psa_9_price, psa_9_5_price, psa_10_price, " +
      "bgs_10_price, cgc_10_price, sgc_10_price, " +
      "price_history, ppt_tcgplayer_id, ppt_url, updated_at, " +
      "pt_avg, pt_low, pt_high, pt_avg_1d, pt_avg_7d, pt_avg_30d, " +
      "pt_median_3d, pt_median_7d, pt_median_30d, " +
      "pt_trend, pt_confidence, pt_sale_count",
    )
    .eq("identity_id", identityId)
    .eq("grading_service", gradingService)
    .eq("grade", grade)
    .eq("source", source)
    .maybeSingle();
  if (!data) return null;
  // ... existing tail (history parse + return) unchanged below ...
```

Replace the `MarketReadResult` interface to include the Poketrace fields:

```ts
export interface MarketReadResult {
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  priceHistory: PriceHistoryPoint[];
  pptTCGPlayerId: string | null;
  pptUrl: string | null;
  updatedAt: string | null;
  // Poketrace fields. Populated only when reading source='poketrace'.
  poketrace: {
    avgCents:        number | null;
    lowCents:        number | null;
    highCents:       number | null;
    avg1dCents:      number | null;
    avg7dCents:      number | null;
    avg30dCents:     number | null;
    median3dCents:   number | null;
    median7dCents:   number | null;
    median30dCents:  number | null;
    trend:           "up" | "down" | "stable" | null;
    confidence:      "high" | "medium" | "low" | null;
    saleCount:       number | null;
  } | null;
}
```

In the return object of `readMarketLadder` (after `priceHistory: history,`), add:

```ts
    pptTCGPlayerId: data.ppt_tcgplayer_id ?? null,
    pptUrl: data.ppt_url ?? null,
    updatedAt: data.updated_at ?? null,
    poketrace: source === "poketrace"
      ? {
          avgCents:       decimalToCents(data.pt_avg),
          lowCents:       decimalToCents(data.pt_low),
          highCents:      decimalToCents(data.pt_high),
          avg1dCents:     decimalToCents(data.pt_avg_1d),
          avg7dCents:     decimalToCents(data.pt_avg_7d),
          avg30dCents:    decimalToCents(data.pt_avg_30d),
          median3dCents:  decimalToCents(data.pt_median_3d),
          median7dCents:  decimalToCents(data.pt_median_7d),
          median30dCents: decimalToCents(data.pt_median_30d),
          trend:          (data.pt_trend ?? null) as MarketReadResult["poketrace"] extends infer R ? R extends { trend: infer T } ? T : never : never,
          confidence:     (data.pt_confidence ?? null) as MarketReadResult["poketrace"] extends infer R ? R extends { confidence: infer C } ? C : never : never,
          saleCount:      typeof data.pt_sale_count === "number" ? data.pt_sale_count : null,
        }
      : null,
```

If the conditional-type cast is awkward in editor, use a simple `as any` — the runtime values are validated by the DB CHECK constraint:

```ts
      trend:      (data.pt_trend ?? null) as ("up" | "down" | "stable" | null),
      confidence: (data.pt_confidence ?? null) as ("high" | "medium" | "low" | null),
```

- [ ] **Step 2: Update existing PPT call site to pass `source`**

In `supabase/functions/price-comp/index.ts`, find the existing call to `upsertMarketLadder(supabase, { ... })` (around line 215) and add `source: "pokemonpricetracker",` to the input object literal. Existing call:

```ts
    await upsertMarketLadder(supabase, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service,
      grade: body.grade,
      headlinePriceCents: headlineCents,
      ladderCents: ladder,
      priceHistory: history,
      pptTCGPlayerId: resolvedTCGPlayerId,
      pptUrl: url,
    });
```

becomes:

```ts
    await upsertMarketLadder(supabase, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service,
      grade: body.grade,
      source: "pokemonpricetracker",
      headlinePriceCents: headlineCents,
      ladderCents: ladder,
      priceHistory: history,
      pptTCGPlayerId: resolvedTCGPlayerId,
      pptUrl: url,
    });
```

Also update both `readMarketLadder` calls (around lines 93 and elsewhere) to pass `"pokemonpricetracker"` explicitly:

```ts
  const cached = await readMarketLadder(
    supabase,
    body.graded_card_identity_id,
    body.grading_service,
    body.grade,
    "pokemonpricetracker",
  );
```

- [ ] **Step 3: Run the existing edge-function tests**

```bash
cd supabase/functions/price-comp
deno test __tests__/index.test.ts __tests__/regression.test.ts
```

Expected: PASS. The `source` argument has a default of `'pokemonpricetracker'` so legacy call sites still compile, but we updated the explicit call sites for readability.

If a test fails because the test stub doesn't expose `source` on its query mock, update the mock. (See `__tests__/index.test.ts` for the existing supabase stub pattern.)

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/price-comp/persistence/market.ts \
        supabase/functions/price-comp/index.ts
git commit -m "feat(price-comp): persistence layer accepts source arg"
```

---

### Task 5: Add identity helpers for the Poketrace UUID cache

**Files:**
- Modify: `supabase/functions/price-comp/persistence/identity-product-id.ts`

- [ ] **Step 1: Append two new functions**

Append to `supabase/functions/price-comp/persistence/identity-product-id.ts`:

```ts

// ---- Poketrace UUID cache ---------------------------------------------------
//
// Cache the Poketrace card UUID on graded_card_identities so we don't re-do
// the tcgplayer_ids cross-walk on every scan. Empty string '' is the
// "tried, no match" sentinel — re-attempt after 7 days.

const POKETRACE_NEGATIVE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export async function persistIdentityPoketraceCardId(
  supabase: SupabaseClient,
  identityId: string,
  cardId: string, // empty string for "no match" sentinel
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({
      poketrace_card_id: cardId,
      poketrace_card_id_resolved_at: new Date().toISOString(),
    })
    .eq("id", identityId);
  if (error) throw new Error(`identity poketrace_card_id update: ${error.message}`);
}

export async function clearIdentityPoketraceCardId(
  supabase: SupabaseClient,
  identityId: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({
      poketrace_card_id: null,
      poketrace_card_id_resolved_at: null,
    })
    .eq("id", identityId);
  if (error) throw new Error(`identity poketrace_card_id clear: ${error.message}`);
}

/**
 * True when an empty-string sentinel is fresh enough that we should NOT
 * re-attempt the cross-walk.
 */
export function poketraceNegativeCacheStillFresh(
  resolvedAtIso: string | null,
  nowMs: number,
): boolean {
  if (!resolvedAtIso) return false;
  const resolvedMs = Date.parse(resolvedAtIso);
  if (!Number.isFinite(resolvedMs)) return false;
  return nowMs - resolvedMs < POKETRACE_NEGATIVE_TTL_MS;
}
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/price-comp/persistence/identity-product-id.ts
git commit -m "feat(price-comp): add poketrace_card_id cache helpers"
```

---

## Phase 3 — Poketrace API client

### Task 6: Implement `poketrace/client.ts`

**Files:**
- Create: `supabase/functions/price-comp/poketrace/client.ts`
- Create: `supabase/functions/price-comp/__tests__/poketrace-client.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/price-comp/__tests__/poketrace-client.test.ts`:

```ts
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchJson } from "../poketrace/client.ts";

Deno.test("fetchJson: sends X-API-Key header and returns parsed body", async () => {
  let observedHeaders: Headers | null = null;
  const stubFetch: typeof fetch = (input, init) => {
    observedHeaders = new Headers(init?.headers ?? {});
    return Promise.resolve(new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "content-type": "application/json", "x-ratelimit-daily-remaining": "499" },
    }));
  };
  const result = await fetchJson(
    { apiKey: "k", baseUrl: "https://api.poketrace.com/v1", fetchImpl: stubFetch },
    "/health",
  );
  assertEquals(result.status, 200);
  assertEquals(result.body, { ok: true });
  assertEquals(result.dailyRemaining, 499);
  assert(observedHeaders);
  assertEquals(observedHeaders!.get("x-api-key"), "k");
});

Deno.test("fetchJson: retries once on 502", async () => {
  let calls = 0;
  const stubFetch: typeof fetch = () => {
    calls += 1;
    if (calls === 1) return Promise.resolve(new Response("nope", { status: 502 }));
    return Promise.resolve(new Response(JSON.stringify({ ok: true }), {
      status: 200, headers: { "content-type": "application/json" },
    }));
  };
  const result = await fetchJson(
    { apiKey: "k", baseUrl: "https://api.poketrace.com/v1", fetchImpl: stubFetch },
    "/cards/abc",
  );
  assertEquals(calls, 2);
  assertEquals(result.status, 200);
});

Deno.test("fetchJson: returns the 4xx response without retrying", async () => {
  let calls = 0;
  const stubFetch: typeof fetch = () => {
    calls += 1;
    return Promise.resolve(new Response('{"error":"not found"}', {
      status: 404, headers: { "content-type": "application/json" },
    }));
  };
  const result = await fetchJson(
    { apiKey: "k", baseUrl: "https://api.poketrace.com/v1", fetchImpl: stubFetch },
    "/cards/missing",
  );
  assertEquals(calls, 1);
  assertEquals(result.status, 404);
});

Deno.test("fetchJson: timeout aborts the request", async () => {
  const stubFetch: typeof fetch = (_input, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
      // never resolves
    });
  let threw = false;
  try {
    await fetchJson(
      { apiKey: "k", baseUrl: "https://api.poketrace.com/v1", fetchImpl: stubFetch, timeoutMs: 10 },
      "/cards/slow",
    );
  } catch (e) {
    threw = e instanceof Error && e.message.includes("timeout");
  }
  assert(threw, "expected fetchJson to throw on timeout");
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd supabase/functions/price-comp
deno test __tests__/poketrace-client.test.ts
```

Expected: FAIL with module-not-found.

- [ ] **Step 3: Implement the client**

Create `supabase/functions/price-comp/poketrace/client.ts`:

```ts
// supabase/functions/price-comp/poketrace/client.ts
//
// Minimal Poketrace HTTP client. Production code uses the global `fetch`
// implementation; tests inject a stub via `fetchImpl`. Authentication is
// `X-API-Key: <key>` per https://poketrace.com/docs/authentication.

export interface PoketraceClientOptions {
  apiKey: string;
  baseUrl: string;             // e.g. "https://api.poketrace.com/v1"
  fetchImpl?: typeof fetch;
  timeoutMs?: number;          // default 8000
}

export interface FetchResult<T> {
  status: number;
  body: T | null;
  dailyRemaining: number | null; // x-ratelimit-daily-remaining header
}

const DEFAULT_TIMEOUT_MS = 8000;

export async function fetchJson<T>(
  opts: PoketraceClientOptions,
  pathAndQuery: string,
): Promise<FetchResult<T>> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const url = `${opts.baseUrl}${pathAndQuery}`;
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  async function once(): Promise<Response> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await fetchImpl(url, {
        method: "GET",
        headers: {
          "x-api-key": opts.apiKey,
          "accept": "application/json",
        },
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }
  }

  let resp: Response;
  try {
    resp = await once();
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") {
      throw new Error(`poketrace timeout after ${timeoutMs}ms: ${pathAndQuery}`);
    }
    throw e;
  }

  if (resp.status >= 500 && resp.status <= 599) {
    // One short retry — covers transient 5xx without amplifying outages.
    await new Promise((r) => setTimeout(r, 250));
    try { resp = await once(); }
    catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") {
        throw new Error(`poketrace timeout after ${timeoutMs}ms: ${pathAndQuery}`);
      }
      throw e;
    }
  }

  const dailyRemainingHeader = resp.headers.get("x-ratelimit-daily-remaining");
  const dailyRemaining = dailyRemainingHeader !== null && Number.isFinite(Number(dailyRemainingHeader))
    ? Number(dailyRemainingHeader)
    : null;

  let body: T | null = null;
  if (resp.headers.get("content-type")?.includes("application/json")) {
    try { body = (await resp.json()) as T; } catch { body = null; }
  }
  return { status: resp.status, body, dailyRemaining };
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
deno test __tests__/poketrace-client.test.ts
```

Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/poketrace/client.ts \
        supabase/functions/price-comp/__tests__/poketrace-client.test.ts
git commit -m "feat(price-comp): add poketrace HTTP client"
```

---

### Task 7: Implement `poketrace/match.ts` (cross-walk + cache)

**Files:**
- Create: `supabase/functions/price-comp/poketrace/match.ts`
- Create: `supabase/functions/price-comp/__tests__/poketrace-match.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/price-comp/__tests__/poketrace-match.test.ts`:

```ts
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { resolvePoketraceCardId } from "../poketrace/match.ts";

type IdentityRow = {
  id: string;
  ppt_tcgplayer_id: string | null;
  poketrace_card_id: string | null;
  poketrace_card_id_resolved_at: string | null;
};

function fakeSupabase(identity: IdentityRow, calls: { updates: number }) {
  return {
    from(_t: string) {
      return {
        update(patch: Record<string, unknown>) {
          calls.updates += 1;
          identity.poketrace_card_id = (patch.poketrace_card_id as string | null) ?? null;
          identity.poketrace_card_id_resolved_at = (patch.poketrace_card_id_resolved_at as string | null) ?? null;
          return { eq: (_c: string, _v: string) => ({ error: null }) };
        },
      };
    },
  } as unknown;
}

Deno.test("resolvePoketraceCardId: returns cached UUID without an HTTP call", async () => {
  const identity: IdentityRow = {
    id: "id1",
    ppt_tcgplayer_id: "243172",
    poketrace_card_id: "11111111-1111-1111-1111-111111111111",
    poketrace_card_id_resolved_at: new Date().toISOString(),
  };
  const calls = { updates: 0 };
  let httpCalls = 0;
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    {
      fetchJsonImpl: () => { httpCalls += 1; return Promise.resolve({ status: 200, body: null, dailyRemaining: null }); },
    },
  );
  assertEquals(result, "11111111-1111-1111-1111-111111111111");
  assertEquals(httpCalls, 0);
  assertEquals(calls.updates, 0);
});

Deno.test("resolvePoketraceCardId: empty-string sentinel within 7d returns null", async () => {
  const identity: IdentityRow = {
    id: "id2",
    ppt_tcgplayer_id: "243172",
    poketrace_card_id: "",
    poketrace_card_id_resolved_at: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
  };
  const calls = { updates: 0 };
  let httpCalls = 0;
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    { fetchJsonImpl: () => { httpCalls += 1; return Promise.resolve({ status: 200, body: null, dailyRemaining: null }); } },
  );
  assertEquals(result, null);
  assertEquals(httpCalls, 0);
});

Deno.test("resolvePoketraceCardId: uncached → cross-walk → persists UUID and returns it", async () => {
  const identity: IdentityRow = {
    id: "id3",
    ppt_tcgplayer_id: "243172",
    poketrace_card_id: null,
    poketrace_card_id_resolved_at: null,
  };
  const calls = { updates: 0 };
  let observedPath = "";
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    {
      fetchJsonImpl: (_opts, path) => {
        observedPath = path;
        return Promise.resolve({
          status: 200,
          dailyRemaining: 499,
          body: { data: [{ id: "22222222-2222-2222-2222-222222222222", name: "Charizard", cardNumber: "4" }] },
        });
      },
    },
  );
  assertEquals(result, "22222222-2222-2222-2222-222222222222");
  assert(observedPath.startsWith("/cards?"));
  assert(observedPath.includes("tcgplayer_ids=243172"));
  assertEquals(calls.updates, 1);
  assertEquals(identity.poketrace_card_id, "22222222-2222-2222-2222-222222222222");
});

Deno.test("resolvePoketraceCardId: cross-walk returns 0 results → persists '' sentinel", async () => {
  const identity: IdentityRow = {
    id: "id4",
    ppt_tcgplayer_id: "999999",
    poketrace_card_id: null,
    poketrace_card_id_resolved_at: null,
  };
  const calls = { updates: 0 };
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    {
      fetchJsonImpl: () => Promise.resolve({ status: 200, dailyRemaining: 499, body: { data: [] } }),
    },
  );
  assertEquals(result, null);
  assertEquals(calls.updates, 1);
  assertEquals(identity.poketrace_card_id, "");
});

Deno.test("resolvePoketraceCardId: identity has no ppt_tcgplayer_id → returns null without HTTP call", async () => {
  const identity: IdentityRow = {
    id: "id5",
    ppt_tcgplayer_id: null,
    poketrace_card_id: null,
    poketrace_card_id_resolved_at: null,
  };
  const calls = { updates: 0 };
  let httpCalls = 0;
  const result = await resolvePoketraceCardId(
    {
      supabase: fakeSupabase(identity, calls),
      client: { apiKey: "k", baseUrl: "https://api.poketrace.com/v1" },
      now: () => Date.now(),
    },
    identity,
    { fetchJsonImpl: () => { httpCalls += 1; return Promise.resolve({ status: 200, body: null, dailyRemaining: null }); } },
  );
  assertEquals(result, null);
  assertEquals(httpCalls, 0);
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
deno test __tests__/poketrace-match.test.ts
```

Expected: FAIL with module-not-found.

- [ ] **Step 3: Implement match.ts**

Create `supabase/functions/price-comp/poketrace/match.ts`:

```ts
// @ts-nocheck — Deno runtime
// supabase/functions/price-comp/poketrace/match.ts
//
// Resolve a graded_card_identity to a Poketrace card UUID using the
// previously-persisted ppt_tcgplayer_id. Cache the UUID on the identity
// so subsequent scans skip the cross-walk.
//
//   * Hit (non-empty UUID cached): return it.
//   * Negative-hit ('' sentinel within 7d): return null without retrying.
//   * Miss: GET /cards?tcgplayer_ids=<id>. Persist the first result's UUID
//     (or '' when 0 results).

import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import {
  persistIdentityPoketraceCardId,
  poketraceNegativeCacheStillFresh,
} from "../persistence/identity-product-id.ts";

interface IdentityForMatch {
  id: string;
  ppt_tcgplayer_id: string | null;
  poketrace_card_id: string | null;
  poketrace_card_id_resolved_at: string | null;
}

export interface ResolveDeps {
  supabase: SupabaseClient;
  client: PoketraceClientOptions;
  now: () => number;
}

export interface ResolveOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

interface CardSearchResponse {
  data: Array<{ id: string }>;
}

/**
 * Returns the resolved Poketrace card UUID, or null if no match exists.
 * Persists the result on `graded_card_identities`.
 */
export async function resolvePoketraceCardId(
  deps: ResolveDeps,
  identity: IdentityForMatch,
  overrides: ResolveOverrides = {},
): Promise<string | null> {
  // 1. Positive cache hit
  if (identity.poketrace_card_id && identity.poketrace_card_id !== "") {
    return identity.poketrace_card_id;
  }

  // 2. Negative cache (recently looked up, no match) — skip retry for 7d
  if (
    identity.poketrace_card_id === "" &&
    poketraceNegativeCacheStillFresh(identity.poketrace_card_id_resolved_at, deps.now())
  ) {
    return null;
  }

  // 3. No tcgPlayerId on identity → cannot cross-walk
  if (!identity.ppt_tcgplayer_id) {
    return null;
  }

  // 4. Live cross-walk
  const fetchImpl = overrides.fetchJsonImpl ?? fetchJson;
  const path = `/cards?tcgplayer_ids=${encodeURIComponent(identity.ppt_tcgplayer_id)}&limit=20&has_graded=true`;
  const res = await fetchImpl<CardSearchResponse>(deps.client, path);

  if (res.status !== 200 || !res.body?.data) {
    // Don't poison the cache on transient failures — return null and try
    // again next scan. Only the empty-array case persists the sentinel.
    return null;
  }

  if (res.body.data.length === 0) {
    await persistIdentityPoketraceCardId(deps.supabase, identity.id, "");
    return null;
  }

  const cardId = res.body.data[0].id;
  await persistIdentityPoketraceCardId(deps.supabase, identity.id, cardId);
  return cardId;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
deno test __tests__/poketrace-match.test.ts
```

Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/poketrace/match.ts \
        supabase/functions/price-comp/__tests__/poketrace-match.test.ts
git commit -m "feat(price-comp): add poketrace card_id resolver with caching"
```

---

### Task 8: Implement `poketrace/parse.ts`

**Files:**
- Create: `supabase/functions/price-comp/poketrace/parse.ts`
- Create: `supabase/functions/price-comp/__tests__/poketrace-parse.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/price-comp/__tests__/poketrace-parse.test.ts`:

```ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  extractTierPrice,
  tierPriceToBlock,
  parseHistoryResponse,
  type RawTierPrice,
} from "../poketrace/parse.ts";

Deno.test("extractTierPrice: walks data.prices.<source>.<tier>", () => {
  const card = {
    data: {
      id: "uuid-1",
      prices: {
        ebay:      { PSA_10: { avg: 185.00, low: 170.00, high: 199.99 } },
        tcgplayer: { NEAR_MINT: { avg: 95 } },
      },
    },
  };
  const tp = extractTierPrice(card, "PSA_10");
  assertEquals(tp?.avg, 185.0);
  assertEquals(tp?.low, 170.0);
  assertEquals(tp?.high, 199.99);
});

Deno.test("extractTierPrice: missing tier returns null", () => {
  const card = { data: { id: "uuid-1", prices: { ebay: { PSA_9: { avg: 50 } } } } };
  assertEquals(extractTierPrice(card, "PSA_10"), null);
});

Deno.test("extractTierPrice: missing prices returns null", () => {
  assertEquals(extractTierPrice({ data: { id: "uuid-1" } }, "PSA_10"), null);
});

Deno.test("tierPriceToBlock: dollars → cents, missing fields → null", () => {
  const raw: RawTierPrice = {
    avg: 185.50,
    low: 170,
    high: 199.99,
    avg30d: 180,
    median7d: 178.45,
    trend: "stable",
    confidence: "high",
    saleCount: 42,
  };
  const block = tierPriceToBlock(raw);
  assertEquals(block.avg_cents, 18550);
  assertEquals(block.low_cents, 17000);
  assertEquals(block.high_cents, 19999);
  assertEquals(block.avg_30d_cents, 18000);
  assertEquals(block.median_7d_cents, 17845);
  assertEquals(block.trend, "stable");
  assertEquals(block.confidence, "high");
  assertEquals(block.sale_count, 42);
  // Fields not present in raw → null
  assertEquals(block.avg_1d_cents, null);
  assertEquals(block.avg_7d_cents, null);
  assertEquals(block.median_3d_cents, null);
  assertEquals(block.median_30d_cents, null);
});

Deno.test("tierPriceToBlock: rounds half away from zero", () => {
  const block = tierPriceToBlock({ avg: 12.345 });
  // 12.345 * 100 = 1234.5 → round → 1235 (Math.round is half-to-positive)
  assertEquals(block.avg_cents, 1235);
});

Deno.test("tierPriceToBlock: rejects non-numeric trend/confidence", () => {
  // deno-lint-ignore no-explicit-any
  const block = tierPriceToBlock({ avg: 50, trend: "wat" as any, confidence: 7 as any });
  assertEquals(block.trend, null);
  assertEquals(block.confidence, null);
});

Deno.test("parseHistoryResponse: maps date+avg → ts+price_cents", () => {
  const resp = {
    data: [
      { date: "2026-04-08", source: "ebay", avg: 180 },
      { date: "2026-04-09", source: "ebay", avg: 182.5 },
      { date: "2026-04-10", source: "ebay" }, // missing avg → skipped
      { date: "2026-04-11", source: "ebay", avg: null }, // null avg → skipped
    ],
  };
  const points = parseHistoryResponse(resp);
  assertEquals(points.length, 2);
  assertEquals(points[0], { ts: "2026-04-08T00:00:00Z", price_cents: 18000 });
  assertEquals(points[1], { ts: "2026-04-09T00:00:00Z", price_cents: 18250 });
});

Deno.test("parseHistoryResponse: missing or non-array data → []", () => {
  assertEquals(parseHistoryResponse({} as Record<string, unknown>), []);
  assertEquals(parseHistoryResponse({ data: null }), []);
  assertEquals(parseHistoryResponse({ data: "nope" } as Record<string, unknown>), []);
});
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
deno test __tests__/poketrace-parse.test.ts
```

Expected: FAIL with module-not-found.

- [ ] **Step 3: Implement parse.ts**

Create `supabase/functions/price-comp/poketrace/parse.ts`:

```ts
// supabase/functions/price-comp/poketrace/parse.ts
//
// Pure transforms. No I/O.
//   * extractTierPrice: walk Poketrace card detail to find a tier under
//     any of the top-level price source keys (e.g. ebay, tcgplayer).
//   * tierPriceToBlock: TierPrice (decimal dollars) → wire-shaped block
//     (integer cents).
//   * parseHistoryResponse: PriceHistoryResponse → app-shaped
//     [{ ts, price_cents }].

import type { PoketraceTierFields } from "../types.ts";
import type { PriceHistoryPoint } from "../ppt/parse.ts";

export interface RawTierPrice {
  avg?: number | null;
  low?: number | null;
  high?: number | null;
  avg1d?: number | null;
  avg7d?: number | null;
  avg30d?: number | null;
  median3d?: number | null;
  median7d?: number | null;
  median30d?: number | null;
  trend?: "up" | "down" | "stable" | null;
  confidence?: "high" | "medium" | "low" | null;
  saleCount?: number | null;
}

interface CardDetailEnvelope {
  data?: {
    id?: string;
    prices?: Record<string, Record<string, RawTierPrice>>;
  };
}

const TREND_VALUES = new Set(["up", "down", "stable"]);
const CONFIDENCE_VALUES = new Set(["high", "medium", "low"]);

function dollarsToCents(v: unknown): number | null {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  return Math.round(v * 100);
}

export function extractTierPrice(
  card: CardDetailEnvelope,
  tierKey: string,
): RawTierPrice | null {
  const prices = card.data?.prices;
  if (!prices || typeof prices !== "object") return null;
  for (const sourceKey of Object.keys(prices)) {
    const sourceMap = prices[sourceKey];
    if (sourceMap && typeof sourceMap === "object" && tierKey in sourceMap) {
      return sourceMap[tierKey] ?? null;
    }
  }
  return null;
}

export function tierPriceToBlock(tp: RawTierPrice): PoketraceTierFields {
  const trend: PoketraceTierFields["trend"] =
    typeof tp.trend === "string" && TREND_VALUES.has(tp.trend)
      ? (tp.trend as PoketraceTierFields["trend"])
      : null;
  const confidence: PoketraceTierFields["confidence"] =
    typeof tp.confidence === "string" && CONFIDENCE_VALUES.has(tp.confidence)
      ? (tp.confidence as PoketraceTierFields["confidence"])
      : null;
  return {
    avg_cents:        dollarsToCents(tp.avg),
    low_cents:        dollarsToCents(tp.low),
    high_cents:       dollarsToCents(tp.high),
    avg_1d_cents:     dollarsToCents(tp.avg1d),
    avg_7d_cents:     dollarsToCents(tp.avg7d),
    avg_30d_cents:    dollarsToCents(tp.avg30d),
    median_3d_cents:  dollarsToCents(tp.median3d),
    median_7d_cents:  dollarsToCents(tp.median7d),
    median_30d_cents: dollarsToCents(tp.median30d),
    trend,
    confidence,
    sale_count: typeof tp.saleCount === "number" && Number.isFinite(tp.saleCount) ? tp.saleCount : null,
  };
}

interface HistoryEntry {
  date?: string;
  avg?: number | null;
}

interface HistoryEnvelope {
  data?: HistoryEntry[] | unknown;
}

export function parseHistoryResponse(resp: HistoryEnvelope | Record<string, unknown>): PriceHistoryPoint[] {
  const data = (resp as HistoryEnvelope).data;
  if (!Array.isArray(data)) return [];
  const out: PriceHistoryPoint[] = [];
  for (const entry of data) {
    if (!entry || typeof entry.date !== "string") continue;
    const cents = dollarsToCents(entry.avg);
    if (cents === null) continue;
    // Poketrace returns dates as YYYY-MM-DD; promote to midnight UTC ISO.
    const ts = `${entry.date}T00:00:00Z`;
    out.push({ ts, price_cents: cents });
  }
  return out;
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
deno test __tests__/poketrace-parse.test.ts
```

Expected: PASS — 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/poketrace/parse.ts \
        supabase/functions/price-comp/__tests__/poketrace-parse.test.ts
git commit -m "feat(price-comp): add poketrace TierPrice + history parsers"
```

---

### Task 9: Implement `poketrace/prices.ts` and `poketrace/history.ts`

**Files:**
- Create: `supabase/functions/price-comp/poketrace/prices.ts`
- Create: `supabase/functions/price-comp/poketrace/history.ts`

These are thin orchestration layers over `client.ts` + `parse.ts`. Their happy paths are covered by the integration test in Task 11; per-function unit tests would just re-test the wiring of two already-tested functions. We skip the dedicated unit tests for these two files in favor of the integration test.

- [ ] **Step 1: Implement prices.ts**

Create `supabase/functions/price-comp/poketrace/prices.ts`:

```ts
// supabase/functions/price-comp/poketrace/prices.ts
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import { extractTierPrice, tierPriceToBlock, type RawTierPrice } from "./parse.ts";
import type { PoketraceTierFields } from "../types.ts";

export interface FetchPoketracePricesOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

export interface PoketracePricesResult {
  status: number;
  fields: PoketraceTierFields | null; // null when tier not present
  raw: RawTierPrice | null;
}

export async function fetchPoketracePrices(
  client: PoketraceClientOptions,
  cardId: string,
  tierKey: string,
  overrides: FetchPoketracePricesOverrides = {},
): Promise<PoketracePricesResult> {
  const fetchImpl = overrides.fetchJsonImpl ?? fetchJson;
  const res = await fetchImpl<{ data?: { prices?: Record<string, Record<string, RawTierPrice>> } }>(
    client, `/cards/${encodeURIComponent(cardId)}`,
  );
  if (res.status !== 200 || !res.body) {
    return { status: res.status, fields: null, raw: null };
  }
  const raw = extractTierPrice(res.body, tierKey);
  if (!raw) return { status: 200, fields: null, raw: null };
  return { status: 200, fields: tierPriceToBlock(raw), raw };
}
```

- [ ] **Step 2: Implement history.ts**

Create `supabase/functions/price-comp/poketrace/history.ts`:

```ts
// supabase/functions/price-comp/poketrace/history.ts
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import { parseHistoryResponse } from "./parse.ts";
import type { PriceHistoryPoint } from "../ppt/parse.ts";

export interface FetchPoketraceHistoryOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

export interface PoketraceHistoryResult {
  status: number;
  history: PriceHistoryPoint[];
}

export async function fetchPoketraceHistory(
  client: PoketraceClientOptions,
  cardId: string,
  tierKey: string,
  overrides: FetchPoketraceHistoryOverrides = {},
): Promise<PoketraceHistoryResult> {
  const fetchImpl = overrides.fetchJsonImpl ?? fetchJson;
  const path = `/cards/${encodeURIComponent(cardId)}/prices/${encodeURIComponent(tierKey)}/history?period=30d&limit=50`;
  const res = await fetchImpl<{ data?: unknown }>(client, path);
  if (res.status !== 200 || !res.body) {
    return { status: res.status, history: [] };
  }
  return { status: 200, history: parseHistoryResponse(res.body) };
}
```

- [ ] **Step 3: Type-check**

```bash
cd supabase/functions/price-comp
deno check poketrace/prices.ts poketrace/history.ts
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/price-comp/poketrace/prices.ts \
        supabase/functions/price-comp/poketrace/history.ts
git commit -m "feat(price-comp): add poketrace prices + history fetchers"
```

---

## Phase 4 — Edge Function orchestration

### Task 10: Wire the Poketrace branch into `index.ts`

**Files:**
- Modify: `supabase/functions/price-comp/index.ts`

- [ ] **Step 1: Add imports**

At the top of `index.ts`, alongside existing imports, add:

```ts
import { resolvePoketraceCardId } from "./poketrace/match.ts";
import { fetchPoketracePrices } from "./poketrace/prices.ts";
import { fetchPoketraceHistory } from "./poketrace/history.ts";
import { poketraceTierKey } from "./lib/poketrace-tier-key.ts";
import type { PoketraceBlock, ReconciledBlock, PriceCompResponseV2 } from "./types.ts";
```

- [ ] **Step 2: Extend `HandleDeps`**

Replace the `HandleDeps` interface (around lines 60–66) with:

```ts
export interface HandleDeps {
  supabase: SupabaseClient | unknown;
  pptBaseUrl: string;
  pptToken: string;
  ttlSeconds: number;
  poketraceBaseUrl: string;
  poketraceApiKey: string | null; // null disables the branch
  now: () => number;
}
```

- [ ] **Step 3: Add a Poketrace branch helper**

After the `staleOrUpstreamDown` helper (near the end of the file, before `Deno.serve`), add:

```ts
async function fetchPoketraceBranch(
  deps: HandleDeps,
  identity: { id: string; ppt_tcgplayer_id: string | null; poketrace_card_id: string | null; poketrace_card_id_resolved_at: string | null },
  service: GradingService,
  grade: string,
): Promise<PoketraceBlock | null> {
  if (!deps.poketraceApiKey) return null;
  const client = { apiKey: deps.poketraceApiKey, baseUrl: deps.poketraceBaseUrl };
  const cardId = await resolvePoketraceCardId(
    { supabase: deps.supabase as SupabaseClient, client, now: deps.now },
    identity,
  );
  if (!cardId) return null;

  const tierKey = poketraceTierKey(service, grade);
  const [pricesRes, historyRes] = await Promise.allSettled([
    fetchPoketracePrices(client, cardId, tierKey),
    fetchPoketraceHistory(client, cardId, tierKey),
  ]);

  const prices = pricesRes.status === "fulfilled" ? pricesRes.value : null;
  const history = historyRes.status === "fulfilled" ? historyRes.value.history : [];

  if (!prices || !prices.fields) return null;

  return {
    card_id: cardId,
    tier: tierKey,
    ...prices.fields,
    price_history: history,
    fetched_at: new Date().toISOString(),
  };
}

function reconcile(
  pptHeadlineCents: number | null,
  poketrace: PoketraceBlock | null,
): ReconciledBlock {
  const ptAvg = poketrace?.avg_cents ?? null;
  if (pptHeadlineCents !== null && ptAvg !== null) {
    return {
      headline_price_cents: Math.round((pptHeadlineCents + ptAvg) / 2),
      source: "avg",
    };
  }
  if (pptHeadlineCents !== null) {
    return { headline_price_cents: pptHeadlineCents, source: "ppt-only" };
  }
  if (ptAvg !== null) {
    return { headline_price_cents: ptAvg, source: "poketrace-only" };
  }
  return { headline_price_cents: null, source: "ppt-only" };
}
```

- [ ] **Step 4: Run the Poketrace branch in parallel with the existing PPT flow**

The existing happy-path (lines ~114–251) reads PPT data, persists, and builds the response. We refactor minimally: capture the PPT response into a local variable, fan out to Poketrace concurrently, then build the V2 envelope.

Locate the final `return json(200, buildResponse({ ... }))` near line 240 and replace it with:

```ts
  const pptResponse = buildResponse({
    ladderCents: ladder,
    headlineCents,
    service: body.grading_service,
    grade: body.grade,
    priceHistory: history,
    tcgPlayerId: resolvedTCGPlayerId,
    pptUrl: url,
    cacheHit: false,
    isStaleFallback: false,
  });

  // V1 LIMITATION (intentional for shipping speed): the Poketrace branch
  // runs sequentially AFTER the PPT happy path completes. This means PPT
  // failures (404 NO_MARKET_DATA, AUTH_INVALID, etc.) short-circuit the
  // request before Poketrace gets a chance, so the spec's
  // 'poketrace-only' reconciliation source path is unreachable in v1.
  // Refactoring index.ts to fan out PPT into a helper and run both
  // providers via Promise.allSettled is tracked as a follow-up — see
  // spec section "V1 limitations".
  //
  // The Poketrace call has its own 8s per-fetch timeout in client.ts.
  let poketraceBlock: PoketraceBlock | null = null;
  try {
    poketraceBlock = await fetchPoketraceBranch(
      deps,
      {
        id: identity.id,
        ppt_tcgplayer_id: identity.ppt_tcgplayer_id ?? null,
        poketrace_card_id: identity.poketrace_card_id ?? null,
        poketrace_card_id_resolved_at: identity.poketrace_card_id_resolved_at ?? null,
      },
      body.grading_service,
      body.grade,
    );
  } catch (e) {
    console.error("poketrace.branch_failed", { message: (e as Error).message });
  }

  // Persist Poketrace row (fire-and-log; persistence failure does not fail the request)
  if (poketraceBlock) {
    try {
      await upsertMarketLadder(supabase, {
        identityId: body.graded_card_identity_id,
        gradingService: body.grading_service,
        grade: body.grade,
        source: "poketrace",
        headlinePriceCents: poketraceBlock.avg_cents,
        ladderCents: { loose: null, psa_7: null, psa_8: null, psa_9: null, psa_9_5: null, psa_10: null, bgs_10: null, cgc_10: null, sgc_10: null },
        priceHistory: poketraceBlock.price_history,
        pptTCGPlayerId: "",
        pptUrl: "",
        poketrace: {
          avgCents:       poketraceBlock.avg_cents,
          lowCents:       poketraceBlock.low_cents,
          highCents:      poketraceBlock.high_cents,
          avg1dCents:     poketraceBlock.avg_1d_cents,
          avg7dCents:     poketraceBlock.avg_7d_cents,
          avg30dCents:    poketraceBlock.avg_30d_cents,
          median3dCents:  poketraceBlock.median_3d_cents,
          median7dCents:  poketraceBlock.median_7d_cents,
          median30dCents: poketraceBlock.median_30d_cents,
          trend:          poketraceBlock.trend,
          confidence:     poketraceBlock.confidence,
          saleCount:      poketraceBlock.sale_count,
        },
      });
    } catch (e) {
      console.error("poketrace.persist.market_failed", { message: (e as Error).message });
    }
  }

  const reconciledBlock = reconcile(pptResponse.headline_price_cents, poketraceBlock);

  const v2: PriceCompResponseV2 = {
    ...pptResponse,
    poketrace: poketraceBlock,
    reconciled: reconciledBlock,
  };
  return json(200, v2);
```

Apply the same `pptResponse + poketrace + reconciled` envelope to the cache-hit path (around line 100). Replace:

```ts
  if (state === "hit" && cached) {
    return json(200, buildResponse({ ... }));
  }
```

with:

```ts
  if (state === "hit" && cached) {
    const pptResponse = buildResponse({
      ladderCents: cached.ladderCents,
      headlineCents: cached.headlinePriceCents,
      service: body.grading_service,
      grade: body.grade,
      priceHistory: cached.priceHistory,
      tcgPlayerId: cached.pptTCGPlayerId ?? identity.ppt_tcgplayer_id ?? "",
      pptUrl: cached.pptUrl ?? identity.ppt_url ?? "",
      cacheHit: true,
      isStaleFallback: false,
    });

    // Read cached Poketrace row separately; if fresh enough, return it
    // alongside the PPT cache hit.
    const cachedPt = await readMarketLadder(
      supabase, body.graded_card_identity_id, body.grading_service, body.grade, "poketrace",
    );
    let poketraceBlock: PoketraceBlock | null = null;
    if (cachedPt && cachedPt.poketrace) {
      const tierKey = poketraceTierKey(body.grading_service, body.grade);
      poketraceBlock = {
        card_id: identity.poketrace_card_id ?? "",
        tier: tierKey,
        avg_cents:        cachedPt.poketrace.avgCents,
        low_cents:        cachedPt.poketrace.lowCents,
        high_cents:       cachedPt.poketrace.highCents,
        avg_1d_cents:     cachedPt.poketrace.avg1dCents,
        avg_7d_cents:     cachedPt.poketrace.avg7dCents,
        avg_30d_cents:    cachedPt.poketrace.avg30dCents,
        median_3d_cents:  cachedPt.poketrace.median3dCents,
        median_7d_cents:  cachedPt.poketrace.median7dCents,
        median_30d_cents: cachedPt.poketrace.median30dCents,
        trend:            cachedPt.poketrace.trend,
        confidence:       cachedPt.poketrace.confidence,
        sale_count:       cachedPt.poketrace.saleCount,
        price_history:    cachedPt.priceHistory,
        fetched_at:       cachedPt.updatedAt ?? new Date().toISOString(),
      };
    }
    const reconciledBlock = reconcile(pptResponse.headline_price_cents, poketraceBlock);
    const v2: PriceCompResponseV2 = { ...pptResponse, poketrace: poketraceBlock, reconciled: reconciledBlock };
    return json(200, v2);
  }
```

Apply the same envelope to `staleOrUpstreamDown`'s response — it returns a 200 with cached data and should also include `poketrace: null, reconciled: { headline_price_cents: cached.headlinePriceCents, source: "ppt-only" }`. Update the helper:

```ts
async function staleOrUpstreamDown(
  cached: Awaited<ReturnType<typeof readMarketLadder>>,
  body: PriceCompRequest,
  marker: string,
): Promise<Response> {
  console.error("ppt.upstream_5xx", { marker });
  if (!cached) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  const pptResponse = buildResponse({
    ladderCents: cached.ladderCents,
    headlineCents: cached.headlinePriceCents,
    service: body.grading_service,
    grade: body.grade,
    priceHistory: cached.priceHistory,
    tcgPlayerId: cached.pptTCGPlayerId ?? "",
    pptUrl: cached.pptUrl ?? "",
    cacheHit: true,
    isStaleFallback: true,
  });
  const v2: PriceCompResponseV2 = {
    ...pptResponse,
    poketrace: null,
    reconciled: { headline_price_cents: cached.headlinePriceCents, source: "ppt-only" },
  };
  return json(200, v2);
}
```

- [ ] **Step 5: Update `Deno.serve` startup to load the new env vars**

Replace the `Deno.serve` block at the bottom (line 273) with:

```ts
Deno.serve(async (req) => {
  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  const poketraceApiKey = (() => {
    try { return env("POKETRACE_API_KEY"); }
    catch { return null; }
  })();
  if (!poketraceApiKey) {
    console.warn("price-comp.poketrace_disabled", { reason: "POKETRACE_API_KEY not set" });
  }
  return await handle(req, {
    supabase,
    pptBaseUrl: "https://www.pokemonpricetracker.com",
    pptToken: env("POKEMONPRICETRACKER_API_TOKEN"),
    ttlSeconds: Number(env("POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS", "86400")),
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey,
    now: () => Date.now(),
  });
});
```

- [ ] **Step 6: Run the existing tests to confirm nothing regressed**

```bash
cd supabase/functions/price-comp
deno test
```

Expected: PASS — all existing tests still pass. The Poketrace branch is gated by `poketraceApiKey == null` so existing test setups (which don't set it) take the legacy path.

If `__tests__/index.test.ts` builds `HandleDeps` literals, add the two new fields to the test fixtures:

```ts
poketraceBaseUrl: "https://api.poketrace.com/v1",
poketraceApiKey: null,
```

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/price-comp/index.ts
git commit -m "feat(price-comp): fan out to poketrace and return v2 envelope"
```

---

### Task 11: Integration test for the fan-out

**Files:**
- Create: `supabase/functions/price-comp/__tests__/index-fanout.test.ts`

- [ ] **Step 1: Write the test**

Create `supabase/functions/price-comp/__tests__/index-fanout.test.ts`:

```ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handle, type HandleDeps } from "../index.ts";

// Minimal in-memory supabase stub. Mirrors the patterns in __tests__/index.test.ts.
function makeSupabase(initial: { identity?: Record<string, unknown>; market?: Record<string, unknown> }) {
  const tables: Record<string, Record<string, unknown>[]> = {
    graded_card_identities: initial.identity ? [initial.identity] : [],
    graded_market: initial.market ? [initial.market] : [],
  };
  return {
    from(name: string) {
      const rows = tables[name] ??= [];
      return {
        select(_cols?: string) {
          return {
            eq(col: string, val: unknown) {
              return {
                eq(col2: string, val2: unknown) {
                  return {
                    eq(col3: string, val3: unknown) {
                      return {
                        eq(col4: string, val4: unknown) {
                          return {
                            maybeSingle() {
                              const r = rows.find((r) => r[col] === val && r[col2] === val2 && r[col3] === val3 && r[col4] === val4);
                              return Promise.resolve({ data: r ?? null, error: null });
                            },
                            single() {
                              const r = rows.find((r) => r[col] === val && r[col2] === val2 && r[col3] === val3 && r[col4] === val4);
                              return Promise.resolve({ data: r ?? null, error: r ? null : { message: "not found" } });
                            },
                          };
                        },
                        maybeSingle() {
                          const r = rows.find((r) => r[col] === val && r[col2] === val2 && r[col3] === val3);
                          return Promise.resolve({ data: r ?? null, error: null });
                        },
                      };
                    },
                  };
                },
                single() {
                  const r = rows.find((r) => r[col] === val);
                  return Promise.resolve({ data: r ?? null, error: r ? null : { message: "not found" } });
                },
                maybeSingle() {
                  const r = rows.find((r) => r[col] === val);
                  return Promise.resolve({ data: r ?? null, error: null });
                },
              };
            },
          };
        },
        upsert(row: Record<string, unknown>) {
          // Replace-or-insert by composite key.
          const idx = rows.findIndex((r) =>
            r.identity_id === row.identity_id &&
            r.grading_service === row.grading_service &&
            r.grade === row.grade &&
            r.source === row.source);
          if (idx >= 0) rows[idx] = row;
          else rows.push(row);
          return Promise.resolve({ error: null });
        },
        update(patch: Record<string, unknown>) {
          return {
            eq(col: string, val: unknown) {
              const r = rows.find((r) => r[col] === val);
              if (r) Object.assign(r, patch);
              return Promise.resolve({ error: null });
            },
          };
        },
      };
    },
    inspect() { return tables; },
  } as unknown;
}

const IDENTITY = {
  id: "00000000-0000-0000-0000-000000000001",
  game: "pokemon",
  language: "en",
  set_code: "BS",
  set_name: "Base Set",
  card_number: "4",
  card_name: "Charizard",
  variant: null,
  year: 1999,
  ppt_tcgplayer_id: "243172",
  ppt_url: "https://www.pokemonpricetracker.com/card/charizard",
  poketrace_card_id: null,
  poketrace_card_id_resolved_at: null,
};

function makeRequest() {
  return new Request("http://x/price-comp", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      graded_card_identity_id: IDENTITY.id,
      grading_service: "PSA",
      grade: "10",
    }),
  });
}

// We replace the global fetch for the duration of each test.
function withStubFetch<T>(stub: typeof fetch, fn: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  return fn().finally(() => { globalThis.fetch = original; });
}

Deno.test("v2 envelope: both PPT and Poketrace succeed → reconciled is the average", async () => {
  const supabase = makeSupabase({ identity: { ...IDENTITY } });
  const stubFetch: typeof fetch = (input) => {
    const url = String(input);
    if (url.includes("pokemonpricetracker.com")) {
      // PPT stub: minimal "Charizard PSA 10 = $185.00"
      return Promise.resolve(new Response(JSON.stringify({
        cards: [{
          tcgPlayerId: 243172,
          name: "Charizard",
          ebay: { grades: { psa_10: 185.00, psa_9: 80, psa_9_5: 120, psa_8: 50, psa_7: 30, bgs_10: 220, cgc_10: 170, sgc_10: 165 } },
          tcgPlayer: { market: 4 },
          priceHistory: [],
          url: "https://www.pokemonpricetracker.com/card/charizard",
        }],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/cards?")) {
      return Promise.resolve(new Response(JSON.stringify({
        data: [{ id: "22222222-2222-2222-2222-222222222222" }],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.match(/\/cards\/[^/]+$/)) {
      return Promise.resolve(new Response(JSON.stringify({
        data: { id: "22222222-2222-2222-2222-222222222222", prices: { ebay: { PSA_10: { avg: 195.00, low: 180, high: 210, trend: "stable", confidence: "high", saleCount: 24 } } } },
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify({
        data: [{ date: "2026-04-30", source: "ebay", avg: 192 }],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    return Promise.resolve(new Response("not stubbed: " + url, { status: 599 }));
  };

  const deps: HandleDeps = {
    supabase,
    pptBaseUrl: "https://www.pokemonpricetracker.com",
    pptToken: "ppt-token",
    ttlSeconds: 86400,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: "pt-key",
    now: () => Date.parse("2026-05-08T12:00:00Z"),
  };

  const resp = await withStubFetch(stubFetch, () => handle(makeRequest(), deps));
  assertEquals(resp.status, 200);
  const body = await resp.json();
  assertEquals(body.headline_price_cents, 18500); // PPT psa_10
  assert(body.poketrace);
  assertEquals(body.poketrace.tier, "PSA_10");
  assertEquals(body.poketrace.avg_cents, 19500);
  assertEquals(body.poketrace.trend, "stable");
  assertEquals(body.poketrace.sale_count, 24);
  assertEquals(body.reconciled.source, "avg");
  // (18500 + 19500) / 2 = 19000
  assertEquals(body.reconciled.headline_price_cents, 19000);
});

Deno.test("v2 envelope: poketrace down → reconciled = ppt-only", async () => {
  const supabase = makeSupabase({ identity: { ...IDENTITY } });
  const stubFetch: typeof fetch = (input) => {
    const url = String(input);
    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(JSON.stringify({
        cards: [{
          tcgPlayerId: 243172, name: "Charizard",
          ebay: { grades: { psa_10: 185.00, psa_9: 80, psa_9_5: 120, psa_8: 50, psa_7: 30, bgs_10: 220, cgc_10: 170, sgc_10: 165 } },
          tcgPlayer: { market: 4 },
          priceHistory: [], url: "https://www.pokemonpricetracker.com/card/charizard",
        }],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com")) {
      return Promise.resolve(new Response("upstream down", { status: 503 }));
    }
    return Promise.resolve(new Response("not stubbed", { status: 599 }));
  };
  const resp = await withStubFetch(stubFetch, () => handle(makeRequest(), {
    supabase,
    pptBaseUrl: "https://www.pokemonpricetracker.com",
    pptToken: "ppt-token",
    ttlSeconds: 86400,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: "pt-key",
    now: () => Date.parse("2026-05-08T12:00:00Z"),
  }));
  const body = await resp.json();
  assertEquals(body.poketrace, null);
  assertEquals(body.reconciled.source, "ppt-only");
  assertEquals(body.reconciled.headline_price_cents, 18500);
});

Deno.test("v2 envelope: poketrace api key not configured → branch quietly skipped", async () => {
  const supabase = makeSupabase({ identity: { ...IDENTITY } });
  const stubFetch: typeof fetch = (input) => {
    const url = String(input);
    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(JSON.stringify({
        cards: [{
          tcgPlayerId: 243172, name: "Charizard",
          ebay: { grades: { psa_10: 185.00, psa_9: 80, psa_9_5: 120, psa_8: 50, psa_7: 30, bgs_10: 220, cgc_10: 170, sgc_10: 165 } },
          tcgPlayer: { market: 4 },
          priceHistory: [], url: "https://www.pokemonpricetracker.com/card/charizard",
        }],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    return Promise.resolve(new Response("should not be called", { status: 599 }));
  };
  const resp = await withStubFetch(stubFetch, () => handle(makeRequest(), {
    supabase,
    pptBaseUrl: "https://www.pokemonpricetracker.com",
    pptToken: "ppt-token",
    ttlSeconds: 86400,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: null,
    now: () => Date.parse("2026-05-08T12:00:00Z"),
  }));
  assertEquals(resp.status, 200);
  const body = await resp.json();
  assertEquals(body.poketrace, null);
  assertEquals(body.reconciled.source, "ppt-only");
});
```

- [ ] **Step 2: Run the test**

```bash
cd supabase/functions/price-comp
deno test __tests__/index-fanout.test.ts
```

Expected: PASS — 3 tests pass. If a test stub mismatch surfaces (e.g. an `eq` chain depth mismatch in `makeSupabase`), align the chain depth to what the new `readMarketLadder` requires (4 `.eq`s — identity, service, grade, source).

- [ ] **Step 3: Run the entire price-comp test suite**

```bash
deno test
```

Expected: PASS — all tests pass.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/price-comp/__tests__/index-fanout.test.ts
git commit -m "test(price-comp): cover v2 envelope fan-out cases"
```

---

## Phase 5 — iOS

### Task 12: Reshape `GradedMarketSnapshot` for two sources

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift`

The unique key on this `@Model` becomes `(identityId, gradingService, grade, source)`. SwiftData lightweight migration tolerates added optional fields and a different unique-attribute set when the schema container is rebuilt with `Schema.Migration`. Since `GradedMarketSnapshot` is a *cache* of server-derivable data (per the existing model docstring), the safe path is a **destructive migration**: drop the local SwiftData store on first launch under the new schema. The PPT migration in `2026-05-07-pokemonpricetracker-comp-implementation.md` used the same approach.

- [ ] **Step 1: Add `source` and `pt_*` properties + bump init**

Replace the entire body of `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift` with:

```swift
import Foundation
import SwiftData

@Model
final class GradedMarketSnapshot {
    var identityId: UUID
    var gradingService: String
    var grade: String

    /// "pokemonpricetracker" | "poketrace". Two snapshots can coexist for the
    /// same (identity, service, grade) — one per source.
    var source: String

    var headlinePriceCents: Int64?

    // PPT-shaped ladder. Only populated when source == "pokemonpricetracker".
    var loosePriceCents: Int64?
    var psa7PriceCents: Int64?
    var psa8PriceCents: Int64?
    var psa9PriceCents: Int64?
    var psa9_5PriceCents: Int64?
    var psa10PriceCents: Int64?
    var bgs10PriceCents: Int64?
    var cgc10PriceCents: Int64?
    var sgc10PriceCents: Int64?

    var pptTCGPlayerId: String?
    var pptURL: URL?

    // Poketrace-shaped fields. Only populated when source == "poketrace".
    var ptAvgCents: Int64?
    var ptLowCents: Int64?
    var ptHighCents: Int64?
    var ptAvg1dCents: Int64?
    var ptAvg7dCents: Int64?
    var ptAvg30dCents: Int64?
    var ptMedian3dCents: Int64?
    var ptMedian7dCents: Int64?
    var ptMedian30dCents: Int64?
    var ptTrend: String?      // "up" | "down" | "stable"
    var ptConfidence: String? // "high" | "medium" | "low"
    var ptSaleCount: Int?
    var poketraceCardId: String?

    /// JSON-encoded `[PriceHistoryPoint]`. See note in earlier spec.
    var priceHistoryJSON: String?

    var fetchedAt: Date
    var cacheHit: Bool
    var isStaleFallback: Bool

    init(
        identityId: UUID,
        gradingService: String,
        grade: String,
        source: String,
        headlinePriceCents: Int64?,
        loosePriceCents: Int64? = nil,
        psa7PriceCents: Int64? = nil,
        psa8PriceCents: Int64? = nil,
        psa9PriceCents: Int64? = nil,
        psa9_5PriceCents: Int64? = nil,
        psa10PriceCents: Int64? = nil,
        bgs10PriceCents: Int64? = nil,
        cgc10PriceCents: Int64? = nil,
        sgc10PriceCents: Int64? = nil,
        pptTCGPlayerId: String? = nil,
        pptURL: URL? = nil,
        ptAvgCents: Int64? = nil,
        ptLowCents: Int64? = nil,
        ptHighCents: Int64? = nil,
        ptAvg1dCents: Int64? = nil,
        ptAvg7dCents: Int64? = nil,
        ptAvg30dCents: Int64? = nil,
        ptMedian3dCents: Int64? = nil,
        ptMedian7dCents: Int64? = nil,
        ptMedian30dCents: Int64? = nil,
        ptTrend: String? = nil,
        ptConfidence: String? = nil,
        ptSaleCount: Int? = nil,
        poketraceCardId: String? = nil,
        priceHistoryJSON: String?,
        fetchedAt: Date,
        cacheHit: Bool,
        isStaleFallback: Bool
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
        self.source = source
        self.headlinePriceCents = headlinePriceCents
        self.loosePriceCents = loosePriceCents
        self.psa7PriceCents = psa7PriceCents
        self.psa8PriceCents = psa8PriceCents
        self.psa9PriceCents = psa9PriceCents
        self.psa9_5PriceCents = psa9_5PriceCents
        self.psa10PriceCents = psa10PriceCents
        self.bgs10PriceCents = bgs10PriceCents
        self.cgc10PriceCents = cgc10PriceCents
        self.sgc10PriceCents = sgc10PriceCents
        self.pptTCGPlayerId = pptTCGPlayerId
        self.pptURL = pptURL
        self.ptAvgCents = ptAvgCents
        self.ptLowCents = ptLowCents
        self.ptHighCents = ptHighCents
        self.ptAvg1dCents = ptAvg1dCents
        self.ptAvg7dCents = ptAvg7dCents
        self.ptAvg30dCents = ptAvg30dCents
        self.ptMedian3dCents = ptMedian3dCents
        self.ptMedian7dCents = ptMedian7dCents
        self.ptMedian30dCents = ptMedian30dCents
        self.ptTrend = ptTrend
        self.ptConfidence = ptConfidence
        self.ptSaleCount = ptSaleCount
        self.poketraceCardId = poketraceCardId
        self.priceHistoryJSON = priceHistoryJSON
        self.fetchedAt = fetchedAt
        self.cacheHit = cacheHit
        self.isStaleFallback = isStaleFallback
    }

    var priceHistory: [PriceHistoryPoint] {
        guard let json = priceHistoryJSON, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PriceHistoryPoint].self, from: data)) ?? []
    }
}

extension GradedMarketSnapshot {
    static let sourcePPT = "pokemonpricetracker"
    static let sourcePoketrace = "poketrace"
}
```

- [ ] **Step 2: Trigger destructive store rebuild**

The local SwiftData store containing the previous `GradedMarketSnapshot` shape is incompatible with the new schema (added `source` field, expanded uniqueness implicit when callers persist 2 rows per scan). Locate the `ModelContainer` setup in the app — typically in `slabbistApp.swift` or a dedicated `PersistenceController.swift`. Check by searching:

```bash
rg -n "ModelContainer\(" ios/slabbist/slabbist/ | head
```

Update the version constant the project uses to detect schema changes. The PPT migration commit `2026-05-07` should have introduced a `currentSchemaVersion` literal somewhere in the persistence setup. Increment it (or follow the pattern shown there). The destructive rebuild path deletes the old store on launch and recreates it.

If the project uses a simple `ModelContainer(for: ..., configurations: .init(isStoredInMemoryOnly: false))` without a version guard, follow the pattern from the PPT plan: catch the `ModelContainer` init failure, delete the store directory, rebuild.

- [ ] **Step 3: Type-check**

Open the slabbist workspace in Xcode and build (⌘B). Expected: build succeeds. If a callsite passes the old initializer, fix it to pass `source:` (use `GradedMarketSnapshot.sourcePPT` for legacy code paths).

```bash
cd ios/slabbist
xcodebuild -workspace slabbist.xcworkspace -scheme slabbist -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -40
```

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift
# Plus any persistence-version bump
git commit -m "feat(ios): GradedMarketSnapshot grows source + pt_* columns"
```

---

### Task 13: Extend `CompRepository.Wire` / `Decoded` for v2 envelope

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompRepository.swift`

- [ ] **Step 1: Write the failing test**

Edit `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift` and append (inside the `struct CompRepositoryTests` body):

```swift
    @Test("decodes a v2 envelope with both PPT and Poketrace blocks present")
    func decodesV2BothSources() async throws {
        let json = #"""
        {
          "headline_price_cents": 18500,
          "grading_service": "PSA",
          "grade": "10",
          "loose_price_cents": 400,
          "psa_7_price_cents": 2400,
          "psa_8_price_cents": 3400,
          "psa_9_price_cents": 6800,
          "psa_9_5_price_cents": 11200,
          "psa_10_price_cents": 18500,
          "bgs_10_price_cents": 21500,
          "cgc_10_price_cents": 16800,
          "sgc_10_price_cents": 16500,
          "price_history": [{ "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 }],
          "ppt_tcgplayer_id": "243172",
          "ppt_url": "https://www.pokemonpricetracker.com/card/charizard",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false,
          "is_stale_fallback": false,
          "poketrace": {
            "card_id": "22222222-2222-2222-2222-222222222222",
            "tier": "PSA_10",
            "avg_cents": 19500,
            "low_cents": 18000,
            "high_cents": 21000,
            "avg_1d_cents": null,
            "avg_7d_cents": 19400,
            "avg_30d_cents": 19200,
            "median_3d_cents": 19500,
            "median_7d_cents": 19350,
            "median_30d_cents": 19000,
            "trend": "stable",
            "confidence": "high",
            "sale_count": 24,
            "price_history": [{ "ts": "2026-04-30T00:00:00Z", "price_cents": 19200 }],
            "fetched_at": "2026-05-07T22:14:03Z"
          },
          "reconciled": { "headline_price_cents": 19000, "source": "avg" }
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == 18500)
        #expect(decoded.poketrace != nil)
        #expect(decoded.poketrace?.avgCents == 19500)
        #expect(decoded.poketrace?.trend == "stable")
        #expect(decoded.poketrace?.confidence == "high")
        #expect(decoded.poketrace?.saleCount == 24)
        #expect(decoded.reconciledHeadlineCents == 19000)
        #expect(decoded.reconciledSource == "avg")
    }

    @Test("decodes a v2 envelope with poketrace null (PPT-only)")
    func decodesV2PptOnly() async throws {
        let json = #"""
        {
          "headline_price_cents": 18500,
          "grading_service": "PSA", "grade": "10",
          "loose_price_cents": 400,
          "psa_7_price_cents": null, "psa_8_price_cents": null,
          "psa_9_price_cents": null, "psa_9_5_price_cents": null,
          "psa_10_price_cents": 18500, "bgs_10_price_cents": null,
          "cgc_10_price_cents": null, "sgc_10_price_cents": null,
          "price_history": [],
          "ppt_tcgplayer_id": "243172",
          "ppt_url": "https://www.pokemonpricetracker.com/card/charizard",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false, "is_stale_fallback": false,
          "poketrace": null,
          "reconciled": { "headline_price_cents": 18500, "source": "ppt-only" }
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.poketrace == nil)
        #expect(decoded.reconciledSource == "ppt-only")
    }

    @Test("decodes a legacy (pre-v2) response with no poketrace/reconciled blocks")
    func decodesLegacyResponse() async throws {
        let json = #"""
        {
          "headline_price_cents": 18500,
          "grading_service": "PSA", "grade": "10",
          "loose_price_cents": 400,
          "psa_7_price_cents": null, "psa_8_price_cents": null,
          "psa_9_price_cents": null, "psa_9_5_price_cents": null,
          "psa_10_price_cents": 18500, "bgs_10_price_cents": null,
          "cgc_10_price_cents": null, "sgc_10_price_cents": null,
          "price_history": [],
          "ppt_tcgplayer_id": "243172",
          "ppt_url": "https://www.pokemonpricetracker.com/card/charizard",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false, "is_stale_fallback": false
        }
        """#.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.poketrace == nil)
        #expect(decoded.reconciledHeadlineCents == 18500)   // falls back to PPT headline
        #expect(decoded.reconciledSource == "ppt-only")     // synthesized
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

In Xcode: ⌘U (test). Or:

```bash
cd ios/slabbist
xcodebuild -workspace slabbist.xcworkspace -scheme slabbist \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:slabbistTests/CompRepositoryTests 2>&1 | tail -40
```

Expected: FAIL — `decoded.poketrace`, `decoded.reconciledHeadlineCents`, `decoded.reconciledSource` are not yet members of `Decoded`.

- [ ] **Step 3: Extend `Wire` and `Decoded`**

Edit `ios/slabbist/slabbist/Features/Comp/CompRepository.swift`. Inside the `Wire` struct (after `is_stale_fallback`), add:

```swift
        // v2 additions; both optional so legacy responses still decode.
        let poketrace: PoketraceWire?
        let reconciled: ReconciledWire?

        struct PoketraceWire: Decodable {
            let card_id: String
            let tier: String
            let avg_cents: Int64?
            let low_cents: Int64?
            let high_cents: Int64?
            let avg_1d_cents: Int64?
            let avg_7d_cents: Int64?
            let avg_30d_cents: Int64?
            let median_3d_cents: Int64?
            let median_7d_cents: Int64?
            let median_30d_cents: Int64?
            let trend: String?
            let confidence: String?
            let sale_count: Int?
            let price_history: [PriceHistoryPoint]
            let fetched_at: Date
        }
        struct ReconciledWire: Decodable {
            let headline_price_cents: Int64?
            let source: String
        }
```

Inside `Decoded`, after the existing fields, add:

```swift
        let poketrace: SourceComp?
        let reconciledHeadlineCents: Int64?
        let reconciledSource: String  // "avg" | "ppt-only" | "poketrace-only"

        struct SourceComp: Equatable {
            let cardId: String
            let tier: String
            let avgCents: Int64?
            let lowCents: Int64?
            let highCents: Int64?
            let avg1dCents: Int64?
            let avg7dCents: Int64?
            let avg30dCents: Int64?
            let median3dCents: Int64?
            let median7dCents: Int64?
            let median30dCents: Int64?
            let trend: String?
            let confidence: String?
            let saleCount: Int?
            let priceHistory: [PriceHistoryPoint]
            let fetchedAt: Date
        }
```

In the `decode` function, after constructing the existing `Decoded(...)` instance, replace the old return with:

```swift
        let poketrace = wire.poketrace.map { pt in
            Decoded.SourceComp(
                cardId: pt.card_id, tier: pt.tier,
                avgCents: pt.avg_cents, lowCents: pt.low_cents, highCents: pt.high_cents,
                avg1dCents: pt.avg_1d_cents, avg7dCents: pt.avg_7d_cents, avg30dCents: pt.avg_30d_cents,
                median3dCents: pt.median_3d_cents, median7dCents: pt.median_7d_cents, median30dCents: pt.median_30d_cents,
                trend: pt.trend, confidence: pt.confidence, saleCount: pt.sale_count,
                priceHistory: pt.price_history, fetchedAt: pt.fetched_at
            )
        }
        let reconciledCents = wire.reconciled?.headline_price_cents ?? wire.headline_price_cents
        let reconciledSource = wire.reconciled?.source ?? "ppt-only"
        return Decoded(
            headlinePriceCents: wire.headline_price_cents,
            gradingService: wire.grading_service,
            grade: wire.grade,
            loosePriceCents: wire.loose_price_cents,
            psa7PriceCents: wire.psa_7_price_cents,
            psa8PriceCents: wire.psa_8_price_cents,
            psa9PriceCents: wire.psa_9_price_cents,
            psa9_5PriceCents: wire.psa_9_5_price_cents,
            psa10PriceCents: wire.psa_10_price_cents,
            bgs10PriceCents: wire.bgs_10_price_cents,
            cgc10PriceCents: wire.cgc_10_price_cents,
            sgc10PriceCents: wire.sgc_10_price_cents,
            priceHistory: wire.price_history,
            pptTCGPlayerId: wire.ppt_tcgplayer_id,
            pptURL: URL(string: wire.ppt_url),
            fetchedAt: wire.fetched_at,
            cacheHit: wire.cache_hit,
            isStaleFallback: wire.is_stale_fallback,
            poketrace: poketrace,
            reconciledHeadlineCents: reconciledCents,
            reconciledSource: reconciledSource
        )
```

You'll also need to update the `Decoded` initializer / synthesized memberwise init signature usage at the call site if Swift's auto-synthesized memberwise init does not accept the new fields — Swift requires explicit positional ordering. Match the order shown above.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ios/slabbist
xcodebuild -workspace slabbist.xcworkspace -scheme slabbist \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:slabbistTests/CompRepositoryTests 2>&1 | tail -40
```

Expected: PASS — all tests including the three new ones pass.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompRepository.swift \
        ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift
git commit -m "feat(ios): CompRepository decodes v2 envelope"
```

---

### Task 14: Update `CompFetchService` to persist 2 snapshots and surface reconciled headline

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift`
- Modify: `ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift`

- [ ] **Step 1: Read the existing service to locate `persistSnapshot`**

```bash
rg -n "persistSnapshot\b" ios/slabbist/slabbist/Features/Comp/CompFetchService.swift
```

- [ ] **Step 2: Add a failing test for the dual-snapshot behavior**

Append to `CompFetchServiceTests.swift` a test that builds a `Decoded` with both `poketrace` set and PPT fields set, runs the service, and asserts two `GradedMarketSnapshot` rows exist in the test `ModelContext` — one with `source == "pokemonpricetracker"` and ladder fields populated, one with `source == "poketrace"` and `ptAvgCents != nil`. Use the in-memory `ModelContainer` pattern already in the file (look at the existing `setUp`).

```swift
    @Test("persists two snapshots — PPT and Poketrace — when both are present")
    func persistsBothSnapshots() async throws {
        let container = try ModelContainer(
            for: GradedMarketSnapshot.self,
            configurations: .init(isStoredInMemoryOnly: true),
        )
        let context = ModelContext(container)
        let service = CompFetchService(context: context)
        let decoded = makeBothSourcesDecoded()
        let scan = makeScan()

        try await service.persist(scan: scan, decoded: decoded)

        let fetched: [GradedMarketSnapshot] = try context.fetch(FetchDescriptor())
        #expect(fetched.count == 2)
        #expect(fetched.contains { $0.source == GradedMarketSnapshot.sourcePPT && $0.psa10PriceCents == 18500 })
        #expect(fetched.contains { $0.source == GradedMarketSnapshot.sourcePoketrace && $0.ptAvgCents == 19500 })
        // Reconciled headline propagates to the scan
        #expect(scan.reconciledHeadlinePriceCents == 19000)
    }
```

(Implement `makeBothSourcesDecoded()` and `makeScan()` helpers near the existing factories in the test file; they should construct one `Decoded` populated as in Task 13's both-sources fixture and a `Scan` for the same identity.)

- [ ] **Step 3: Run the test to verify it fails**

Expected: FAIL — `persist` only writes one row, `Scan.reconciledHeadlinePriceCents` may not exist.

- [ ] **Step 4: Add `reconciledHeadlinePriceCents` to `Scan`**

If `Scan` does not already expose a property for the displayed headline, add one. Locate `Scan.swift`:

```bash
rg -n "class Scan\b|struct Scan\b" ios/slabbist/slabbist/Core/Models/ | head
```

Add to `Scan`:

```swift
    /// Source of truth for the comp-card hero number. Computed server-side
    /// (average of PPT + Poketrace when both succeed; single-source value
    /// otherwise). Mirrored locally so list views render without re-decoding
    /// the snapshots.
    var reconciledHeadlinePriceCents: Int64?
```

- [ ] **Step 5: Update `CompFetchService.persist`**

Replace the body of `persist(scan:decoded:)` (or whichever method writes the `GradedMarketSnapshot`) so it:

1. Fetches and deletes any existing snapshots for this `(identityId, gradingService, grade)` regardless of source.
2. Inserts a PPT snapshot populated from `decoded.psa*PriceCents` etc.
3. Inserts a Poketrace snapshot when `decoded.poketrace != nil`.
4. Sets `scan.reconciledHeadlinePriceCents = decoded.reconciledHeadlineCents`.

Sketch (adapt to the actual existing function shape):

```swift
    func persist(scan: Scan, decoded: CompRepository.Decoded) async throws {
        // Drop existing snapshots for this slab — both sources.
        let identityId = scan.identityId
        let descriptor = FetchDescriptor<GradedMarketSnapshot>(
            predicate: #Predicate { $0.identityId == identityId
                && $0.gradingService == decoded.gradingService
                && $0.grade == decoded.grade }
        )
        let existing = try context.fetch(descriptor)
        for s in existing { context.delete(s) }

        let priceHistoryJSON = encodePriceHistory(decoded.priceHistory)

        let ppt = GradedMarketSnapshot(
            identityId: identityId,
            gradingService: decoded.gradingService,
            grade: decoded.grade,
            source: GradedMarketSnapshot.sourcePPT,
            headlinePriceCents: decoded.headlinePriceCents,
            loosePriceCents:  decoded.loosePriceCents,
            psa7PriceCents:   decoded.psa7PriceCents,
            psa8PriceCents:   decoded.psa8PriceCents,
            psa9PriceCents:   decoded.psa9PriceCents,
            psa9_5PriceCents: decoded.psa9_5PriceCents,
            psa10PriceCents:  decoded.psa10PriceCents,
            bgs10PriceCents:  decoded.bgs10PriceCents,
            cgc10PriceCents:  decoded.cgc10PriceCents,
            sgc10PriceCents:  decoded.sgc10PriceCents,
            pptTCGPlayerId:   decoded.pptTCGPlayerId,
            pptURL:           decoded.pptURL,
            priceHistoryJSON: priceHistoryJSON,
            fetchedAt:        decoded.fetchedAt,
            cacheHit:         decoded.cacheHit,
            isStaleFallback:  decoded.isStaleFallback
        )
        context.insert(ppt)

        if let pt = decoded.poketrace {
            let ptHistoryJSON = encodePriceHistory(pt.priceHistory)
            let snapshot = GradedMarketSnapshot(
                identityId: identityId,
                gradingService: decoded.gradingService,
                grade: decoded.grade,
                source: GradedMarketSnapshot.sourcePoketrace,
                headlinePriceCents: pt.avgCents,
                ptAvgCents:        pt.avgCents,
                ptLowCents:        pt.lowCents,
                ptHighCents:       pt.highCents,
                ptAvg1dCents:      pt.avg1dCents,
                ptAvg7dCents:      pt.avg7dCents,
                ptAvg30dCents:     pt.avg30dCents,
                ptMedian3dCents:   pt.median3dCents,
                ptMedian7dCents:   pt.median7dCents,
                ptMedian30dCents:  pt.median30dCents,
                ptTrend:           pt.trend,
                ptConfidence:      pt.confidence,
                ptSaleCount:       pt.saleCount,
                poketraceCardId:   pt.cardId,
                priceHistoryJSON:  ptHistoryJSON,
                fetchedAt:         pt.fetchedAt,
                cacheHit:          decoded.cacheHit,
                isStaleFallback:   decoded.isStaleFallback
            )
            context.insert(snapshot)
        }

        scan.reconciledHeadlinePriceCents = decoded.reconciledHeadlineCents
        try context.save()
    }

    private func encodePriceHistory(_ points: [PriceHistoryPoint]) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(points)).flatMap { String(data: $0, encoding: .utf8) }
    }
```

(Adjust import names and helper function names to match existing patterns.)

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd ios/slabbist
xcodebuild -workspace slabbist.xcworkspace -scheme slabbist \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:slabbistTests/CompFetchServiceTests 2>&1 | tail -40
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompFetchService.swift \
        ios/slabbist/slabbist/Core/Models/Scan.swift \
        ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift
git commit -m "feat(ios): persist PPT+Poketrace snapshots and reconciled headline"
```

---

### Task 15: Reshape `CompCardView` for side-by-side sources + sparkline toggle

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompCardView.swift`
- Modify (or create): `ios/slabbist/slabbistTests/Features/Comp/CompCardViewSnapshotTests.swift`

- [ ] **Step 1: Add the side-by-side source row + caption to the hero**

Locate the hero section in `CompCardView.swift`. Replace the existing single-headline `Text` with:

```swift
// Hero: the reconciled price.
VStack(alignment: .leading, spacing: 4) {
    if let cents = scan.reconciledHeadlinePriceCents {
        Text(currency(cents))
            .font(.largeTitle.weight(.bold))
            .monospacedDigit()
        Text(captionForReconciled())
            .font(.caption)
            .foregroundStyle(.secondary)
    } else {
        Text("—")
            .font(.largeTitle.weight(.bold))
        Text("no price data")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

Then add a `Sources` row below the hero. Pull the PPT and Poketrace snapshots via SwiftData query, then:

```swift
HStack(alignment: .top, spacing: 16) {
    // PPT cell (left)
    SourcePriceCell(
        title: "PPT",
        priceCents: pptSnapshot?.headlinePriceCents,
        accessoryLine1: nil,
        accessoryLine2: nil,
        confidence: nil
    )
    Divider()
    // Poketrace cell (right)
    SourcePriceCell(
        title: "Poketrace",
        priceCents: poketraceSnapshot?.ptAvgCents,
        accessoryLine1: priceRange(snapshot: poketraceSnapshot),
        accessoryLine2: salesAndTrend(snapshot: poketraceSnapshot),
        confidence: poketraceSnapshot?.ptConfidence
    )
}
.padding(.vertical, 8)
```

Implement the helpers:

```swift
private func captionForReconciled() -> String {
    let pt = poketraceSnapshot?.ptAvgCents
    let ppt = pptSnapshot?.headlinePriceCents
    switch (ppt != nil, pt != nil) {
    case (true, true):  return "avg of 2 sources"
    case (true, false): return "PPT only"
    case (false, true): return "Poketrace only"
    default:            return "no price data"
    }
}

private func priceRange(snapshot: GradedMarketSnapshot?) -> String? {
    guard let s = snapshot, let lo = s.ptLowCents, let hi = s.ptHighCents else { return nil }
    return "(\(currency(lo))–\(currency(hi)))"
}

private func salesAndTrend(snapshot: GradedMarketSnapshot?) -> String? {
    guard let s = snapshot else { return nil }
    var parts: [String] = []
    if let n = s.ptSaleCount { parts.append("n=\(n)") }
    if let trend = s.ptTrend { parts.append(trendChevron(trend)) }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
}

private func trendChevron(_ trend: String) -> String {
    switch trend {
    case "up":     return "▲"
    case "down":   return "▼"
    default:       return "–"
    }
}

private func currency(_ cents: Int64) -> String {
    let dollars = Double(cents) / 100
    return dollars.formatted(.currency(code: "USD"))
}
```

Add the `SourcePriceCell` helper at file scope (or as a private nested view):

```swift
private struct SourcePriceCell: View {
    let title: String
    let priceCents: Int64?
    let accessoryLine1: String?
    let accessoryLine2: String?
    let confidence: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let cents = priceCents {
                Text(currency(cents))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("no data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let l1 = accessoryLine1 {
                Text(l1).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            if let l2 = accessoryLine2 {
                Text(l2).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textColor: Color {
        switch confidence {
        case "high":   return .primary
        case "medium": return .secondary
        case "low":    return .secondary.opacity(0.6)
        default:       return .primary
        }
    }

    private func currency(_ cents: Int64) -> String {
        Double(cents).formatted(.currency(code: "USD").presentation(.standard).rounded(rule: .toNearestOrAwayFromZero, increment: 1))
    }
}
```

(If the existing project has a shared `Money.format` helper, prefer that over redefining.)

- [ ] **Step 2: Add the sparkline source toggle**

Find the existing `CompSparklineView` invocation in `CompCardView`. Wrap with:

```swift
@State private var sparklineSource: SparklineSource = .ppt

enum SparklineSource: String, CaseIterable, Identifiable { case ppt, poketrace; var id: String { rawValue } }

// In body, above the sparkline:
Picker("History source", selection: $sparklineSource) {
    Text("PPT").tag(SparklineSource.ppt)
    Text("Poketrace").tag(SparklineSource.poketrace).disabled(poketraceSnapshot?.priceHistory.isEmpty != false)
}
.pickerStyle(.segmented)

CompSparklineView(points: sparklineSource == .ppt
    ? (pptSnapshot?.priceHistory ?? [])
    : (poketraceSnapshot?.priceHistory ?? []))
```

- [ ] **Step 3: Update or add a snapshot test**

The project uses a snapshot harness in `slabbistTests/Features/Comp/CompCardViewSnapshotTests.swift`. Add fixtures + assertions for three states:
1. Both sources populated.
2. Only PPT (Poketrace cell shows "no data").
3. Only Poketrace (PPT cell shows "no data" — rare but possible).

Follow the harness's existing `assertSnapshot` pattern. Re-record snapshots locally on first run.

- [ ] **Step 4: Run and visually verify in the simulator**

```bash
cd ios/slabbist
xcodebuild -workspace slabbist.xcworkspace -scheme slabbist \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' \
  test -only-testing:slabbistTests/CompCardViewSnapshotTests 2>&1 | tail -40
```

Expected: PASS — snapshot tests match.

Then launch the app in the simulator, navigate to a scan, and visually verify the side-by-side cells render and the sparkline toggle changes the chart.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompCardView.swift \
        ios/slabbist/slabbistTests/Features/Comp/CompCardViewSnapshotTests.swift \
        ios/slabbist/slabbistTests/Features/Comp/__Snapshots__/
git commit -m "feat(ios): side-by-side source cells + sparkline source toggle"
```

---

## Phase 6 — Secrets & deployment

### Task 16: Configure secrets and deploy the Edge Function

**Files:** none.

- [ ] **Step 1: Set the Poketrace API key on the Supabase project**

```bash
supabase secrets set POKETRACE_API_KEY="<key from poketrace dashboard>"
supabase secrets list | grep -i poketrace
# Expected: POKETRACE_API_KEY listed; value masked.
```

`POKETRACE_FRESHNESS_TTL_SECONDS` from the spec is not wired up in v1 —
Poketrace freshness piggy-backs on the existing PPT TTL via the cache-hit
path (Task 10 step 4 reads cached Poketrace alongside cached PPT). When
PPT goes stale, both providers are refetched together. A dedicated
Poketrace TTL knob is a follow-up.

- [ ] **Step 2: Deploy the price-comp Edge Function**

```bash
supabase functions deploy price-comp
# Expected: "Deployed function price-comp" with the new bundle hash.
```

- [ ] **Step 3: Live curl smoke**

```bash
PROJECT_URL="$(supabase status -o env | awk -F'=' '/^API_URL/{print $2}' | tr -d '"')"
ANON_KEY="$(supabase status -o env | awk -F'=' '/^ANON_KEY/{print $2}' | tr -d '"')"

# Use a real graded_card_identity_id from your dev DB.
IDENTITY_ID="<paste an id from select id from graded_card_identities limit 1>"

curl -sS -X POST "${PROJECT_URL}/functions/v1/price-comp" \
  -H "authorization: Bearer ${ANON_KEY}" \
  -H "content-type: application/json" \
  -d "{\"graded_card_identity_id\":\"${IDENTITY_ID}\",\"grading_service\":\"PSA\",\"grade\":\"10\"}" | jq .
```

Expected: a 200 response containing `headline_price_cents`, `poketrace: { ... }` (or `null` if Poketrace had no match), and `reconciled: { headline_price_cents, source }`.

If `poketrace` is unexpectedly `null`, check edge logs:

```bash
supabase functions logs price-comp --tail
```

Look for `poketrace.branch_failed` or `price-comp.poketrace_disabled` lines.

- [ ] **Step 4: Verify the DB rows**

```bash
psql "$SUPABASE_DB_URL" -c "
  select source, headline_price, pt_avg, pt_sale_count
    from public.graded_market
   where identity_id = '${IDENTITY_ID}'::uuid;
"
```

Expected: two rows — `pokemonpricetracker` with `headline_price` set, `poketrace` with `pt_avg` set.

---

## Phase 7 — Manual end-to-end smoke

### Task 17: iOS smoke flow

**Files:** none.

- [ ] **Step 1: Connect iOS dev build to the deployed Edge Function**

Confirm the dev build's `baseURL` points at the deployed Supabase project. (Search `Configuration.swift` or `.xcconfig` if unclear.)

- [ ] **Step 2: Scan a real PSA 10 slab on simulator or device**

In the simulator, scan-or-paste-cert a known PSA 10 card (e.g. a Charizard you already have data for). Wait for the comp card to render.

- [ ] **Step 3: Visually verify**

Confirm:

1. Hero number shows currency, with caption "avg of 2 sources" if both succeed.
2. PPT cell shows the PPT headline price.
3. Poketrace cell shows the Poketrace `avg`, with `($low–$high)` line below and `n=N ▲|▼|–` line below that.
4. Average is correct: `(PPT_headline + Poketrace_avg) / 2`. Calculate manually to verify.
5. Sparkline toggle: tapping "Poketrace" segment swaps the chart to Poketrace's 30d history points.

- [ ] **Step 4: Force the Poketrace branch to fail and verify graceful degradation**

Temporarily corrupt the key:

```bash
supabase secrets set POKETRACE_API_KEY=invalid
supabase functions deploy price-comp
```

In the app, scan a different slab (or invalidate the cache). Verify:

1. PPT cell shows the price as before.
2. Poketrace cell shows "—" and "no data".
3. Hero caption says "PPT only".

Restore the real key:

```bash
supabase secrets set POKETRACE_API_KEY="<real key>"
supabase functions deploy price-comp
```

- [ ] **Step 5: Verify cache hit on second scan**

Re-scan the same slab. Expected: comp card renders fast (<500ms), and edge logs show `cache_state: hit` for the PPT branch and a separate `readMarketLadder` round-trip for the Poketrace branch.

- [ ] **Step 6: Document the smoke result**

Append to the spec doc's `Update history` section a line like:

```
- 2026-05-08 (smoke): both-sources scan succeeded; Charizard PSA 10 reconciled at $X.XX; PPT-only fallback rendered correctly when key revoked.
```

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/specs/2026-05-08-poketrace-comp-design.md
git commit -m "docs: record poketrace integration smoke test results"
```

---

## Done

The integration is complete when:
- `supabase functions deploy price-comp` reports the new bundle is live.
- A real-device scan renders both PPT and Poketrace prices side-by-side.
- The reconciled headline is the average of the two when both succeed.
- The Poketrace branch fails cleanly when the key is revoked (cell shows "no data", PPT renders normally).
- All `__tests__/poketrace-*.test.ts` and `CompRepositoryTests` / `CompFetchServiceTests` / `CompCardViewSnapshotTests` pass.

If any of the above doesn't hold, return to the failing phase and iterate.
