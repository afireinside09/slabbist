# Pokemon Price Tracker Comp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace PriceCharting (landed 2026-05-05) with Pokemon Price Tracker (PPT) as the source of truth for the `/price-comp` Edge Function and the iOS comp card. Same hybrid match-then-cache architecture; new data source, new tier columns (cross-grader: PSA 7/8/9/9.5/10 + BGS 10 + CGC 10 + SGC 10 + Raw), new sparkline panel.

**Architecture:** A single `GET /api/v2/cards?...&includeEbay=true&includeHistory=true` call replaces PriceCharting's two-call (`/api/products` + `/api/product`) flow. The `tcgPlayerId` is cached on the identity row after the first search. Per-tier columns on `graded_market` mirror `ebay.grades.{psa_10|psa_9_5|bgs_10|cgc_10|sgc_10|...}`. A `price_history` JSONB column drives a sparkline view in the comp card.

**Tech Stack:** Deno (Edge Function), SwiftUI + SwiftData (iOS), PostgreSQL via Supabase migrations, Pokemon Price Tracker REST API.

**Spec:** [`docs/superpowers/specs/2026-05-06-pokemonpricetracker-comp-design.md`](../specs/2026-05-06-pokemonpricetracker-comp-design.md)

---

## Prerequisites

- A Pokemon Price Tracker API tier subscription ($9.99/mo) with a valid Bearer token.
- Supabase CLI authenticated against the slabbist project.
- Xcode 16+ with the slabbist workspace cleanly building on `main`.
- Memory note `feedback_supabase_migration_ledger`: when `supabase db push` reports `relation already exists`, INSERT into `supabase_migrations.schema_migrations` rather than re-running DDL. This applies to dropping/adding columns when the upstream ledger is out of sync.

---

## Phase 0 — Live API probe

The PPT public docs are JS-rendered and partially obscured to WebFetch. The spec's field-name claims (`ebay.grades.{key}`, `priceHistory[]` shape, canonical URL field) are best-effort and **must** be reconciled against the live API before any code lands.

### Task 0: Probe live PPT API and capture a baseline fixture

**Files:**
- Create: `supabase/functions/price-comp/__fixtures__/ppt/charizard-base-set.json`
- Modify: `docs/superpowers/specs/2026-05-06-pokemonpricetracker-comp-design.md` — only if field names differ from the spec; bump the **Update history** with an `r3` entry recording the change

- [ ] **Step 1: Verify the API token is loaded into a local env var**

```bash
echo "${POKEMONPRICETRACKER_API_TOKEN:?token not set}" | wc -c
# Expected: a count > 1 (token length + newline). If 0, export the token first:
#   export POKEMONPRICETRACKER_API_TOKEN=<token from PPT dashboard>
```

- [ ] **Step 2: Run a smoke probe against the live API**

```bash
curl -sS -G 'https://www.pokemonpricetracker.com/api/v2/cards' \
  --data-urlencode 'search=charizard base set' \
  --data-urlencode 'limit=1' \
  --data-urlencode 'includeEbay=true' \
  --data-urlencode 'includeHistory=true' \
  --data-urlencode 'days=180' \
  --data-urlencode 'maxDataPoints=30' \
  -H "Authorization: Bearer ${POKEMONPRICETRACKER_API_TOKEN}" \
  -H 'X-API-Version: v1' \
  -o supabase/functions/price-comp/__fixtures__/ppt/charizard-base-set.json \
  -D /tmp/ppt-headers.txt

# Verify the response saved
ls -la supabase/functions/price-comp/__fixtures__/ppt/charizard-base-set.json
cat /tmp/ppt-headers.txt | head -20
```

Expected: HTTP 200, response body saved, headers include `X-API-Calls-Consumed`, `X-RateLimit-Daily-Remaining`. If the auth fails, fix the token before continuing.

- [ ] **Step 3: Reconcile fixture against the spec**

Read the captured JSON. Compare these spec assumptions against the actual response:

| Spec claim | Verify |
|---|---|
| `ebay.grades` is the path | Path may be `ebayData.grades`, `ebay.{tier}.avg`, etc. |
| Keys are snake_case (`psa_10`, `psa_9_5`, `bgs_10`) | May be `psa10`, `PSA10`, `psa-10` |
| Values are dollar floats | May be cents int |
| `prices.market` exists for raw | Path may be `tcgPlayer.market` |
| `priceHistory` is an array of `{date, price}` | Field names may be `ts`/`value`, or it may be `{date: …, prices: {market, psa10}}` |
| Response is array of cards | May be a wrapper object `{ data: [...] }` |
| Canonical URL is on the card | May be derivable only from `tcgPlayerId` |

- [ ] **Step 4: Update the spec only if reality differs**

If any field path differs from the spec, edit `docs/superpowers/specs/2026-05-06-pokemonpricetracker-comp-design.md`:

- Append an entry under **Update history**: `- **2026-05-07 r3** — Reconciled with live API probe. Changed: <list of corrections>.`
- Update the API surface section to use the actual field paths.
- Update the Persistence (live path) section's extract block.
- Update the iOS payload example.

If reality matches the spec, skip the spec edit. Either way, the captured JSON becomes the canonical fixture used by all later parse and integration tests.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/__fixtures__/ppt/charizard-base-set.json
# If the spec was edited:
git add docs/superpowers/specs/2026-05-06-pokemonpricetracker-comp-design.md

git commit -m "$(cat <<'EOF'
edge: capture PPT live-API probe fixture for charizard base set

Baseline response for downstream parser tests. Reconciles spec field
paths against the live API.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

**Block:** All later tasks consume this fixture. Do not proceed until the fixture is captured and the spec is reconciled.

---

## Phase 1 — Database migrations

Migrations are split per-concern so each one can roll back independently.

### Task 1: Drop PriceCharting columns from `graded_card_identities`

**Files:**
- Create: `supabase/migrations/20260507120000_drop_pricecharting_columns_from_identities.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260507120000_drop_pricecharting_columns_from_identities.sql

drop index if exists graded_card_identities_pc_product_idx;

alter table public.graded_card_identities
  drop column if exists pricecharting_product_id,
  drop column if exists pricecharting_url;
```

- [ ] **Step 2: Apply locally**

```bash
supabase db reset --local 2>&1 | tail -30
```

Expected: clean reset; the new migration runs without error.

- [ ] **Step 3: Verify columns are gone**

```bash
supabase db inspect locks 2>&1 | head -5
psql "$(supabase status -o json | jq -r .DB_URL)" -c "\d public.graded_card_identities" | grep -i 'pricecharting'
```

Expected: no rows. If `pricecharting_*` columns still appear, the migration didn't apply — investigate before continuing.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260507120000_drop_pricecharting_columns_from_identities.sql
git commit -m "$(cat <<'EOF'
db: drop pricecharting_* columns from graded_card_identities

PPT replaces PriceCharting; identity rows will get ppt_tcgplayer_id
in the next migration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 2: Add PPT columns to `graded_card_identities`

**Files:**
- Create: `supabase/migrations/20260507120100_add_ppt_columns_to_identities.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260507120100_add_ppt_columns_to_identities.sql

alter table public.graded_card_identities
  add column if not exists ppt_tcgplayer_id text,
  add column if not exists ppt_url          text;

create index if not exists graded_card_identities_ppt_tcgplayer_idx
  on public.graded_card_identities (ppt_tcgplayer_id)
  where ppt_tcgplayer_id is not null;
```

- [ ] **Step 2: Apply locally and verify**

```bash
supabase db reset --local 2>&1 | tail -10
psql "$(supabase status -o json | jq -r .DB_URL)" \
  -c "\d public.graded_card_identities" | grep -E 'ppt_tcgplayer_id|ppt_url'
```

Expected: both new columns present, both `text`, both nullable.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260507120100_add_ppt_columns_to_identities.sql
git commit -m "$(cat <<'EOF'
db: add ppt_tcgplayer_id + ppt_url to graded_card_identities

Cached PPT card identifier persists once after first search match,
keyed by tcgPlayerId. Partial index covers non-null rows.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3: Drop PriceCharting + generic-grade columns from `graded_market`

**Files:**
- Create: `supabase/migrations/20260507120200_drop_pricecharting_columns_from_market.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260507120200_drop_pricecharting_columns_from_market.sql

alter table public.graded_market
  drop column if exists pricecharting_product_id,
  drop column if exists pricecharting_url,
  drop column if exists grade_7_price,
  drop column if exists grade_8_price,
  drop column if exists grade_9_price,
  drop column if exists grade_9_5_price;
```

- [ ] **Step 2: Apply locally and verify**

```bash
supabase db reset --local 2>&1 | tail -10
psql "$(supabase status -o json | jq -r .DB_URL)" \
  -c "\d public.graded_market" | grep -E 'pricecharting|grade_7|grade_8|grade_9'
```

Expected: only the per-grader `*_10_price` columns remain (`psa_10_price`, `bgs_10_price`, `cgc_10_price`, `sgc_10_price`). The generic `grade_*_price` columns and the `pricecharting_*` columns are gone.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260507120200_drop_pricecharting_columns_from_market.sql
git commit -m "$(cat <<'EOF'
db: drop pricecharting + generic grade_* columns from graded_market

PPT publishes per-(grader, grade) prices, so generic grade_7/8/9/9_5
columns are replaced by PSA-specific columns in the next migration.
psa_10/bgs_10/cgc_10/sgc_10/loose_price are kept.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 4: Add PPT columns to `graded_market`

**Files:**
- Create: `supabase/migrations/20260507120300_add_ppt_columns_to_market.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260507120300_add_ppt_columns_to_market.sql

alter table public.graded_market
  add column if not exists ppt_tcgplayer_id text,
  add column if not exists ppt_url          text,
  add column if not exists psa_7_price      numeric(12,2),
  add column if not exists psa_8_price      numeric(12,2),
  add column if not exists psa_9_price      numeric(12,2),
  add column if not exists psa_9_5_price    numeric(12,2),
  add column if not exists price_history    jsonb;

update public.graded_market
   set source = 'pokemonpricetracker'
 where source = 'pricecharting';

alter table public.graded_market
  alter column source set default 'pokemonpricetracker';
```

- [ ] **Step 2: Apply locally and verify**

```bash
supabase db reset --local 2>&1 | tail -10
psql "$(supabase status -o json | jq -r .DB_URL)" \
  -c "\d public.graded_market" | grep -E 'ppt_|psa_7|psa_8|psa_9|psa_9_5|price_history|^ source'
```

Expected: all new columns present; `source` default is `'pokemonpricetracker'`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260507120300_add_ppt_columns_to_market.sql
git commit -m "$(cat <<'EOF'
db: add ppt + per-PSA tier columns + price_history to graded_market

ppt_tcgplayer_id, ppt_url, psa_7/8/9/9_5_price, and a price_history
JSONB blob for the 6-month sparkline. Source default flips from
pricecharting to pokemonpricetracker.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5: Apply migrations to the remote Supabase project

**Files:** none.

- [ ] **Step 1: Inspect remote state**

```bash
supabase db push --dry-run 2>&1 | tail -40
```

Expected: prints the four new migrations as pending. If it errors with `relation already exists`, the local and remote ledgers are out of sync — see ledger-reconciliation note below.

- [ ] **Step 2: Apply**

```bash
supabase db push 2>&1 | tail -40
```

Expected: each migration reports applied.

- [ ] **Step 3: If `relation already exists` errors fire**

For each affected migration `<filename>`, reconcile the ledger:

```bash
psql "$(supabase status -o json | jq -r .REMOTE_DB_URL)" -c \
  "INSERT INTO supabase_migrations.schema_migrations (version, name, statements) \
   VALUES ('<version>', '<name>', ARRAY['-- already applied'])"
```

Then re-run `supabase db push`. Reference: memory note `feedback_supabase_migration_ledger`.

- [ ] **Step 4: Verify remote columns**

```bash
psql "$(supabase status -o json | jq -r .REMOTE_DB_URL)" -c "\d public.graded_market" | grep -E 'ppt_|price_history'
psql "$(supabase status -o json | jq -r .REMOTE_DB_URL)" -c "\d public.graded_card_identities" | grep -E 'ppt_'
```

Expected: all new columns present.

---

## Phase 2 — Edge Function (Deno)

We add the `ppt/` directory alongside `pricecharting/`, rewrite consumers to import from `ppt/`, then delete `pricecharting/` last so we never have a broken intermediate state on disk.

### Task 6: Rewrite `lib/grade-key.ts` for the cross-grader column set

**Files:**
- Modify: `supabase/functions/price-comp/lib/grade-key.ts`
- Test: `supabase/functions/price-comp/__tests__/grade-key.test.ts`

- [ ] **Step 1: Rewrite the failing test first**

Replace the contents of `supabase/functions/price-comp/__tests__/grade-key.test.ts`:

```typescript
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { gradeKeyFor } from "../lib/grade-key.ts";

Deno.test("(PSA, '10') maps to psa_10", () => {
  assertEquals(gradeKeyFor("PSA", "10"), "psa_10");
});

Deno.test("(PSA, '9.5') maps to psa_9_5", () => {
  assertEquals(gradeKeyFor("PSA", "9.5"), "psa_9_5");
});

Deno.test("(PSA, '9') maps to psa_9", () => {
  assertEquals(gradeKeyFor("PSA", "9"), "psa_9");
});

Deno.test("(PSA, '8') maps to psa_8", () => {
  assertEquals(gradeKeyFor("PSA", "8"), "psa_8");
});

Deno.test("(PSA, '7') maps to psa_7", () => {
  assertEquals(gradeKeyFor("PSA", "7"), "psa_7");
});

Deno.test("(BGS, '10') maps to bgs_10", () => {
  assertEquals(gradeKeyFor("BGS", "10"), "bgs_10");
});

Deno.test("(CGC, '10') maps to cgc_10", () => {
  assertEquals(gradeKeyFor("CGC", "10"), "cgc_10");
});

Deno.test("(SGC, '10') maps to sgc_10", () => {
  assertEquals(gradeKeyFor("SGC", "10"), "sgc_10");
});

Deno.test("(TAG, '10') returns null (unsupported in v1)", () => {
  assertEquals(gradeKeyFor("TAG", "10"), null);
});

Deno.test("(BGS, '9.5') returns null in v1 (deferred)", () => {
  assertEquals(gradeKeyFor("BGS", "9.5"), null);
});

Deno.test("(PSA, '6') returns null (sub-PSA-7 unsupported)", () => {
  assertEquals(gradeKeyFor("PSA", "6"), null);
});

Deno.test("PSA verbose grade strings strip down to bare grade", () => {
  assertEquals(gradeKeyFor("PSA", "GEM MT 10"), "psa_10");
  assertEquals(gradeKeyFor("PSA", "MINT 9"), "psa_9");
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd supabase/functions/price-comp && deno test --allow-read --allow-env __tests__/grade-key.test.ts 2>&1 | tail -20
```

Expected: failures (current `gradeKeyFor` returns `grade_7` etc., not `psa_7`).

- [ ] **Step 3: Rewrite the implementation**

Replace `supabase/functions/price-comp/lib/grade-key.ts`:

```typescript
// supabase/functions/price-comp/lib/grade-key.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { GradingService } from "../types.ts";

export type TierKey =
  | "loose"
  | "psa_7"
  | "psa_8"
  | "psa_9"
  | "psa_9_5"
  | "psa_10"
  | "bgs_10"
  | "cgc_10"
  | "sgc_10";

// Strip PSA's verbose adjectives ("GEM MT 10" -> "10") and trim whitespace.
function bareGrade(grade: string): string {
  const m = grade.trim().match(/(\d+(?:\.\d+)?)$/);
  return m ? m[1] : grade.trim();
}

export function gradeKeyFor(service: GradingService, grade: string): TierKey | null {
  const g = bareGrade(grade);
  if (service === "PSA") {
    if (g === "10")  return "psa_10";
    if (g === "9.5") return "psa_9_5";
    if (g === "9")   return "psa_9";
    if (g === "8")   return "psa_8";
    if (g === "7")   return "psa_7";
    return null;
  }
  if (g === "10") {
    if (service === "BGS") return "bgs_10";
    if (service === "CGC") return "cgc_10";
    if (service === "SGC") return "sgc_10";
  }
  return null;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd supabase/functions/price-comp && deno test --allow-read --allow-env __tests__/grade-key.test.ts 2>&1 | tail -20
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/lib/grade-key.ts supabase/functions/price-comp/__tests__/grade-key.test.ts
git commit -m "$(cat <<'EOF'
edge: rewrite gradeKeyFor for the PPT cross-grader tier set

(PSA, 7..10/9.5) → psa_*; (BGS|CGC|SGC, 10) → *_10. TAG, PSA 1–6,
non-PSA half-grades return null and surface as headline-null on the
client.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 7: Add `ppt/parse.ts` (extractLadder, pickTier, parseHistory, productUrl)

**Files:**
- Create: `supabase/functions/price-comp/ppt/parse.ts`
- Test: `supabase/functions/price-comp/__tests__/parse.test.ts` (rewritten)
- Reference: `supabase/functions/price-comp/__fixtures__/ppt/charizard-base-set.json` (live capture from Task 0; Base Set 2 reprint, useful for partial-ladder semantics)

> **API shape lock-in (per spec r3 + Task 0 fixture):**
> - Bare card object lives at `data[0]` of the live response wrapper. The fixtures below store the bare card; the wrapper-unwrap happens in `ppt/cards.ts` (Task 9), not here.
> - Per-tier price path: `card.ebay.salesByGrade.{key}.smartMarketPrice.price` (USD float). Keys are compact: `psa10`, `psa9_5`, `bgs10`, `cgc10`, `sgc10`, `ungraded`.
> - Graded sparkline data: `card.ebay.priceHistory.{gradeKey}` is a **date-keyed dict** (`"YYYY-MM-DD": { average: <float>, count: <int>, … }`), not a flat array. Convert to a chronologically-sorted `[{ts, price_cents}]`.
> - Canonical URL: `card.tcgPlayerUrl` (TCGPlayer page; PPT does not expose a PPT-native product URL). Stored in our `ppt_url` column for spec-name continuity.

- [ ] **Step 1: Add synthetic fixtures matching the v1 ladder shape**

Create `supabase/functions/price-comp/__fixtures__/ppt/full-ladder.json`:

```json
{
  "tcgPlayerId": "243172",
  "name": "Charizard",
  "setName": "Base Set",
  "cardNumber": "4/102",
  "tcgPlayerUrl": "https://www.tcgplayer.com/product/243172",
  "prices": { "market": 4.00 },
  "ebay": {
    "salesByGrade": {
      "ungraded": { "count": 50, "smartMarketPrice": { "price": 4.00, "confidence": "high" } },
      "psa7":     { "count": 20, "smartMarketPrice": { "price": 24.00, "confidence": "medium" } },
      "psa8":     { "count": 15, "smartMarketPrice": { "price": 34.00, "confidence": "medium" } },
      "psa9":     { "count": 10, "smartMarketPrice": { "price": 68.00, "confidence": "medium" } },
      "psa9_5":   { "count": 5,  "smartMarketPrice": { "price": 112.00, "confidence": "low" } },
      "psa10":    { "count": 12, "smartMarketPrice": { "price": 185.00, "confidence": "high" } },
      "bgs10":    { "count": 4,  "smartMarketPrice": { "price": 215.00, "confidence": "low" } },
      "cgc10":    { "count": 6,  "smartMarketPrice": { "price": 168.00, "confidence": "medium" } },
      "sgc10":    { "count": 3,  "smartMarketPrice": { "price": 165.00, "confidence": "low" } }
    },
    "priceHistory": {
      "psa10": {
        "2025-11-08": { "average": 162.00, "count": 1 },
        "2025-11-15": { "average": 168.50, "count": 2 },
        "2025-11-22": { "average": 175.00, "count": 1 },
        "2025-12-01": { "average": 180.00, "count": 1 },
        "2026-05-01": { "average": 185.00, "count": 1 }
      },
      "psa9": {
        "2025-11-08": { "average": 60.00, "count": 1 },
        "2026-05-01": { "average": 68.00, "count": 1 }
      }
    }
  }
}
```

Create `supabase/functions/price-comp/__fixtures__/ppt/partial-ladder.json`:

```json
{
  "tcgPlayerId": "999999",
  "name": "Obscure Card",
  "setName": "Vintage",
  "cardNumber": "999/999",
  "tcgPlayerUrl": "https://www.tcgplayer.com/product/999999",
  "prices": { "market": 5.00 },
  "ebay": {
    "salesByGrade": {
      "ungraded": { "count": 12, "smartMarketPrice": { "price": 5.00, "confidence": "high" } },
      "psa9":     { "count": 3,  "smartMarketPrice": { "price": 42.00, "confidence": "low" } },
      "psa10":    { "count": 2,  "smartMarketPrice": { "price": 180.00, "confidence": "low" } }
    },
    "priceHistory": {
      "psa10": {}
    }
  }
}
```

Create `supabase/functions/price-comp/__fixtures__/ppt/no-prices.json`:

```json
{
  "tcgPlayerId": "111",
  "name": "Untraded Card",
  "setName": "Test",
  "cardNumber": "1/1",
  "tcgPlayerUrl": "https://www.tcgplayer.com/product/111",
  "prices": {},
  "ebay": { "salesByGrade": {}, "priceHistory": {} }
}
```

> **Note:** These are synthetic fixtures (the live Task 0 capture only covers a subset of tiers because Base Set 2 has no recent PSA 10 / BGS 10 / CGC 10 / SGC 10 sales). Their shape mirrors the live response's `data[0]` exactly; if the implementer finds shape drift between this and the captured `charizard-base-set.json`, the live capture wins — fix the synthetic fixtures + parse.ts.

- [ ] **Step 2: Rewrite `__tests__/parse.test.ts`**

Replace the entire contents:

```typescript
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  extractLadder,
  pickTier,
  ladderHasAnyPrice,
  parsePriceHistory,
  priceHistoryForTier,
  productUrl,
} from "../ppt/parse.ts";

const full = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/full-ladder.json", import.meta.url)),
);
const partial = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/partial-ladder.json", import.meta.url)),
);
const empty = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/no-prices.json", import.meta.url)),
);

Deno.test("extractLadder: full ladder, dollars→cents from salesByGrade.{key}.smartMarketPrice.price", () => {
  assertEquals(extractLadder(full), {
    loose:    400,
    psa_7:   2400,
    psa_8:   3400,
    psa_9:   6800,
    psa_9_5:11200,
    psa_10: 18500,
    bgs_10: 21500,
    cgc_10: 16800,
    sgc_10: 16500,
  });
});

Deno.test("extractLadder: partial ladder, missing keys are null", () => {
  const ladder = extractLadder(partial);
  assertEquals(ladder.loose, 500);
  assertEquals(ladder.psa_9, 4200);
  assertEquals(ladder.psa_10, 18000);
  assertEquals(ladder.psa_7, null);
  assertEquals(ladder.psa_8, null);
  assertEquals(ladder.psa_9_5, null);
  assertEquals(ladder.bgs_10, null);
  assertEquals(ladder.cgc_10, null);
  assertEquals(ladder.sgc_10, null);
});

Deno.test("extractLadder: no-prices card → all null", () => {
  const ladder = extractLadder(empty);
  for (const v of Object.values(ladder)) assertEquals(v, null);
});

Deno.test("extractLadder: prices.market preferred over ebay.salesByGrade.ungraded for loose", () => {
  const card = {
    prices: { market: 7.50 },
    ebay: { salesByGrade: { ungraded: { smartMarketPrice: { price: 4.00 } } } },
  };
  assertEquals(extractLadder(card).loose, 750);
});

Deno.test("extractLadder: falls back to ebay.salesByGrade.ungraded.smartMarketPrice when prices.market absent", () => {
  const card = {
    prices: {},
    ebay: { salesByGrade: { ungraded: { smartMarketPrice: { price: 4.00 } } } },
  };
  assertEquals(extractLadder(card).loose, 400);
});

Deno.test("extractLadder: a tier with smartMarketPrice = null is treated as missing", () => {
  const card = {
    ebay: {
      salesByGrade: {
        psa10: { count: 0, smartMarketPrice: { price: null } },
      },
    },
  };
  assertEquals(extractLadder(card).psa_10, null);
});

Deno.test("pickTier: (PSA, '10') picks psa10", () => {
  assertEquals(pickTier(full, "PSA", "10"), 18500);
});

Deno.test("pickTier: (BGS, '10') picks bgs10", () => {
  assertEquals(pickTier(full, "BGS", "10"), 21500);
});

Deno.test("pickTier: (PSA, '9.5') picks psa9_5", () => {
  assertEquals(pickTier(full, "PSA", "9.5"), 11200);
});

Deno.test("pickTier: (TAG, '10') returns null in v1", () => {
  assertEquals(pickTier(full, "TAG", "10"), null);
});

Deno.test("ladderHasAnyPrice: full → true, empty → false", () => {
  assert(ladderHasAnyPrice(extractLadder(full)));
  assert(!ladderHasAnyPrice(extractLadder(empty)));
});

Deno.test("parsePriceHistory: date-keyed dict → chronologically-sorted [{ts, price_cents}]", () => {
  const psa10History = full.ebay.priceHistory.psa10;
  assertEquals(parsePriceHistory(psa10History), [
    { ts: "2025-11-08", price_cents: 16200 },
    { ts: "2025-11-15", price_cents: 16850 },
    { ts: "2025-11-22", price_cents: 17500 },
    { ts: "2025-12-01", price_cents: 18000 },
    { ts: "2026-05-01", price_cents: 18500 },
  ]);
});

Deno.test("parsePriceHistory: empty dict → []", () => {
  assertEquals(parsePriceHistory({}), []);
});

Deno.test("parsePriceHistory: missing input → []", () => {
  assertEquals(parsePriceHistory(undefined), []);
  assertEquals(parsePriceHistory(null), []);
});

Deno.test("parsePriceHistory: array input (wrong shape) → []", () => {
  assertEquals(parsePriceHistory([{ date: "2025-11-08", price: 100 }]), []);
});

Deno.test("parsePriceHistory: malformed entries dropped silently", () => {
  const series = {
    "2025-11-08": { average: 162.00, count: 1 },
    "bad-date":   { average: 100, count: 1 },
    "2025-11-15": { count: 2 },                     // missing average
    "2025-11-22": { average: null, count: 1 },      // null average
    "2025-12-01": { average: "not-a-number" },      // non-numeric
    "2026-05-01": { average: 180.00, count: 1 },
  };
  const out = parsePriceHistory(series);
  assertEquals(out.length, 2);
  assertEquals(out[0].ts, "2025-11-08");
  assertEquals(out[1].ts, "2026-05-01");
});

Deno.test("priceHistoryForTier: (PSA, '10') returns the psa10 series", () => {
  const series = priceHistoryForTier(full, "psa_10");
  assertEquals(typeof series, "object");
  // Spot-check: the series contains the 2026-05-01 daily aggregate.
  assert((series as Record<string, unknown>)["2026-05-01"], "psa10 series includes 2026-05-01");
});

Deno.test("priceHistoryForTier: (BGS, '10') returns null when no bgs10 history exists", () => {
  assertEquals(priceHistoryForTier(full, "bgs_10"), null);
});

Deno.test("priceHistoryForTier: 'loose' returns null", () => {
  assertEquals(priceHistoryForTier(full, "loose"), null);
});

Deno.test("priceHistoryForTier: null tier returns null", () => {
  assertEquals(priceHistoryForTier(full, null), null);
});

Deno.test("productUrl: returns card.tcgPlayerUrl when present", () => {
  assertEquals(productUrl(full), "https://www.tcgplayer.com/product/243172");
});

Deno.test("productUrl: derives a TCGPlayer URL from tcgPlayerId when tcgPlayerUrl is missing", () => {
  const card = { tcgPlayerId: "243172", name: "Charizard" };
  const url = productUrl(card);
  assertEquals(url, "https://www.tcgplayer.com/product/243172");
});
```

- [ ] **Step 3: Run the tests to confirm they fail**

```bash
cd supabase/functions/price-comp && deno test --allow-read --allow-env __tests__/parse.test.ts 2>&1 | tail -20
```

Expected: all fail (ppt/parse.ts doesn't exist yet).

- [ ] **Step 4: Implement `ppt/parse.ts`**

Create `supabase/functions/price-comp/ppt/parse.ts`:

```typescript
// supabase/functions/price-comp/ppt/parse.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { GradingService } from "../types.ts";
import { gradeKeyFor, type TierKey } from "../lib/grade-key.ts";

export interface PPTSmartMarketPrice {
  price?: number | null;
  confidence?: string;
}

export interface PPTSalesByGradeEntry {
  count?: number;
  averagePrice?: number;
  smartMarketPrice?: PPTSmartMarketPrice;
}

export interface PPTEbay {
  salesByGrade?: Record<string, PPTSalesByGradeEntry | undefined>;
  // priceHistory is keyed by gradeKey ("psa10", "bgs10", "ungraded", …);
  // each value is a date-keyed dict of daily aggregates.
  priceHistory?: Record<string, Record<string, { average?: number; count?: number } | undefined> | undefined>;
}

export interface PPTCard {
  tcgPlayerId?: string;
  name?: string;
  setName?: string;
  cardNumber?: string;
  tcgPlayerUrl?: string;
  prices?: { market?: number };
  ebay?: PPTEbay;
}

export interface LadderPrices {
  loose:    number | null;
  psa_7:    number | null;
  psa_8:    number | null;
  psa_9:    number | null;
  psa_9_5:  number | null;
  psa_10:   number | null;
  bgs_10:   number | null;
  cgc_10:   number | null;
  sgc_10:   number | null;
}

export interface PriceHistoryPoint {
  ts: string;
  price_cents: number;
}

// Maps our internal TierKey → PPT's compact key in `salesByGrade` /
// `priceHistory`. PPT uses `psa10` not `psa_10`, `ungraded` not `raw`.
const TIER_TO_PPT_KEY: Record<Exclude<keyof LadderPrices, "loose">, string> = {
  psa_7:   "psa7",
  psa_8:   "psa8",
  psa_9:   "psa9",
  psa_9_5: "psa9_5",
  psa_10:  "psa10",
  bgs_10:  "bgs10",
  cgc_10:  "cgc10",
  sgc_10:  "sgc10",
};

function dollarsToCents(v: number | null | undefined): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v !== "number" || !Number.isFinite(v) || v <= 0) return null;
  return Math.round(v * 100);
}

function smartMarketCents(entry: PPTSalesByGradeEntry | undefined): number | null {
  if (!entry) return null;
  return dollarsToCents(entry.smartMarketPrice?.price);
}

export function extractLadder(card: PPTCard): LadderPrices {
  const sbg = card.ebay?.salesByGrade ?? {};
  const looseFromMarket   = dollarsToCents(card.prices?.market);
  const looseFromUngraded = smartMarketCents(sbg["ungraded"]);
  const out: LadderPrices = {
    loose:   looseFromMarket ?? looseFromUngraded,
    psa_7:   null, psa_8: null, psa_9: null, psa_9_5: null, psa_10: null,
    bgs_10:  null, cgc_10: null, sgc_10: null,
  };
  for (const [tier, key] of Object.entries(TIER_TO_PPT_KEY) as Array<[keyof LadderPrices, string]>) {
    out[tier] = smartMarketCents(sbg[key]);
  }
  return out;
}

export function pickTier(card: PPTCard, service: GradingService, grade: string): number | null {
  const key = gradeKeyFor(service, grade);
  if (!key) return null;
  const ladder = extractLadder(card);
  return ladder[key as keyof LadderPrices] ?? null;
}

export function ladderHasAnyPrice(ladder: LadderPrices): boolean {
  return Object.values(ladder).some((v) => v !== null);
}

/**
 * Converts a PPT `ebay.priceHistory.{gradeKey}` date-keyed dict
 * (e.g. `{ "2026-05-05": { average: 1190.0, count: 1 }, … }`) into a
 * chronologically-sorted array of `{ts, price_cents}`. Tolerates missing
 * keys, malformed entries, and wrong shapes by returning `[]`.
 */
export function parsePriceHistory(raw: unknown): PriceHistoryPoint[] {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
  const out: PriceHistoryPoint[] = [];
  for (const [date, agg] of Object.entries(raw as Record<string, unknown>)) {
    if (!date) continue;
    const parsedDate = Date.parse(date);
    if (Number.isNaN(parsedDate)) continue;
    if (!agg || typeof agg !== "object") continue;
    const avg = (agg as { average?: unknown }).average;
    if (avg === null || avg === undefined) continue;
    const num = typeof avg === "number" ? avg : Number(avg);
    if (!Number.isFinite(num) || num <= 0) continue;
    out.push({ ts: date, price_cents: Math.round(num * 100) });
  }
  out.sort((a, b) => a.ts.localeCompare(b.ts));
  return out;
}

/**
 * Returns the raw `ebay.priceHistory.{gradeKey}` dict for the given
 * internal TierKey, or `null` if no series exists for that tier (or if
 * the tier is `loose` / `null`). Caller passes the result to
 * `parsePriceHistory()` to convert into the wire shape.
 */
export function priceHistoryForTier(card: PPTCard, tierKey: TierKey | null): unknown {
  if (!tierKey || tierKey === "loose") return null;
  const pptKey = TIER_TO_PPT_KEY[tierKey as Exclude<keyof LadderPrices, "loose">];
  if (!pptKey) return null;
  const series = card.ebay?.priceHistory?.[pptKey];
  return series ?? null;
}

/**
 * Canonical product page URL for the card. Currently the TCGPlayer URL —
 * PPT does not expose a PPT-native product page URL on the card object.
 * The `ppt_url` column name is kept for spec-name continuity even though
 * the URL points off-domain.
 */
export function productUrl(card: PPTCard): string {
  if (typeof card.tcgPlayerUrl === "string" && card.tcgPlayerUrl) return card.tcgPlayerUrl;
  if (card.tcgPlayerId) {
    return `https://www.tcgplayer.com/product/${encodeURIComponent(card.tcgPlayerId)}`;
  }
  return "https://www.tcgplayer.com";
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd supabase/functions/price-comp && deno test --allow-read --allow-env __tests__/parse.test.ts 2>&1 | tail -20
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/price-comp/ppt/parse.ts \
        supabase/functions/price-comp/__tests__/parse.test.ts \
        supabase/functions/price-comp/__fixtures__/ppt/full-ladder.json \
        supabase/functions/price-comp/__fixtures__/ppt/partial-ladder.json \
        supabase/functions/price-comp/__fixtures__/ppt/no-prices.json
git commit -m "$(cat <<'EOF'
edge: add ppt/parse.ts with ladder + history extractors

extractLadder maps ebay.salesByGrade.{key}.smartMarketPrice.price to
LadderPrices in cents. parsePriceHistory turns a PPT date-keyed history
dict into a chronologically-sorted [{ts, price_cents}] array.
priceHistoryForTier picks the right per-grade series. loose price
prefers prices.market then falls back to salesByGrade.ungraded.
productUrl returns tcgPlayerUrl (no PPT-native product URL exists).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 8: Add `ppt/client.ts` with Bearer auth + retry-once + rate-limit pause

**Files:**
- Create: `supabase/functions/price-comp/ppt/client.ts`
- Test: `supabase/functions/price-comp/__tests__/client.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/price-comp/__tests__/client.test.ts`:

```typescript
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { get, _resetPause } from "../ppt/client.ts";

function startServer(handler: (req: Request) => Response | Promise<Response>): { url: string; close: () => Promise<void> } {
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, handler);
  const url = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  return { url, async close() { ac.abort(); try { await server.finished; } catch {} } };
}

Deno.test("get: sends Authorization Bearer and X-API-Version headers", async () => {
  let captured: { authorization: string | null; apiVersion: string | null } = { authorization: null, apiVersion: null };
  const srv = startServer((req) => {
    captured.authorization = req.headers.get("authorization");
    captured.apiVersion = req.headers.get("x-api-version");
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPause();
    const r = await get({ token: "abc-123", baseUrl: srv.url, now: () => Date.now() }, "/api/v2/cards", { search: "x" });
    assertEquals(r.status, 200);
    assertEquals(captured.authorization, "Bearer abc-123");
    assertEquals(captured.apiVersion, "v1");
  } finally {
    await srv.close();
  }
});

Deno.test("get: 401 triggers a single retry", async () => {
  let calls = 0;
  const srv = startServer(() => {
    calls++;
    if (calls === 1) return new Response("nope", { status: 401 });
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPause();
    const r = await get({ token: "t", baseUrl: srv.url, now: () => Date.now() }, "/api/v2/cards", { search: "x" });
    assertEquals(r.status, 200);
    assertEquals(calls, 2);
  } finally {
    await srv.close();
  }
});

Deno.test("get: 401 twice returns 401 to caller", async () => {
  const srv = startServer(() => new Response("still nope", { status: 401 }));
  try {
    _resetPause();
    const r = await get({ token: "t", baseUrl: srv.url, now: () => Date.now() }, "/api/v2/cards", { search: "x" });
    assertEquals(r.status, 401);
  } finally {
    await srv.close();
  }
});

Deno.test("get: 429 sets a 60s in-isolate pause; subsequent calls return paused 429 without hitting the network", async () => {
  let calls = 0;
  const srv = startServer(() => { calls++; return new Response("rate-limited", { status: 429 }); });
  try {
    _resetPause();
    let now = 1_000_000;
    const r1 = await get({ token: "t", baseUrl: srv.url, now: () => now }, "/api/v2/cards", { search: "x" });
    assertEquals(r1.status, 429);
    assertEquals(calls, 1);
    // Within the 60s pause, no network call.
    now += 30_000;
    const r2 = await get({ token: "t", baseUrl: srv.url, now: () => now }, "/api/v2/cards", { search: "x" });
    assertEquals(r2.status, 429);
    assert(r2.paused === true);
    assertEquals(calls, 1);
    // After the pause, fresh call.
    now += 31_000;
    const r3 = await get({ token: "t", baseUrl: srv.url, now: () => now }, "/api/v2/cards", { search: "x" });
    assertEquals(r3.status, 429);
    assertEquals(calls, 2);
  } finally {
    await srv.close();
  }
});
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read --allow-env __tests__/client.test.ts 2>&1 | tail -20
```

Expected: fail (ppt/client.ts does not exist).

- [ ] **Step 3: Implement `ppt/client.ts`**

```typescript
// supabase/functions/price-comp/ppt/client.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.

const BASE_URL = "https://www.pokemonpricetracker.com";

let pausedUntil = 0;

export interface ClientOptions {
  token: string;
  baseUrl?: string;
  now?: () => number;
}

export interface ClientResponse {
  status: number;
  body: unknown;
  paused?: boolean;
  creditsConsumed?: number;
}

export function _resetPause(): void { pausedUntil = 0; }

function urlFor(opts: ClientOptions, path: string, params: Record<string, string>): string {
  const url = new URL(path, opts.baseUrl ?? BASE_URL);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  return url.toString();
}

async function doFetch(url: string, token: string): Promise<ClientResponse> {
  const res = await fetch(url, {
    method: "GET",
    headers: {
      authorization: `Bearer ${token}`,
      "x-api-version": "v1",
      accept: "application/json",
    },
  });
  let body: unknown = null;
  try { body = await res.json(); } catch { body = null; }
  const consumedRaw = res.headers.get("x-api-calls-consumed");
  const credits = consumedRaw ? Number(consumedRaw) : undefined;
  return { status: res.status, body, creditsConsumed: Number.isFinite(credits) ? credits : undefined };
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
  const first = await doFetch(url, opts.token);
  if (first.status === 429) {
    pausedUntil = now + 60_000;
    return first;
  }
  if (first.status === 401) {
    return await doFetch(url, opts.token);
  }
  return first;
}
```

- [ ] **Step 4: Run tests to verify**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read --allow-env __tests__/client.test.ts 2>&1 | tail -20
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/ppt/client.ts supabase/functions/price-comp/__tests__/client.test.ts
git commit -m "$(cat <<'EOF'
edge: add ppt/client.ts with Bearer auth, 401-retry, 429 pause

Sends Authorization: Bearer + X-API-Version: v1 headers, retries once
on 401 (transient token-refresh), and pauses all in-isolate fetches
for 60s after a 429. Test seam _resetPause() lets unit tests start
clean.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 9: Add `ppt/cards.ts` (single-call wrapper)

**Files:**
- Create: `supabase/functions/price-comp/ppt/cards.ts`
- Test: `supabase/functions/price-comp/__tests__/cards.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/price-comp/__tests__/cards.test.ts`:

```typescript
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fetchCard, _resetPauseForTests } from "../ppt/cards.ts";

function startServer(handler: (req: Request) => Response | Promise<Response>): { url: string; close: () => Promise<void> } {
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, handler);
  const url = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  return { url, async close() { ac.abort(); try { await server.finished; } catch {} } };
}

const fullLadder = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/full-ladder.json", import.meta.url)),
);

Deno.test("fetchCard: by tcgPlayerId, returns first card from response", async () => {
  let receivedQuery: URLSearchParams | null = null;
  const srv = startServer((req) => {
    const u = new URL(req.url);
    receivedQuery = u.searchParams;
    return new Response(JSON.stringify([fullLadder]), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { tcgPlayerId: "243172" });
    assertEquals(r.status, 200);
    assert(r.card?.tcgPlayerId === "243172");
    assertEquals(receivedQuery?.get("tcgPlayerId"), "243172");
    assertEquals(receivedQuery?.get("includeEbay"), "true");
    assertEquals(receivedQuery?.get("includeHistory"), "true");
    assertEquals(receivedQuery?.get("days"), "180");
    assertEquals(receivedQuery?.get("maxDataPoints"), "30");
  } finally {
    await srv.close();
  }
});

Deno.test("fetchCard: by search, sends search + limit=1", async () => {
  let receivedQuery: URLSearchParams | null = null;
  const srv = startServer((req) => {
    receivedQuery = new URL(req.url).searchParams;
    return new Response(JSON.stringify([fullLadder]), { status: 200, headers: { "content-type": "application/json" } });
  });
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "Charizard Base Set" });
    assertEquals(r.status, 200);
    assertEquals(receivedQuery?.get("search"), "Charizard Base Set");
    assertEquals(receivedQuery?.get("limit"), "1");
  } finally {
    await srv.close();
  }
});

Deno.test("fetchCard: empty array → status 200, card = null", async () => {
  const srv = startServer(() => new Response(JSON.stringify([]), { status: 200 }));
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { search: "nope" });
    assertEquals(r.status, 200);
    assertEquals(r.card, null);
  } finally {
    await srv.close();
  }
});

Deno.test("fetchCard: response wrapper { data: [card] } also supported", async () => {
  const srv = startServer(() => new Response(JSON.stringify({ data: [fullLadder] }), { status: 200 }));
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { tcgPlayerId: "243172" });
    assertEquals(r.status, 200);
    assert(r.card?.tcgPlayerId === "243172");
  } finally {
    await srv.close();
  }
});

Deno.test("fetchCard: 5xx propagates, card = null", async () => {
  const srv = startServer(() => new Response("down", { status: 503 }));
  try {
    _resetPauseForTests();
    const r = await fetchCard({ token: "t", baseUrl: srv.url, now: () => Date.now() }, { tcgPlayerId: "243172" });
    assertEquals(r.status, 503);
    assertEquals(r.card, null);
  } finally {
    await srv.close();
  }
});
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read --allow-env __tests__/cards.test.ts 2>&1 | tail -20
```

Expected: fail (cards.ts does not exist).

- [ ] **Step 3: Implement `ppt/cards.ts`**

```typescript
// supabase/functions/price-comp/ppt/cards.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { get, type ClientOptions, _resetPause } from "./client.ts";
import type { PPTCard } from "./parse.ts";

export interface FetchCardArgs {
  search?: string;
  tcgPlayerId?: string;
}

export interface FetchCardResult {
  status: number;
  card: PPTCard | null;
  creditsConsumed?: number;
}

export function _resetPauseForTests(): void { _resetPause(); }

export async function fetchCard(opts: ClientOptions, args: FetchCardArgs): Promise<FetchCardResult> {
  const params: Record<string, string> = {
    includeEbay: "true",
    includeHistory: "true",
    days: "180",
    maxDataPoints: "30",
  };
  if (args.tcgPlayerId) {
    params.tcgPlayerId = args.tcgPlayerId;
  } else if (args.search) {
    params.search = args.search;
    params.limit = "1";
  } else {
    return { status: 400, card: null };
  }
  const res = await get(opts, "/api/v2/cards", params);
  if (res.status !== 200) return { status: res.status, card: null, creditsConsumed: res.creditsConsumed };
  const body = res.body;
  let arr: unknown;
  if (Array.isArray(body)) arr = body;
  else if (body && typeof body === "object" && Array.isArray((body as { data?: unknown }).data)) arr = (body as { data: unknown[] }).data;
  else arr = [];
  const list = arr as unknown[];
  const card = (list.length > 0 ? list[0] : null) as PPTCard | null;
  return { status: 200, card, creditsConsumed: res.creditsConsumed };
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read --allow-env __tests__/cards.test.ts 2>&1 | tail -20
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/ppt/cards.ts supabase/functions/price-comp/__tests__/cards.test.ts
git commit -m "$(cat <<'EOF'
edge: add ppt/cards.ts single-call wrapper

GET /api/v2/cards with includeEbay+includeHistory; supports both
?tcgPlayerId= (warm path) and ?search=<q>&limit=1 (cold path). Tolerates
both bare-array and { data: [] } response shapes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 10: Rewrite `types.ts` for the PPT contract

**Files:**
- Modify: `supabase/functions/price-comp/types.ts`

- [ ] **Step 1: Replace the file**

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
  ppt_tcgplayer_id: string | null;
  ppt_url: string | null;
}

export interface PriceCompRequest {
  graded_card_identity_id: string;
  grading_service: GradingService;
  grade: string;
}

export interface PriceHistoryWirePoint {
  ts: string;
  price_cents: number;
}

export interface PriceCompResponse {
  headline_price_cents: number | null;
  grading_service: GradingService;
  grade: string;

  loose_price_cents:    number | null;
  psa_7_price_cents:    number | null;
  psa_8_price_cents:    number | null;
  psa_9_price_cents:    number | null;
  psa_9_5_price_cents:  number | null;
  psa_10_price_cents:   number | null;
  bgs_10_price_cents:   number | null;
  cgc_10_price_cents:   number | null;
  sgc_10_price_cents:   number | null;

  price_history: PriceHistoryWirePoint[];

  ppt_tcgplayer_id: string;
  ppt_url: string;

  fetched_at: string;
  cache_hit: boolean;
  is_stale_fallback: boolean;
}

export type CacheState = "hit" | "miss" | "stale";
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/price-comp/types.ts
git commit -m "$(cat <<'EOF'
edge: rewrite types.ts for PPT request/response contract

GradedCardIdentity drops pricecharting_*, gains ppt_*. Response shape
gets per-PSA tier columns + price_history array. Removes generic
grade_*_price_cents fields; psa_10/bgs_10/cgc_10/sgc_10 keep their
existing field names.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 11: Rewrite `persistence/market.ts` for the new column set

**Files:**
- Modify: `supabase/functions/price-comp/persistence/market.ts`

- [ ] **Step 1: Replace the file**

```typescript
// supabase/functions/price-comp/persistence/market.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService } from "../types.ts";
import type { LadderPrices, PriceHistoryPoint } from "../ppt/parse.ts";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  priceHistory: PriceHistoryPoint[];
  pptTCGPlayerId: string;
  pptUrl: string;
}

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
      source: "pokemonpricetracker",
      ppt_tcgplayer_id: input.pptTCGPlayerId,
      ppt_url: input.pptUrl,
      headline_price: centsToDecimal(input.headlinePriceCents),
      loose_price:    centsToDecimal(input.ladderCents.loose),
      psa_7_price:    centsToDecimal(input.ladderCents.psa_7),
      psa_8_price:    centsToDecimal(input.ladderCents.psa_8),
      psa_9_price:    centsToDecimal(input.ladderCents.psa_9),
      psa_9_5_price:  centsToDecimal(input.ladderCents.psa_9_5),
      psa_10_price:   centsToDecimal(input.ladderCents.psa_10),
      bgs_10_price:   centsToDecimal(input.ladderCents.bgs_10),
      cgc_10_price:   centsToDecimal(input.ladderCents.cgc_10),
      sgc_10_price:   centsToDecimal(input.ladderCents.sgc_10),
      price_history:  input.priceHistory,
      updated_at: new Date().toISOString(),
    }, { onConflict: "identity_id,grading_service,grade" });
  if (error) throw new Error(`graded_market upsert: ${error.message}`);
}

export interface MarketReadResult {
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  priceHistory: PriceHistoryPoint[];
  pptTCGPlayerId: string | null;
  pptUrl: string | null;
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
      "headline_price, loose_price, " +
      "psa_7_price, psa_8_price, psa_9_price, psa_9_5_price, psa_10_price, " +
      "bgs_10_price, cgc_10_price, sgc_10_price, " +
      "price_history, ppt_tcgplayer_id, ppt_url, updated_at",
    )
    .eq("identity_id", identityId)
    .eq("grading_service", gradingService)
    .eq("grade", grade)
    .maybeSingle();
  if (!data) return null;
  const history = Array.isArray(data.price_history)
    ? (data.price_history as Array<{ ts?: unknown; price_cents?: unknown }>)
        .filter((p) => typeof p.ts === "string" && typeof p.price_cents === "number")
        .map((p) => ({ ts: p.ts as string, price_cents: p.price_cents as number }))
    : [];
  return {
    headlinePriceCents: decimalToCents(data.headline_price),
    ladderCents: {
      loose:    decimalToCents(data.loose_price),
      psa_7:    decimalToCents(data.psa_7_price),
      psa_8:    decimalToCents(data.psa_8_price),
      psa_9:    decimalToCents(data.psa_9_price),
      psa_9_5:  decimalToCents(data.psa_9_5_price),
      psa_10:   decimalToCents(data.psa_10_price),
      bgs_10:   decimalToCents(data.bgs_10_price),
      cgc_10:   decimalToCents(data.cgc_10_price),
      sgc_10:   decimalToCents(data.sgc_10_price),
    },
    priceHistory: history,
    pptTCGPlayerId: data.ppt_tcgplayer_id ?? null,
    pptUrl: data.ppt_url ?? null,
    updatedAt: data.updated_at ?? null,
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/price-comp/persistence/market.ts
git commit -m "$(cat <<'EOF'
edge: rewrite market.ts to read/write the PPT column set

Reads ppt_*, psa_7/8/9/9_5_price, price_history JSONB. Writes the
same set on upsert. cents↔dollars conversion at the boundary
unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 12: Rewrite `persistence/identity-product-id.ts` (rename functions to `ppt*`)

**Files:**
- Modify: `supabase/functions/price-comp/persistence/identity-product-id.ts`

- [ ] **Step 1: Replace the file**

```typescript
// supabase/functions/price-comp/persistence/identity-product-id.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { SupabaseClient } from "@supabase/supabase-js";

export async function persistIdentityPPTId(
  supabase: SupabaseClient,
  identityId: string,
  tcgPlayerId: string,
  pptUrl: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({ ppt_tcgplayer_id: tcgPlayerId, ppt_url: pptUrl })
    .eq("id", identityId);
  if (error) throw new Error(`graded_card_identities update: ${error.message}`);
}

// Used to clear a stale id when the cached card is deleted upstream
// (PPT 404 / empty array). Next scan re-runs search.
export async function clearIdentityPPTId(
  supabase: SupabaseClient,
  identityId: string,
): Promise<void> {
  const { error } = await supabase
    .from("graded_card_identities")
    .update({ ppt_tcgplayer_id: null, ppt_url: null })
    .eq("id", identityId);
  if (error) throw new Error(`graded_card_identities clear: ${error.message}`);
}
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/price-comp/persistence/identity-product-id.ts
git commit -m "$(cat <<'EOF'
edge: rename identity-id helpers to persistIdentityPPTId / clearIdentityPPTId

File path stays. Functions now write ppt_tcgplayer_id + ppt_url
columns instead of the dropped pricecharting_* columns.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 13: Rewrite `index.ts` orchestrator

**Files:**
- Modify: `supabase/functions/price-comp/index.ts`

> **Match-quality note from Task 0 r3:** PPT's fuzzy search with `limit=1` can return the wrong printing for cards with many reprints (the probe searched "charizard base set" and got *Base Set 2*, not the original). The plan keeps `limit=1` for v1 simplicity but the implementer should add a defensive heuristic: if the returned card's `setName` is empty/missing OR the returned card looks like a pattern-mismatch on number, log `ppt.match.set_mismatch` (don't reject the result — a "force-rematch" UX is reserved). This makes drift visible in logs.

- [ ] **Step 1: Replace the file**

```typescript
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
// supabase/functions/price-comp/index.ts
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PriceCompRequest, PriceCompResponse, CacheState } from "./types.ts";
import { extractLadder, pickTier, productUrl, ladderHasAnyPrice, parsePriceHistory, priceHistoryForTier, type LadderPrices, type PriceHistoryPoint } from "./ppt/parse.ts";
import { gradeKeyFor } from "./lib/grade-key.ts";
import { fetchCard } from "./ppt/cards.ts";
import { upsertMarketLadder, readMarketLadder } from "./persistence/market.ts";
import { persistIdentityPPTId, clearIdentityPPTId } from "./persistence/identity-product-id.ts";
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

function buildSearchQuery(identity: {
  card_name: string;
  card_number: string | null;
  set_name: string;
  year: number | null;
}): string {
  const parts: string[] = [identity.card_name];
  if (identity.card_number) parts.push(identity.card_number);
  parts.push(identity.set_name);
  if (identity.year !== null) parts.push(String(identity.year));
  return parts.join(" ");
}

function buildResponse(args: {
  ladderCents: LadderPrices;
  headlineCents: number | null;
  service: GradingService;
  grade: string;
  priceHistory: PriceHistoryPoint[];
  tcgPlayerId: string;
  pptUrl: string;
  cacheHit: boolean;
  isStaleFallback: boolean;
}): PriceCompResponse {
  return {
    headline_price_cents: args.headlineCents,
    grading_service: args.service,
    grade: args.grade,
    loose_price_cents:    args.ladderCents.loose,
    psa_7_price_cents:    args.ladderCents.psa_7,
    psa_8_price_cents:    args.ladderCents.psa_8,
    psa_9_price_cents:    args.ladderCents.psa_9,
    psa_9_5_price_cents:  args.ladderCents.psa_9_5,
    psa_10_price_cents:   args.ladderCents.psa_10,
    bgs_10_price_cents:   args.ladderCents.bgs_10,
    cgc_10_price_cents:   args.ladderCents.cgc_10,
    sgc_10_price_cents:   args.ladderCents.sgc_10,
    price_history: args.priceHistory,
    ppt_tcgplayer_id: args.tcgPlayerId,
    ppt_url: args.pptUrl,
    fetched_at: new Date().toISOString(),
    cache_hit: args.cacheHit,
    is_stale_fallback: args.isStaleFallback,
  };
}

export interface HandleDeps {
  supabase: SupabaseClient | unknown;
  pptBaseUrl: string;
  pptToken: string;
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
      ladderCents: cached.ladderCents,
      headlineCents: cached.headlinePriceCents,
      service: body.grading_service,
      grade: body.grade,
      priceHistory: cached.priceHistory,
      tcgPlayerId: cached.pptTCGPlayerId ?? identity.ppt_tcgplayer_id ?? "",
      pptUrl: cached.pptUrl ?? identity.ppt_url ?? "",
      cacheHit: true,
      isStaleFallback: false,
    }));
  }

  // 3. Live fetch — single call
  const clientOpts = { token: deps.pptToken, baseUrl: deps.pptBaseUrl, now: deps.now };
  const tcgPlayerId = identity.ppt_tcgplayer_id as string | null;
  const fetchArgs = tcgPlayerId
    ? { tcgPlayerId }
    : { search: buildSearchQuery(identity) };
  const result = await fetchCard(clientOpts, fetchArgs);

  if (result.status === 401 || result.status === 403) {
    console.error("ppt.auth_invalid", { phase: tcgPlayerId ? "tcgPlayerId" : "search" });
    return json(502, { code: "AUTH_INVALID" });
  }
  if (result.status === 429 || result.status >= 500) {
    return await staleOrUpstreamDown(cached, body, `${result.status}`);
  }
  if (!result.card) {
    if (tcgPlayerId) {
      // Cached id refers to a deleted card. Clear it so the next scan re-runs search.
      try { await clearIdentityPPTId(supabase, body.graded_card_identity_id); } catch { /* swallow */ }
      return json(404, { code: "NO_MARKET_DATA" });
    }
    console.log("ppt.match.zero_hits", { search: (fetchArgs as { search: string }).search });
    return json(404, { code: "PRODUCT_NOT_RESOLVED" });
  }

  const card = result.card;
  const ladder = extractLadder(card);
  // Sparkline tracks the requested tier's history (e.g., the PSA 10 series
  // when the user scanned a PSA 10). Falls back to PSA 10 history when the
  // requested grader is unsupported (TAG, sub-PSA-7) so the card still
  // shows a meaningful trend line. Empty / missing → empty array.
  const requestedTierKey = gradeKeyFor(body.grading_service, body.grade);
  const historyTierKey = requestedTierKey ?? "psa_10";
  const history = parsePriceHistory(priceHistoryForTier(card, historyTierKey));
  if (!ladderHasAnyPrice(ladder)) {
    console.log("ppt.product.no_prices", { tcgPlayerId: card.tcgPlayerId });
    return json(404, { code: "NO_MARKET_DATA" });
  }
  const headlineCents = pickTier(card, body.grading_service, body.grade);
  const resolvedTCGPlayerId = String(card.tcgPlayerId ?? tcgPlayerId ?? "");
  const url = identity.ppt_url ?? productUrl(card);

  // First-time match — persist tcgPlayerId on identity
  if (!tcgPlayerId && resolvedTCGPlayerId) {
    try {
      await persistIdentityPPTId(supabase, body.graded_card_identity_id, resolvedTCGPlayerId, url);
      console.log("ppt.match.first_resolved", { identity_id: body.graded_card_identity_id, tcgPlayerId: resolvedTCGPlayerId });
    } catch (e) {
      console.error("ppt.persist.identity_failed", { message: (e as Error).message });
    }
  }

  try {
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
  } catch (e) {
    console.error("ppt.persist.market_failed", { message: (e as Error).message });
  }

  console.log("price-comp.live", {
    identity_id: body.graded_card_identity_id,
    tcgPlayerId: resolvedTCGPlayerId,
    cache_state: state,
    matched: tcgPlayerId ? "cached_id" : "searched",
    headline_present: headlineCents !== null,
    history_points: history.length,
    credits_consumed: result.creditsConsumed ?? null,
  });

  return json(200, buildResponse({
    ladderCents: ladder,
    headlineCents,
    service: body.grading_service,
    grade: body.grade,
    priceHistory: history,
    tcgPlayerId: resolvedTCGPlayerId,
    pptUrl: url,
    cacheHit: false,
    isStaleFallback: false,
  }));
}

async function staleOrUpstreamDown(
  cached: Awaited<ReturnType<typeof readMarketLadder>>,
  body: PriceCompRequest,
  marker: string,
): Promise<Response> {
  console.error("ppt.upstream_5xx", { marker });
  if (!cached) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  return json(200, buildResponse({
    ladderCents: cached.ladderCents,
    headlineCents: cached.headlinePriceCents,
    service: body.grading_service,
    grade: body.grade,
    priceHistory: cached.priceHistory,
    tcgPlayerId: cached.pptTCGPlayerId ?? "",
    pptUrl: cached.pptUrl ?? "",
    cacheHit: true,
    isStaleFallback: true,
  }));
}

Deno.serve(async (req) => {
  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  return await handle(req, {
    supabase,
    pptBaseUrl: "https://www.pokemonpricetracker.com",
    pptToken: env("POKEMONPRICETRACKER_API_TOKEN"),
    ttlSeconds: Number(env("POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS", "86400")),
    now: () => Date.now(),
  });
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/price-comp/index.ts
git commit -m "$(cat <<'EOF'
edge: rewrite /price-comp orchestrator on PPT single-call API

Single GET /api/v2/cards replaces PriceCharting's two-call flow.
?tcgPlayerId= on warm path, ?search=&limit=1 on cold path. Persists
ppt_tcgplayer_id on identity after first match. Stale-fallback,
auth-invalid, zero-hit, deleted-card, and rate-limit branches preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 14: Rewrite the orchestrator integration test

**Files:**
- Modify: `supabase/functions/price-comp/__tests__/index.test.ts`

- [ ] **Step 1: Replace the file**

```typescript
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handle } from "../index.ts";
import { _resetPauseForTests } from "../ppt/cards.ts";

interface MockState {
  responses: Map<string, { status: number; body: unknown }>;
  defaultBody: unknown;
  calls: { url: string; query: URLSearchParams }[];
}

function startMock(state: MockState): { url: string; close: () => Promise<void> } {
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, (req) => {
    const u = new URL(req.url);
    state.calls.push({ url: u.pathname, query: u.searchParams });
    const key = u.searchParams.get("tcgPlayerId") ?? u.searchParams.get("search") ?? "__default__";
    const r = state.responses.get(key) ?? state.responses.get("__default__");
    if (!r) return new Response(JSON.stringify(state.defaultBody ?? []), { status: 200, headers: { "content-type": "application/json" } });
    return new Response(JSON.stringify(r.body), { status: r.status, headers: { "content-type": "application/json" } });
  });
  const url = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  return { url, async close() { ac.abort(); try { await server.finished; } catch {} } };
}

const fullLadder = JSON.parse(
  await Deno.readTextFile(new URL("../__fixtures__/ppt/full-ladder.json", import.meta.url)),
);

interface FakeIdentity {
  id: string;
  card_name: string;
  card_number: string | null;
  set_name: string;
  year: number | null;
  ppt_tcgplayer_id: string | null;
  ppt_url: string | null;
}

interface FakeMarketRow {
  identity_id: string;
  grading_service: string;
  grade: string;
  source: string;
  ppt_tcgplayer_id: string | null;
  ppt_url: string | null;
  headline_price: number | null;
  loose_price: number | null;
  psa_7_price: number | null;
  psa_8_price: number | null;
  psa_9_price: number | null;
  psa_9_5_price: number | null;
  psa_10_price: number | null;
  bgs_10_price: number | null;
  cgc_10_price: number | null;
  sgc_10_price: number | null;
  price_history: unknown;
  updated_at: string;
}

function fakeSupabase(state: { identity: FakeIdentity; market: FakeMarketRow | null }) {
  return {
    from(table: string) {
      if (table === "graded_card_identities") {
        return {
          select() { return this; },
          eq(_c: string, _v: string) { return this; },
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
          eq(_c: string, _v: string) { return this; },
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

Deno.test("cache miss + no cached id — search, persist, return ladder", async () => {
  _resetPauseForTests();
  const state: MockState = {
    responses: new Map([["__default__", { status: 200, body: [fullLadder] }]]),
    defaultBody: [fullLadder],
    calls: [],
  };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Charizard",
        card_number: "4/102",
        set_name: "Base Set",
        year: 1999,
        ppt_tcgplayer_id: null,
        ppt_url: null,
      },
      market: null,
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ graded_card_identity_id: "id-1", grading_service: "PSA", grade: "10" }),
    });
    const res = await handle(req, {
      supabase: fake,
      pptBaseUrl: mock.url,
      pptToken: "test-token",
      ttlSeconds: 86400,
      now: () => Date.now(),
    });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.headline_price_cents, 18500);
    assertEquals(body.psa_10_price_cents, 18500);
    assertEquals(body.bgs_10_price_cents, 21500);
    assertEquals(body.ppt_tcgplayer_id, "243172");
    assertEquals(body.cache_hit, false);
    assert(body.price_history.length > 0);
    assertEquals(state.calls.length, 1, "single PPT call");
    assertEquals(state.calls[0].query.get("search"), "Charizard 4/102 Base Set 1999");
  } finally {
    await mock.close();
  }
});

Deno.test("cache hit — within TTL skips PPT entirely", async () => {
  _resetPauseForTests();
  const state: MockState = { responses: new Map(), defaultBody: [], calls: [] };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Charizard",
        card_number: "4/102",
        set_name: "Base Set",
        year: 1999,
        ppt_tcgplayer_id: "243172",
        ppt_url: "https://www.pokemonpricetracker.com/card/charizard-base-set",
      },
      market: {
        identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
        source: "pokemonpricetracker",
        ppt_tcgplayer_id: "243172",
        ppt_url: "https://www.pokemonpricetracker.com/card/charizard-base-set",
        headline_price: 185.0,
        loose_price: 4.0,
        psa_7_price: 24.0,
        psa_8_price: 34.0,
        psa_9_price: 68.0,
        psa_9_5_price: 112.0,
        psa_10_price: 185.0,
        bgs_10_price: 215.0,
        cgc_10_price: 168.0,
        sgc_10_price: 165.0,
        price_history: [{ ts: "2026-05-01", price_cents: 18500 }],
        updated_at: new Date().toISOString(),
      },
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ graded_card_identity_id: "id-1", grading_service: "PSA", grade: "10" }),
    });
    const res = await handle(req, {
      supabase: fake,
      pptBaseUrl: mock.url,
      pptToken: "test-token",
      ttlSeconds: 86400,
      now: () => Date.now(),
    });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.cache_hit, true);
    assertEquals(body.headline_price_cents, 18500);
    assertEquals(state.calls.length, 0);
  } finally {
    await mock.close();
  }
});

Deno.test("warm path — uses ?tcgPlayerId, not search", async () => {
  _resetPauseForTests();
  const state: MockState = {
    responses: new Map([["243172", { status: 200, body: [fullLadder] }]]),
    defaultBody: [],
    calls: [],
  };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Charizard",
        card_number: "4/102",
        set_name: "Base Set",
        year: 1999,
        ppt_tcgplayer_id: "243172",
        ppt_url: "https://www.pokemonpricetracker.com/card/charizard-base-set",
      },
      // Stale market row to force a live fetch.
      market: {
        identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
        source: "pokemonpricetracker",
        ppt_tcgplayer_id: "243172",
        ppt_url: "https://www.pokemonpricetracker.com/card/charizard-base-set",
        headline_price: 180.0,
        loose_price: 4.0,
        psa_7_price: null, psa_8_price: null, psa_9_price: null, psa_9_5_price: null,
        psa_10_price: 180.0, bgs_10_price: null, cgc_10_price: null, sgc_10_price: null,
        price_history: [],
        updated_at: new Date(Date.now() - 2 * 86400_000).toISOString(),
      },
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ graded_card_identity_id: "id-1", grading_service: "PSA", grade: "10" }),
    });
    const res = await handle(req, {
      supabase: fake,
      pptBaseUrl: mock.url,
      pptToken: "t",
      ttlSeconds: 86400,
      now: () => Date.now(),
    });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(state.calls.length, 1);
    assertEquals(state.calls[0].query.get("tcgPlayerId"), "243172");
    assertEquals(state.calls[0].query.get("search"), null);
    assertEquals(body.headline_price_cents, 18500);
  } finally {
    await mock.close();
  }
});

Deno.test("zero search hits — 404 PRODUCT_NOT_RESOLVED, no persistence", async () => {
  _resetPauseForTests();
  const state: MockState = { responses: new Map([["__default__", { status: 200, body: [] }]]), defaultBody: [], calls: [] };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Unknown",
        card_number: "0/0",
        set_name: "Nothing",
        year: null,
        ppt_tcgplayer_id: null,
        ppt_url: null,
      },
      market: null,
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ graded_card_identity_id: "id-1", grading_service: "PSA", grade: "10" }),
    });
    const res = await handle(req, { supabase: fake, pptBaseUrl: mock.url, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
    const body = await res.json();
    assertEquals(res.status, 404);
    assertEquals(body.code, "PRODUCT_NOT_RESOLVED");
  } finally {
    await mock.close();
  }
});

Deno.test("upstream 5xx with cached row — returns is_stale_fallback", async () => {
  _resetPauseForTests();
  const state: MockState = { responses: new Map([["__default__", { status: 503, body: { error: "down" } }]]), defaultBody: {}, calls: [] };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-1",
        card_name: "Charizard",
        card_number: "4/102",
        set_name: "Base Set",
        year: 1999,
        ppt_tcgplayer_id: "243172",
        ppt_url: "https://www.pokemonpricetracker.com/card/charizard-base-set",
      },
      market: {
        identity_id: "id-1",
        grading_service: "PSA",
        grade: "10",
        source: "pokemonpricetracker",
        ppt_tcgplayer_id: "243172",
        ppt_url: "https://www.pokemonpricetracker.com/card/charizard-base-set",
        headline_price: 180.0,
        loose_price: 4.0,
        psa_7_price: null, psa_8_price: null, psa_9_price: null, psa_9_5_price: null,
        psa_10_price: 180.0, bgs_10_price: null, cgc_10_price: null, sgc_10_price: null,
        price_history: [],
        updated_at: new Date(Date.now() - 2 * 86400_000).toISOString(),
      },
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ graded_card_identity_id: "id-1", grading_service: "PSA", grade: "10" }),
    });
    const res = await handle(req, { supabase: fake, pptBaseUrl: mock.url, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
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
  _resetPauseForTests();
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
    body: JSON.stringify({ graded_card_identity_id: "missing", grading_service: "PSA", grade: "10" }),
  });
  const res = await handle(req, { supabase: fake, pptBaseUrl: "http://localhost:0", pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
  const body = await res.json();
  assertEquals(res.status, 404);
  assertEquals(body.code, "IDENTITY_NOT_FOUND");
});

Deno.test("cached id + 404 from PPT — clears the cached id, returns NO_MARKET_DATA", async () => {
  _resetPauseForTests();
  // Empty array = "no card with that id"
  const state: MockState = { responses: new Map([["243172", { status: 200, body: [] }]]), defaultBody: [], calls: [] };
  const mock = startMock(state);
  try {
    const identity = {
      id: "id-1",
      card_name: "Charizard",
      card_number: "4/102",
      set_name: "Base Set",
      year: 1999,
      ppt_tcgplayer_id: "243172",
      ppt_url: "https://www.pokemonpricetracker.com/card/charizard-base-set",
    };
    const fake = fakeSupabase({ identity, market: null });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ graded_card_identity_id: "id-1", grading_service: "PSA", grade: "10" }),
    });
    const res = await handle(req, { supabase: fake, pptBaseUrl: mock.url, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
    const body = await res.json();
    assertEquals(res.status, 404);
    assertEquals(body.code, "NO_MARKET_DATA");
    assertEquals(identity.ppt_tcgplayer_id, null);
    assertEquals(identity.ppt_url, null);
  } finally {
    await mock.close();
  }
});
```

- [ ] **Step 2: Run all Edge Function tests**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read --allow-env 2>&1 | tail -30
```

Expected: every test passes. If `index.test.ts` references the old PriceCharting fixtures or paths, they're now removed — fix any straggling references.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/__tests__/index.test.ts
git commit -m "$(cat <<'EOF'
edge: rewrite /price-comp orchestrator integration tests for PPT

Mock PPT server replaces the two-endpoint PriceCharting mock. Covers
cold-path search, warm-path tcgPlayerId, cache hit, stale fallback,
zero hits, deleted-card id-clear, identity-not-found.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 15: Delete the orphaned PriceCharting code

**Files:**
- Delete: `supabase/functions/price-comp/pricecharting/` (entire directory)
- Delete: `supabase/functions/price-comp/__fixtures__/pricecharting/` (entire directory)

- [ ] **Step 1: Verify no remaining imports**

```bash
grep -rn "pricecharting/" supabase/functions/price-comp --include="*.ts" 2>&1 | grep -v __fixtures__
```

Expected: empty output. If anything still imports from `pricecharting/`, fix it before deleting.

- [ ] **Step 2: Delete the directories**

```bash
rm -rf supabase/functions/price-comp/pricecharting/
rm -rf supabase/functions/price-comp/__fixtures__/pricecharting/
```

- [ ] **Step 3: Re-run all Edge Function tests**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read --allow-env 2>&1 | tail -30
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add -A supabase/functions/price-comp/
git commit -m "$(cat <<'EOF'
edge: delete orphaned pricecharting/ source + fixtures

PPT replaces this code path; nothing imports from pricecharting/ or
the corresponding fixtures anymore. All Edge Function tests stay
green after the deletion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — iOS

### Task 16: Add `PriceHistoryPoint` value type

**Files:**
- Create: `ios/slabbist/slabbist/Core/Models/PriceHistoryPoint.swift`
- Test: `ios/slabbist/slabbistTests/Core/Models/PriceHistoryPointTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/slabbist/slabbistTests/Core/Models/PriceHistoryPointTests.swift`:

```swift
import Testing
import Foundation
@testable import slabbist

@Suite("PriceHistoryPoint")
struct PriceHistoryPointTests {
    @Test("decodes a wire array of {ts, price_cents} into ordered points")
    func decodesWireArray() throws {
        let json = #"""
        [
          { "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 },
          { "ts": "2025-11-15T00:00:00Z", "price_cents": 16850 }
        ]
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let points = try decoder.decode([PriceHistoryPoint].self, from: json)
        #expect(points.count == 2)
        #expect(points[0].priceCents == 16200)
        #expect(points[1].priceCents == 16850)
    }

    @Test("encodes back to the wire shape")
    func encodesToWireShape() throws {
        let p = PriceHistoryPoint(ts: Date(timeIntervalSince1970: 1_700_000_000), priceCents: 12345)
        let data = try JSONEncoder().encode(p)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"price_cents\":12345"))
    }
}
```

- [ ] **Step 2: Run the test (expect failure: type missing)**

Build the test target in Xcode or run from CLI:

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:slabbistTests/PriceHistoryPointTests 2>&1 | tail -30
```

Expected: compilation failure ("Cannot find 'PriceHistoryPoint' in scope").

- [ ] **Step 3: Implement the type**

Create `ios/slabbist/slabbist/Core/Models/PriceHistoryPoint.swift`:

```swift
import Foundation

struct PriceHistoryPoint: Codable, Equatable, Hashable {
    let ts: Date
    let priceCents: Int64

    enum CodingKeys: String, CodingKey {
        case ts
        case priceCents = "price_cents"
    }
}
```

- [ ] **Step 4: Run the test**

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:slabbistTests/PriceHistoryPointTests 2>&1 | tail -20
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/PriceHistoryPoint.swift \
        ios/slabbist/slabbistTests/Core/Models/PriceHistoryPointTests.swift
git commit -m "$(cat <<'EOF'
ios: add PriceHistoryPoint value type for sparkline data

Codable, decodes the {ts, price_cents} wire shape, used by the
sparkline view in CompCardView and persisted as JSON-string on
GradedMarketSnapshot.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 17: Reshape `GradedMarketSnapshot`

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift`

- [ ] **Step 1: Replace the file**

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

    /// JSON-encoded `[PriceHistoryPoint]`. Decoded on demand for the
    /// sparkline view; SwiftData prefers a single primitive blob over
    /// a Codable property of a value-array type, which can fail lightweight
    /// migration.
    var priceHistoryJSON: String?

    var fetchedAt: Date
    var cacheHit: Bool
    var isStaleFallback: Bool

    init(
        identityId: UUID,
        gradingService: String,
        grade: String,
        headlinePriceCents: Int64?,
        loosePriceCents: Int64?,
        psa7PriceCents: Int64?,
        psa8PriceCents: Int64?,
        psa9PriceCents: Int64?,
        psa9_5PriceCents: Int64?,
        psa10PriceCents: Int64?,
        bgs10PriceCents: Int64?,
        cgc10PriceCents: Int64?,
        sgc10PriceCents: Int64?,
        pptTCGPlayerId: String?,
        pptURL: URL?,
        priceHistoryJSON: String?,
        fetchedAt: Date,
        cacheHit: Bool,
        isStaleFallback: Bool
    ) {
        self.identityId = identityId
        self.gradingService = gradingService
        self.grade = grade
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
        self.priceHistoryJSON = priceHistoryJSON
        self.fetchedAt = fetchedAt
        self.cacheHit = cacheHit
        self.isStaleFallback = isStaleFallback
    }

    /// Decoded view of `priceHistoryJSON`. Returns `[]` when missing or
    /// malformed — the caller renders an empty sparkline.
    var priceHistory: [PriceHistoryPoint] {
        guard let json = priceHistoryJSON, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PriceHistoryPoint].self, from: data)) ?? []
    }
}
```

- [ ] **Step 2: Build to surface compile errors in callers**

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build 2>&1 | grep -E '^/.+: error:' | head -20
```

Expected: errors in `CompCardView.swift`, `LotDetailView.swift`, `CompFetchService.swift` referencing the dropped `grade7/8/9/9_5PriceCents`, `pricechartingProductId`, `pricechartingURL` properties. These get fixed in subsequent tasks.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift
git commit -m "$(cat <<'EOF'
ios: reshape GradedMarketSnapshot for the PPT cross-grader ladder

Drops grade7/8/9/9_5PriceCents and the pricecharting_* fields. Adds
psa7/8/9/9_5PriceCents, pptTCGPlayerId, pptURL, priceHistoryJSON
(JSON-encoded [PriceHistoryPoint] for sparkline rendering). Existing
psa10/bgs10/cgc10/sgc10/loose price fields keep their names.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 18: Reshape `CompRepository.Wire` / `Decoded`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompRepository.swift`

- [ ] **Step 1: Replace the file**

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
        let psa_7_price_cents: Int64?
        let psa_8_price_cents: Int64?
        let psa_9_price_cents: Int64?
        let psa_9_5_price_cents: Int64?
        let psa_10_price_cents: Int64?
        let bgs_10_price_cents: Int64?
        let cgc_10_price_cents: Int64?
        let sgc_10_price_cents: Int64?
        let price_history: [PriceHistoryPoint]
        let ppt_tcgplayer_id: String
        let ppt_url: String
        let fetched_at: Date
        let cache_hit: Bool
        let is_stale_fallback: Bool
    }

    struct Decoded {
        let headlinePriceCents: Int64?
        let gradingService: String
        let grade: String
        let loosePriceCents: Int64?
        let psa7PriceCents: Int64?
        let psa8PriceCents: Int64?
        let psa9PriceCents: Int64?
        let psa9_5PriceCents: Int64?
        let psa10PriceCents: Int64?
        let bgs10PriceCents: Int64?
        let cgc10PriceCents: Int64?
        let sgc10PriceCents: Int64?
        let priceHistory: [PriceHistoryPoint]
        let pptTCGPlayerId: String
        let pptURL: URL?
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

- [ ] **Step 2: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompRepository.swift
git commit -m "$(cat <<'EOF'
ios: reshape CompRepository Wire/Decoded for PPT payload

Drops generic grade_*_price_cents wire fields, adds psa_7/8/9/9_5,
ppt_tcgplayer_id, ppt_url, price_history. Error mapping unchanged in
shape.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 19: Reshape `CompFetchService.persistSnapshot` + `classify`

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift`

- [ ] **Step 1: Replace `persistSnapshot` and `classify`**

Open `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift`. Replace the body of `persistSnapshot` (around lines 159–187) with:

```swift
    private static func persistSnapshot(
        decoded: CompRepository.Decoded,
        identityId: UUID,
        service: String,
        grade: String,
        context: ModelContext
    ) {
        let historyJSON: String? = {
            guard !decoded.priceHistory.isEmpty else { return nil }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(decoded.priceHistory) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        let snapshot = GradedMarketSnapshot(
            identityId: identityId,
            gradingService: service,
            grade: grade,
            headlinePriceCents: decoded.headlinePriceCents,
            loosePriceCents: decoded.loosePriceCents,
            psa7PriceCents: decoded.psa7PriceCents,
            psa8PriceCents: decoded.psa8PriceCents,
            psa9PriceCents: decoded.psa9PriceCents,
            psa9_5PriceCents: decoded.psa9_5PriceCents,
            psa10PriceCents: decoded.psa10PriceCents,
            bgs10PriceCents: decoded.bgs10PriceCents,
            cgc10PriceCents: decoded.cgc10PriceCents,
            sgc10PriceCents: decoded.sgc10PriceCents,
            pptTCGPlayerId: decoded.pptTCGPlayerId,
            pptURL: decoded.pptURL,
            priceHistoryJSON: historyJSON,
            fetchedAt: decoded.fetchedAt,
            cacheHit: decoded.cacheHit,
            isStaleFallback: decoded.isStaleFallback
        )
        context.insert(snapshot)
    }
```

Replace the body of `classify` (around lines 198–219) with:

```swift
    nonisolated static func classify(_ error: Error) -> (state: CompFetchState, message: String) {
        if let typed = error as? CompRepository.Error {
            switch typed {
            case .noMarketData:
                return (.noData, "Pokemon Price Tracker has no comp for this slab yet.")
            case .productNotResolved:
                return (.noData, "We couldn't find this card on Pokemon Price Tracker.")
            case .upstreamUnavailable:
                return (.failed, "Pokemon Price Tracker lookup unavailable — try again.")
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

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build 2>&1 | grep -E '^/.+: error:' | head -20
```

Expected: any remaining errors are now in `CompCardView.swift`, `LotDetailView.swift`, and the test files — all addressed in later tasks. `CompFetchService.swift` compiles cleanly.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompFetchService.swift
git commit -m "$(cat <<'EOF'
ios: rewrite CompFetchService persistSnapshot+classify for PPT ladder

persistSnapshot writes the new tier columns + JSON-encoded history.
classify swaps PriceCharting copy for Pokemon Price Tracker. In-flight
de-dup, flipMatching, and the state-machine flips are unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 20: Add `CompSparklineView`

**Files:**
- Create: `ios/slabbist/slabbist/Features/Comp/CompSparklineView.swift`

- [ ] **Step 1: Implement the view**

```swift
import SwiftUI

/// Minimal Path-based sparkline. Hides itself when there are fewer than
/// 2 points (a single point can't draw a line).
struct CompSparklineView: View {
    let points: [PriceHistoryPoint]

    var body: some View {
        GeometryReader { geo in
            if points.count >= 2 {
                let path = sparklinePath(points: points, in: geo.size)
                path.stroke(AppColor.gold, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 32)
    }

    private func sparklinePath(points: [PriceHistoryPoint], in size: CGSize) -> Path {
        guard let minPrice = points.map(\.priceCents).min(),
              let maxPrice = points.map(\.priceCents).max(),
              minPrice < maxPrice,
              let firstTs = points.first?.ts,
              let lastTs = points.last?.ts else {
            return Path()
        }
        let xRange = lastTs.timeIntervalSince(firstTs)
        let yRange = Double(maxPrice - minPrice)
        var path = Path()
        for (index, point) in points.enumerated() {
            let xNorm: CGFloat
            if xRange > 0 {
                xNorm = CGFloat(point.ts.timeIntervalSince(firstTs) / xRange)
            } else {
                xNorm = CGFloat(index) / CGFloat(max(points.count - 1, 1))
            }
            let yNorm = 1.0 - CGFloat(Double(point.priceCents - minPrice) / yRange)
            let x = xNorm * size.width
            let y = yNorm * size.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else          { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
```

- [ ] **Step 2: Add a SwiftUI preview**

Append to the same file:

```swift
#Preview("Sparkline — 6 month series") {
    let calendar = Calendar(identifier: .gregorian)
    let points: [PriceHistoryPoint] = (0..<24).map { i in
        let date = calendar.date(byAdding: .day, value: i * 7, to: Date(timeIntervalSinceNow: -180 * 86_400))!
        let cents = Int64(15_000 + (i * 200) + Int(sin(Double(i) / 3) * 800))
        return PriceHistoryPoint(ts: date, priceCents: cents)
    }
    return CompSparklineView(points: points)
        .padding()
        .background(Color.black)
}

#Preview("Sparkline — empty") {
    CompSparklineView(points: [])
        .padding()
        .background(Color.black)
}
```

- [ ] **Step 3: Build + verify the preview renders in Xcode**

Open the file in Xcode, ensure both previews render without errors. The first should show a curved line; the second should be empty (the view collapses to no path).

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompSparklineView.swift
git commit -m "$(cat <<'EOF'
ios: add CompSparklineView path-based mini-chart

Renders [PriceHistoryPoint] as a 32pt-tall stroked path in AppColor.gold.
Time-axis aware — uses real timestamps for x-position so unevenly-spaced
data points (PPT decimates ~30 points across 180 days) render correctly.
Hides when fewer than 2 points are present.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 21: Reshape `CompCardView` for the PPT ladder + sparkline

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompCardView.swift`

- [ ] **Step 1: Replace the file**

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
                if !sparklinePoints.isEmpty {
                    SlabCardDivider()
                    CompSparklineView(points: sparklinePoints)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if !ladderTiers.isEmpty {
                    SlabCardDivider()
                    ladderRail
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.md)
                }
                if let caveat = caveatMessage {
                    SlabCardDivider()
                    caveatRow(caveat)
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
                Text("\(snapshot.gradingService) \(snapshot.grade)")
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

    // MARK: - Sparkline

    private var sparklinePoints: [PriceHistoryPoint] {
        snapshot.priceHistory.sorted { $0.ts < $1.ts }
    }

    // MARK: - Grade ladder

    private struct Tier: Identifiable {
        let id: String
        let label: String
        let cents: Int64
        let isHeadline: Bool
    }

    /// Ordered tiers in the ladder rail. The cell matching the snapshot's
    /// (gradingService, grade) gets a gold border.
    private var ladderTiers: [Tier] {
        let entries: [(id: String, label: String, cents: Int64?, headlineKey: (service: String, grade: String)?)] = [
            ("loose",    "Raw",     snapshot.loosePriceCents,     nil),
            ("psa_7",    "PSA 7",   snapshot.psa7PriceCents,      ("PSA", "7")),
            ("psa_8",    "PSA 8",   snapshot.psa8PriceCents,      ("PSA", "8")),
            ("psa_9",    "PSA 9",   snapshot.psa9PriceCents,      ("PSA", "9")),
            ("psa_9_5",  "PSA 9.5", snapshot.psa9_5PriceCents,    ("PSA", "9.5")),
            ("psa_10",   "PSA 10",  snapshot.psa10PriceCents,     ("PSA", "10")),
            ("bgs_10",   "BGS 10",  snapshot.bgs10PriceCents,     ("BGS", "10")),
            ("cgc_10",   "CGC 10",  snapshot.cgc10PriceCents,     ("CGC", "10")),
            ("sgc_10",   "SGC 10",  snapshot.sgc10PriceCents,     ("SGC", "10")),
        ]
        return entries.compactMap { e in
            guard let cents = e.cents else { return nil }
            let isHeadline = e.headlineKey.map {
                $0.service == snapshot.gradingService && $0.grade == snapshot.grade
            } ?? false
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

    // MARK: - Caveat

    /// One of three states: stale fallback, headline tier missing for a
    /// supported (grader, grade), or unsupported (grader, grade) entirely.
    private var caveatMessage: String? {
        if snapshot.isStaleFallback {
            return "Cached — Pokemon Price Tracker unavailable"
        }
        if snapshot.headlinePriceCents == nil {
            // Distinguish "supported but no value" (PSA 10 with no sales)
            // from "unsupported (TAG / sub-PSA-7)".
            if isSupportedTier(service: snapshot.gradingService, grade: snapshot.grade) {
                return "Pokemon Price Tracker has no \(snapshot.gradingService) \(snapshot.grade) sales for this card yet — showing the rest of the ladder."
            } else {
                return "Pokemon Price Tracker hasn't logged \(snapshot.gradingService) \(snapshot.grade) sales — showing the rest of the ladder."
            }
        }
        return nil
    }

    private func isSupportedTier(service: String, grade: String) -> Bool {
        switch (service, grade) {
        case ("PSA", "10"), ("PSA", "9.5"), ("PSA", "9"), ("PSA", "8"), ("PSA", "7"):
            return true
        case ("BGS", "10"), ("CGC", "10"), ("SGC", "10"):
            return true
        default:
            return false
        }
    }

    private func caveatRow(_ message: String) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: snapshot.isStaleFallback ? "wifi.slash" : "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(snapshot.isStaleFallback ? AppColor.negative : AppColor.dim)
            Text(message)
                .font(SlabFont.sans(size: 12, weight: .medium))
                .foregroundStyle(snapshot.isStaleFallback ? AppColor.negative : AppColor.dim)
            Spacer()
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerRow: some View {
        if let url = snapshot.pptURL {
            Link(destination: url) {
                HStack(spacing: Spacing.xxs) {
                    Text("Powered by Pokemon Price Tracker · View card")
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

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build 2>&1 | grep -E '^/.+: error:' | head -10
```

Expected: only `LotDetailView.swift` and the test files still error. Those land in later tasks.

- [ ] **Step 3: Open the file's preview in Xcode and visually confirm**

Add a quick preview at the bottom of `CompCardView.swift`:

```swift
#Preview("Full ladder · PSA 10") {
    let history = (0..<10).map { i in
        PriceHistoryPoint(ts: Date(timeIntervalSinceNow: TimeInterval(-i * 86_400 * 18)), priceCents: Int64(18_500 - i * 200))
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = String(data: (try? encoder.encode(history)) ?? Data(), encoding: .utf8)
    let snap = GradedMarketSnapshot(
        identityId: UUID(), gradingService: "PSA", grade: "10",
        headlinePriceCents: 18500, loosePriceCents: 400,
        psa7PriceCents: 2400, psa8PriceCents: 3400, psa9PriceCents: 6800, psa9_5PriceCents: 11200, psa10PriceCents: 18500,
        bgs10PriceCents: 21500, cgc10PriceCents: 16800, sgc10PriceCents: 16500,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: json,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(snapshot: snap).padding().background(Color.black)
}

#Preview("BGS 10 headline") {
    let snap = GradedMarketSnapshot(
        identityId: UUID(), gradingService: "BGS", grade: "10",
        headlinePriceCents: 21500, loosePriceCents: 400,
        psa7PriceCents: nil, psa8PriceCents: nil, psa9PriceCents: nil, psa9_5PriceCents: nil, psa10PriceCents: 18500,
        bgs10PriceCents: 21500, cgc10PriceCents: 16800, sgc10PriceCents: nil,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: nil,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(snapshot: snap).padding().background(Color.black)
}

#Preview("Unsupported tier · TAG 10") {
    let snap = GradedMarketSnapshot(
        identityId: UUID(), gradingService: "TAG", grade: "10",
        headlinePriceCents: nil, loosePriceCents: 400,
        psa7PriceCents: nil, psa8PriceCents: nil, psa9PriceCents: nil, psa9_5PriceCents: nil, psa10PriceCents: 18500,
        bgs10PriceCents: nil, cgc10PriceCents: nil, sgc10PriceCents: nil,
        pptTCGPlayerId: "243172",
        pptURL: URL(string: "https://www.pokemonpricetracker.com/card/charizard-base-set"),
        priceHistoryJSON: nil,
        fetchedAt: Date(), cacheHit: false, isStaleFallback: false
    )
    return CompCardView(snapshot: snap).padding().background(Color.black)
}
```

Open each preview, confirm the gold-border lands on the correct cell, the caveat row renders for the TAG 10 case, and the sparkline draws for the first preview.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompCardView.swift
git commit -m "$(cat <<'EOF'
ios: rewrite CompCardView for PPT cross-grader ladder + sparkline

Hero / sparkline / ladder rail / caveat / footer in that order.
Ladder cells: Raw + PSA 7/8/9/9.5/10 + BGS 10 + CGC 10 + SGC 10. Gold
border on the requested (grader, grade) tier. Caveat row distinguishes
stale-fallback, supported-but-empty, and unsupported-grade cases.
Footer attributes Pokemon Price Tracker and deep-links to pptURL.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 22: Patch `LotDetailView` for the model rename

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Lots/LotDetailView.swift`

`LotDetailView` only references `headlinePriceCents`, which kept its name. The build should already be clean for that file. Check anyway.

- [ ] **Step 1: Verify the file compiles**

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build 2>&1 | grep -E 'LotDetailView.+error:' | head -10
```

If empty: skip steps 2–4, this task is a no-op.

- [ ] **Step 2: Read the offending lines**

```bash
grep -n "grade7\|grade8\|grade9\|pricecharting" ios/slabbist/slabbist/Features/Lots/LotDetailView.swift
```

- [ ] **Step 3: Patch any straggling references**

If any `grade7PriceCents` / `pricechartingURL` references appear, replace with the corresponding new property names from `GradedMarketSnapshot` (or remove if the surface no longer applies).

- [ ] **Step 4: Build clean, commit if anything changed**

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build 2>&1 | tail -5
git diff ios/slabbist/slabbist/Features/Lots/LotDetailView.swift
# If diff is non-empty:
git add ios/slabbist/slabbist/Features/Lots/LotDetailView.swift
git commit -m "$(cat <<'EOF'
ios: patch LotDetailView for GradedMarketSnapshot rename

No-op if the file already compiled; otherwise touches sites that
referenced dropped fields.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 23: Update `ScanDetailView` copy

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift`

- [ ] **Step 1: Find the copy strings to update**

```bash
grep -n "PriceCharting\|pricecharting\|priceCharting" ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift
```

- [ ] **Step 2: Replace each occurrence**

Edit `ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift` and replace each "PriceCharting" with "Pokemon Price Tracker" in user-facing strings only (not in comments or symbol names that don't exist anymore). Examples of exact replacements:

```text
"Fetching PriceCharting comp…" → "Fetching Pokemon Price Tracker comp…"
"PriceCharting has no comp for this slab yet." → "Pokemon Price Tracker has no comp for this slab yet."
"We couldn't find this card on PriceCharting." → "We couldn't find this card on Pokemon Price Tracker."
"PriceCharting lookup unavailable" → "Pokemon Price Tracker lookup unavailable"
```

- [ ] **Step 3: Build clean**

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Features/Scanning/ScanDetailView.swift
git commit -m "$(cat <<'EOF'
ios: update ScanDetailView fetch/empty/error copy for PPT

Source-name swap only — state machine and view structure unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 24: Rewrite `CompRepositoryTests`

**Files:**
- Modify: `ios/slabbist/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift`
- Modify: `ios/slabbist/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift`

> Repository path: actual file lives at `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift`. Use that exact path; the leading `ios/slabbist/slabbist/` typo above is shorthand.

- [ ] **Step 1: Replace `CompRepositoryTests.swift`**

```swift
import Testing
import Foundation
import SwiftData
@testable import slabbist

@Suite("CompRepository")
@MainActor
struct CompRepositoryTests {
    @Test("decodes a full PPT cross-grader ladder response")
    func decodesFullLadder() async throws {
        let json = """
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
          "price_history": [
            { "ts": "2025-11-08T00:00:00Z", "price_cents": 16200 },
            { "ts": "2025-11-15T00:00:00Z", "price_cents": 16850 }
          ],
          "ppt_tcgplayer_id": "243172",
          "ppt_url": "https://www.pokemonpricetracker.com/card/charizard-base-set",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": false,
          "is_stale_fallback": false
        }
        """.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == 18500)
        #expect(decoded.psa10PriceCents == 18500)
        #expect(decoded.bgs10PriceCents == 21500)
        #expect(decoded.psa9_5PriceCents == 11200)
        #expect(decoded.loosePriceCents == 400)
        #expect(decoded.priceHistory.count == 2)
        #expect(decoded.priceHistory.first?.priceCents == 16200)
        #expect(decoded.pptTCGPlayerId == "243172")
        #expect(decoded.cacheHit == false)
    }

    @Test("decodes a partial ladder with null tiers")
    func decodesPartialLadder() async throws {
        let json = """
        {
          "headline_price_cents": null,
          "grading_service": "TAG",
          "grade": "10",
          "loose_price_cents": 500,
          "psa_7_price_cents": null,
          "psa_8_price_cents": null,
          "psa_9_price_cents": 4200,
          "psa_9_5_price_cents": null,
          "psa_10_price_cents": 18000,
          "bgs_10_price_cents": null,
          "cgc_10_price_cents": null,
          "sgc_10_price_cents": null,
          "price_history": [],
          "ppt_tcgplayer_id": "98765432",
          "ppt_url": "https://www.pokemonpricetracker.com/card/obscure",
          "fetched_at": "2026-05-07T22:14:03Z",
          "cache_hit": true,
          "is_stale_fallback": false
        }
        """.data(using: .utf8)!
        let decoded = try CompRepository.decode(data: json)
        #expect(decoded.headlinePriceCents == nil)
        #expect(decoded.psa10PriceCents == 18000)
        #expect(decoded.bgs10PriceCents == nil)
        #expect(decoded.priceHistory.isEmpty)
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

- [ ] **Step 2: Inspect existing `CompFetchServiceTests.swift`**

```bash
cat ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift | head -120
```

- [ ] **Step 3: Update any `Decoded` constructions in `CompFetchServiceTests`**

Anywhere it constructs `CompRepository.Decoded(...)`, switch the field set to match the new struct: drop `grade7/8/9/9_5PriceCents`, drop `pricechartingProductId/URL`, add `psa7/8/9/9_5PriceCents`, `pptTCGPlayerId`, `pptURL`, `priceHistory: []`. Snapshot constructions should switch likewise.

If the file is purely about in-flight de-dup (no `Decoded` shapes constructed), skip this step.

- [ ] **Step 4: Run iOS tests**

```bash
xcodebuild -workspace ios/slabbist/slabbist.xcworkspace -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -30
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift \
        ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift
git commit -m "$(cat <<'EOF'
ios: rewrite Comp tests against the PPT payload

CompRepositoryTests now decodes the new wire shape (psa_*, ppt_*,
price_history). CompFetchServiceTests updated where it constructs
Decoded values; in-flight de-dup behavior unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — Secrets and deployment

### Task 25: Set PPT secrets, unset PriceCharting secrets

**Files:** none (Supabase secrets only).

- [ ] **Step 1: Set PPT secrets**

```bash
supabase secrets set \
  POKEMONPRICETRACKER_API_TOKEN="${POKEMONPRICETRACKER_API_TOKEN}" \
  POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS=86400
```

- [ ] **Step 2: Unset PriceCharting secrets**

```bash
supabase secrets unset \
  PRICECHARTING_API_TOKEN \
  PRICECHARTING_FRESHNESS_TTL_SECONDS
```

- [ ] **Step 3: Verify**

```bash
supabase secrets list | grep -E 'POKEMONPRICETRACKER|PRICECHARTING'
```

Expected: only the two POKEMONPRICETRACKER secrets present.

### Task 26: Deploy the Edge Function

**Files:** none.

- [ ] **Step 1: Verify the PPT account is on the paid API tier (BLOCKER)**

Per Task 0 r3 finding, the probe token may have been on the free plan (100 calls/day, 3-day history). Production needs the paid API tier ($9.99/mo, 20k/day, 6-month history) or scans will rate-limit within the first day and the sparkline will be 3 days wide.

```bash
TOKEN=$(cat ~/.slabbist/ppt-token | tr -d '\n\r')
curl -sS -G 'https://www.pokemonpricetracker.com/api/v2/cards' \
  --data-urlencode 'search=charizard' \
  --data-urlencode 'limit=1' \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'X-API-Version: v1' \
  -D /tmp/ppt-tier-headers.txt -o /dev/null
grep -iE 'x-ratelimit-(daily-limit|daily-remaining)' /tmp/ppt-tier-headers.txt
```

Expected: `x-ratelimit-daily-limit: 20000` (or higher for Business tier). If it shows `100`, the account is still on free — STOP and ask the user to upgrade, then re-run this step.

- [ ] **Step 2: Deploy**

```bash
supabase functions deploy price-comp 2>&1 | tail -20
```

Expected: deployment success.

- [ ] **Step 3: Tail logs and run a curl smoke test**

In one terminal:
```bash
supabase functions logs price-comp --tail 2>&1
```

In another:
```bash
SLAB_USER_JWT="<paste a valid user JWT from the iOS app>"
SLAB_IDENTITY_ID="<a real UUID from graded_card_identities>"
curl -sS -X POST "$(supabase status -o json | jq -r .API_URL)/functions/v1/price-comp" \
  -H "authorization: Bearer ${SLAB_USER_JWT}" \
  -H "content-type: application/json" \
  -d "{\"graded_card_identity_id\":\"${SLAB_IDENTITY_ID}\",\"grading_service\":\"PSA\",\"grade\":\"10\"}" \
  | jq .
```

Expected: HTTP 200 with the new payload shape (`headline_price_cents`, `psa_*_price_cents`, `bgs_10_price_cents`, `price_history` array, `ppt_tcgplayer_id`, `ppt_url`). The log line `price-comp.live` shows `matched: "searched"` on first call, `cache_hit: true` on the second within 24h.

---

## Phase 5 — Manual end-to-end smoke tests

### Task 27: Five simulator smoke flows + airplane-mode retry

**Files:** none — manual QA.

- [ ] **Step 1: PSA 10 — known card (Charizard Base Set or similar)**

Run the iOS app in the simulator. Scan / manually-enter a known PSA 10 cert. Wait for the comp card to render. Verify:

- Hero shows a real dollar amount.
- Sparkline draws.
- All applicable ladder cells render. The PSA 10 cell has the gold border.
- Footer link opens the PPT product page in Safari.

- [ ] **Step 2: PSA 9 — known card**

Repeat with a PSA 9 cert. Verify the gold border lands on PSA 9 and the headline matches the PSA 9 cell.

- [ ] **Step 3: PSA 9.5 — known half-grade**

Repeat with a PSA 9.5 cert. Confirm `psa_9_5_price` populates correctly and the gold border lands on the PSA 9.5 cell.

- [ ] **Step 4: BGS 10 — known card**

Repeat with a BGS 10 cert. Confirm the headline pulls from `bgs_10_price`, the BGS 10 cell has the gold border, and there's no caveat row.

- [ ] **Step 5: TAG slab (or any unsupported grader)**

Repeat with a TAG-graded slab. Confirm:

- Hero shows `—`.
- Caveat row says "Pokemon Price Tracker hasn't logged TAG 10 sales — showing the rest of the ladder."
- The PSA / BGS / CGC / SGC ladder cells still render where data exists.

- [ ] **Step 6: Never-seen identity → cached id sticks**

Scan a card that's been freshly added to `graded_card_identities` (no `ppt_tcgplayer_id` cached). Tail logs:

```bash
supabase functions logs price-comp --tail | grep -E 'matched|first_resolved'
```

Expected: first call logs `matched: "searched"` and `ppt.match.first_resolved`. Second call (within 24h) logs `cache_hit: true` and `matched: "cached_id"`.

- [ ] **Step 7: Airplane-mode retry**

Before scanning, enable Airplane Mode on the simulator (Hardware → Network Link Conditioner → 100% loss). Trigger a comp fetch. Confirm:

- iOS state flips to `failed` or `noData` per `classify`.
- Outbox shows the job pending retry.
- Toggle airplane mode off, observe outbox retry succeed and the snapshot resolve.

---

## Self-review

**Spec coverage:** Each spec section maps to one or more tasks above:

| Spec section | Task |
|---|---|
| Update history (r2) | Driven by Task 0; r3 added inline if probe finds drift |
| Architecture diagram | Task 13 (orchestrator) |
| API surface | Tasks 7–9 (parse/client/cards) |
| Data model: identity migrations | Tasks 1–2 |
| Data model: market migrations | Tasks 3–4 |
| Data model: iOS SwiftData | Tasks 16–17 |
| `/price-comp` request shape | Tasks 10, 18 |
| `/price-comp` response shape | Tasks 10, 18, 21 |
| Error responses | Tasks 13 (server) and 18, 19 (client classify) |
| Hybrid match | Tasks 13, 14 |
| Cache, freshness, secrets | Tasks 11, 13 (TTL env), 25 (secrets) |
| Persistence (live path) | Tasks 11, 12, 13 |
| Failure modes | Task 13 + Task 14 (test cases) |
| iOS — CompCardView | Tasks 20, 21 |
| iOS — ScanDetailView | Task 23 |
| iOS — CompRepository | Task 18 |
| iOS — CompFetchService | Task 19 |
| iOS — LotDetailView | Task 22 |
| Outbox unchanged | n/a (verified by Task 27 step 7) |
| Files: delete / rewrite / add | Tasks 6–22 collectively + Task 15 deletion |
| Testing strategy | Tasks 6, 7, 8, 9, 14, 16, 24, 27 |
| Observability | Task 13 (log lines) |
| Security | Task 25 (secrets) |

**Placeholders:** none. Every step has concrete code, paths, and commands.

**Type consistency:** `LadderPrices` keys use `loose / psa_7 / … / sgc_10` consistently across `parse.ts`, `market.ts`, the orchestrator, the wire response, and the SwiftData model. `pptTCGPlayerId` (camelCase) on iOS, `ppt_tcgplayer_id` (snake_case) on the wire and SQL columns. `_resetPause()` from `client.ts` is re-exported as `_resetPauseForTests()` from `cards.ts` for use in `index.test.ts`. The `priceHistory` shape `{ts: Date, priceCents: Int64}` (Swift) ↔ `{ts: ISO string, price_cents: int}` (wire / Deno) is consistent across decoders.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-07-pokemonpricetracker-comp-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
