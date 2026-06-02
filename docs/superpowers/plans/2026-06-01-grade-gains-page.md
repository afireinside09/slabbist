# Grade Gains Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iOS page that ranks raw Pokémon cards by grade-up profit (PSA 10 − raw − fee), mirroring the Movers tab's filtering, backed by a Poketrace-sourced comp table and a budgeted backfill.

**Architecture:** A new global `tcg_grade_comp` table (keyed by `tcg_products.product_id`) materializes the raw↔graded join. A resumable scraper job fills it newest-English-sets-first within a daily Poketrace request budget. Two live SQL RPCs (`get_grade_gain_sets`, `get_set_grade_gains`) join `tcg_products ⨝ tcg_prices ⨝ tcg_grade_comp` and rank by spread. A new SwiftUI page reuses the Movers filter components and adds a client-side fee control.

**Tech Stack:** Postgres 17 (migrations + plpgsql/sql RPCs), Bun + TypeScript + Vitest (scraper), SwiftUI + SwiftData + Supabase Swift (iOS).

**Spec:** `docs/superpowers/specs/2026-06-01-grade-gains-page-design.md`

---

## File Structure

**Phase 1 — Database**
- Create: `supabase/migrations/20260601120000_tcg_grade_comp.sql` — table + indexes + the two RPCs.
- Create: `supabase/tests/grade_gains_rpcs.sql` — SQL assertions for the RPCs.

**Phase 2 — Scraper backfill**
- Modify: `scraper/src/shared/config.ts` — add `poketrace: { apiKey?, baseUrl }` to `AppConfig`.
- Create: `scraper/src/graded/sources/poketrace.ts` — minimal Poketrace HTTP client (search + PSA 10 detail), budget-aware.
- Create: `scraper/src/graded/sources/poketrace.test.ts` — unit tests for parse + budget header.
- Create: `scraper/src/graded/ingest/poketrace-comp.ts` — the backfill orchestrator.
- Create: `scraper/src/graded/ingest/poketrace-comp.test.ts` — unit tests (skip-fresh, sentinel, budget stop).
- Modify: `scraper/src/cli.ts` — add `run graded poketrace-comp` job.

**Phase 3 — iOS page**
- Create: `ios/slabbist/slabbist/Core/Data/DTOs/GradeGainDTO.swift`
- Create: `ios/slabbist/slabbist/Core/Data/DTOs/GradeGainSetDTO.swift`
- Create: `ios/slabbist/slabbist/Core/Data/Repositories/GradeGainRepository.swift`
- Create: `ios/slabbist/slabbist/Features/GradeGains/GradeGainModels.swift`
- Create: `ios/slabbist/slabbist/Features/GradeGains/GradeGainViewModel.swift`
- Create: `ios/slabbist/slabbist/Features/GradeGains/GradeGainsListView.swift`
- Create: `ios/slabbist/slabbist/Features/GradeGains/GradeGainDetailView.swift`
- Create: `ios/slabbist/slabbistTests/GradeGainViewModelTests.swift`
- Modify: the root tab container (locate via Task 3.0) to add the new tab.

---

## Phase 1 — Database

### Task 1.1: Create `tcg_grade_comp` table + indexes

**Files:**
- Create: `supabase/migrations/20260601120000_tcg_grade_comp.sql`

- [ ] **Step 1: Write the migration (table + indexes only for now)**

```sql
-- 20260601120000_tcg_grade_comp.sql
-- Materialized raw↔graded join for the Grade Gains page. Keyed by the
-- raw TCGPlayer product id (== tcg_products.product_id == the id
-- Poketrace's /cards?tcgplayer_ids= search accepts). Deliberately FK-free:
-- tcg_* and graded data stay decoupled; this table IS the consumer-side
-- join, not a foreign-key relationship.
--
-- Global reference data like tcg_prices → NOT tenant-scoped, NO RLS.

create table if not exists public.tcg_grade_comp (
  product_id         int  primary key,
  poketrace_card_id  text not null default '',   -- '' = looked-up, no match
  psa10_price_cents  int,                         -- PSA 10 avg; null = no PSA 10 tier
  pt_trend           text check (pt_trend in ('up','down','stable')),
  pt_confidence      text check (pt_confidence in ('high','medium','low')),
  pt_sale_count      int,
  resolved_at        timestamptz not null default now()
);

-- Supports spread sorting and "set has gains" checks.
create index if not exists tcg_grade_comp_psa10_idx
  on public.tcg_grade_comp (psa10_price_cents)
  where psa10_price_cents is not null;

comment on table public.tcg_grade_comp is
  'Poketrace PSA 10 comp per raw tcg product. FK-free consumer-side join for the Grade Gains page.';
```

- [ ] **Step 2: Apply the migration**

Run: `supabase db push`
Expected: applies cleanly. If it errors `relation already exists`, INSERT the timestamp into `supabase_migrations.schema_migrations` instead of re-running DDL (per repo convention).

- [ ] **Step 3: Verify the table exists**

Run: `psql "$DATABASE_URL" -c "\d public.tcg_grade_comp"`
Expected: shows the 7 columns and the `tcg_grade_comp_psa10_idx` index.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260601120000_tcg_grade_comp.sql
git commit -m "feat(db): add tcg_grade_comp table for grade gains"
```

### Task 1.2: Add the two read RPCs

**Files:**
- Modify: `supabase/migrations/20260601120000_tcg_grade_comp.sql` (append)

- [ ] **Step 1: Append `get_grade_gain_sets()` and `get_set_grade_gains()`**

```sql
-- ---------------------------------------------------------------
-- Read RPCs. Live joins (data is near-static); no materialized slate.
-- Raw price for a product = the highest market_price across its
-- sub-types (the gradeable chase printing). Spread = psa10 − raw.
-- Reuses public.movers_price_tier(numeric) for raw-price banding so
-- the bands match the Movers tab exactly.
-- ---------------------------------------------------------------

create or replace function public.get_grade_gain_sets()
returns table (
  group_id     int,
  group_name   text,
  gains_count  int,
  published_on date
)
language sql
stable
as $$
  with raw_best as (
    select distinct on (pr.product_id)
      pr.product_id, pr.market_price
    from public.tcg_prices pr
    where pr.market_price is not null and pr.market_price > 0
    order by pr.product_id, pr.market_price desc
  ),
  gains as (
    select p.group_id, count(*)::int as gains_count
    from public.tcg_grade_comp c
    join public.tcg_products p on p.product_id = c.product_id
    join raw_best rb           on rb.product_id = c.product_id
    where c.psa10_price_cents is not null
      and (c.psa10_price_cents - round(rb.market_price * 100)::int) > 0
    group by p.group_id
  )
  select gn.group_id, g.name as group_name, gn.gains_count, g.published_on
  from gains gn
  join public.tcg_groups g on g.group_id = gn.group_id
  where g.category_id = 3        -- English only for v1
  order by g.published_on desc nulls last, g.name asc;
$$;

grant execute on function public.get_grade_gain_sets() to anon, authenticated;

create or replace function public.get_set_grade_gains(
  p_group_id   int,
  p_price_tier text default 'under_5'
)
returns table (
  product_id        int,
  product_name      text,
  group_name        text,
  image_url         text,
  sub_type_name     text,
  raw_price_cents   int,
  psa10_price_cents int,
  spread_cents      int,
  pt_trend          text,
  pt_confidence     text,
  pt_sale_count     int
)
language sql
stable
as $$
  with raw_best as (
    select distinct on (pr.product_id)
      pr.product_id, pr.sub_type_name, pr.market_price
    from public.tcg_prices pr
    where pr.market_price is not null and pr.market_price > 0
    order by pr.product_id, pr.market_price desc
  )
  select
    p.product_id,
    p.name                                                    as product_name,
    g.name                                                    as group_name,
    p.image_url,
    rb.sub_type_name,
    round(rb.market_price * 100)::int                         as raw_price_cents,
    c.psa10_price_cents,
    (c.psa10_price_cents - round(rb.market_price * 100)::int) as spread_cents,
    c.pt_trend,
    c.pt_confidence,
    c.pt_sale_count
  from public.tcg_grade_comp c
  join public.tcg_products p on p.product_id = c.product_id
  join raw_best rb           on rb.product_id = c.product_id
  left join public.tcg_groups g on g.group_id = p.group_id
  where p.group_id = p_group_id
    and c.psa10_price_cents is not null
    and public.movers_price_tier(rb.market_price) = p_price_tier
    and (c.psa10_price_cents - round(rb.market_price * 100)::int) > 0
  order by spread_cents desc, p.product_id asc;
$$;

grant execute on function public.get_set_grade_gains(int, text) to anon, authenticated;
```

- [ ] **Step 2: Apply**

Run: `supabase db push`
Expected: functions created. (If migration row already recorded, run the two `create or replace` blocks directly via `psql "$DATABASE_URL" -f ...` or the SQL editor.)

- [ ] **Step 3: Smoke-check the RPCs exist**

Run: `psql "$DATABASE_URL" -c "select proname from pg_proc where proname in ('get_grade_gain_sets','get_set_grade_gains');"`
Expected: both names listed.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260601120000_tcg_grade_comp.sql
git commit -m "feat(db): add grade gains read RPCs"
```

### Task 1.3: RPC correctness tests (seeded SQL)

**Files:**
- Create: `supabase/tests/grade_gains_rpcs.sql`

- [ ] **Step 1: Write the test (seed fixtures, assert behavior)**

The test verifies WHY each rule exists: highest-subtype selection, raw-price banding, positive-spread-only, spread-DESC ordering, and set-count agreement.

```sql
-- supabase/tests/grade_gains_rpcs.sql
-- Run: psql "$DATABASE_URL" -f supabase/tests/grade_gains_rpcs.sql
begin;

-- Minimal fixtures in a disposable group id unlikely to collide.
insert into public.tcg_groups (group_id, category_id, name, published_on)
  values (999001, 3, 'TEST Grade Gains Set', date '2024-01-01')
  on conflict (group_id) do nothing;

-- Product A: holo subtype is the chase (raw $4 → under_5 band), PSA10 $50 → spread 4600
insert into public.tcg_products (product_id, group_id, category_id, name, card_number)
  values (999101, 999001, 3, 'TEST Card A', '1/100') on conflict do nothing;
insert into public.tcg_prices (product_id, sub_type_name, market_price, updated_at) values
  (999101, 'Normal',   1.00, now()),
  (999101, 'Holofoil', 4.00, now())
  on conflict (product_id, sub_type_name) do update set market_price = excluded.market_price;
insert into public.tcg_grade_comp (product_id, poketrace_card_id, psa10_price_cents, resolved_at)
  values (999101, 'uuid-a', 5000, now())
  on conflict (product_id) do update set psa10_price_cents = excluded.psa10_price_cents;

-- Product B: raw $30 (tier_25_50), PSA10 $40 → spread 1000
insert into public.tcg_products (product_id, group_id, category_id, name, card_number)
  values (999102, 999001, 3, 'TEST Card B', '2/100') on conflict do nothing;
insert into public.tcg_prices (product_id, sub_type_name, market_price, updated_at)
  values (999102, 'Normal', 30.00, now())
  on conflict (product_id, sub_type_name) do update set market_price = excluded.market_price;
insert into public.tcg_grade_comp (product_id, poketrace_card_id, psa10_price_cents, resolved_at)
  values (999102, 'uuid-b', 4000, now())
  on conflict (product_id) do update set psa10_price_cents = excluded.psa10_price_cents;

-- Product C: negative spread (PSA10 < raw) → must NOT appear
insert into public.tcg_products (product_id, group_id, category_id, name, card_number)
  values (999103, 999001, 3, 'TEST Card C', '3/100') on conflict do nothing;
insert into public.tcg_prices (product_id, sub_type_name, market_price, updated_at)
  values (999103, 'Normal', 100.00, now())
  on conflict (product_id, sub_type_name) do update set market_price = excluded.market_price;
insert into public.tcg_grade_comp (product_id, poketrace_card_id, psa10_price_cents, resolved_at)
  values (999103, 'uuid-c', 5000, now())
  on conflict (product_id) do update set psa10_price_cents = excluded.psa10_price_cents;

-- Assertion 1: under_5 band returns Card A only, raw from the HOLO subtype ($4 → 400c).
do $$
declare r record; begin
  select * into r from public.get_set_grade_gains(999001, 'under_5');
  assert r.product_id = 999101, 'expected Card A in under_5';
  assert r.raw_price_cents = 400, format('expected raw 400c (holo), got %s', r.raw_price_cents);
  assert r.sub_type_name = 'Holofoil', 'expected the highest-priced subtype';
  assert r.spread_cents = 4600, format('expected spread 4600, got %s', r.spread_cents);
end $$;

-- Assertion 2: tier_25_50 returns Card B; Card C (negative spread) is absent everywhere.
do $$
declare cnt int; begin
  select count(*) into cnt from public.get_set_grade_gains(999001, 'tier_25_50');
  assert cnt = 1, format('expected 1 row in tier_25_50, got %s', cnt);
  select count(*) into cnt from public.get_set_grade_gains(999001, 'tier_100_200')
    where product_id = 999103;
  assert cnt = 0, 'negative-spread Card C must never appear';
end $$;

-- Assertion 3: set count (gains_count) equals the total positive-spread products in the set (A + B = 2).
do $$
declare gc int; begin
  select gains_count into gc from public.get_grade_gain_sets() where group_id = 999001;
  assert gc = 2, format('expected gains_count 2, got %s', gc);
end $$;

rollback;  -- leave the DB clean; fixtures vanish.
\echo 'grade_gains_rpcs.sql: ALL ASSERTIONS PASSED'
```

- [ ] **Step 2: Run the test**

Run: `psql "$DATABASE_URL" -f supabase/tests/grade_gains_rpcs.sql`
Expected: ends with `ALL ASSERTIONS PASSED`. Any `assert` failure aborts with the message.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/grade_gains_rpcs.sql
git commit -m "test(db): grade gains RPC correctness"
```

---

## Phase 2 — Scraper backfill

### Task 2.1: Add Poketrace config

**Files:**
- Modify: `scraper/src/shared/config.ts`

- [ ] **Step 1: Add `poketrace` to the `AppConfig` interface**

In the `AppConfig` interface, add after the `grading` block:

```ts
  poketrace: { apiKey?: string | undefined; baseUrl: string };
```

- [ ] **Step 2: Populate it in `loadConfig()`'s return**

Add after the `grading: { ... }` object literal:

```ts
    poketrace: {
      apiKey: process.env.POKETRACE_API_KEY || undefined,
      baseUrl: process.env.POKETRACE_BASE_URL || "https://api.poketrace.com/v1",
    },
```

- [ ] **Step 3: Typecheck**

Run: `cd scraper && bun run typecheck`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add scraper/src/shared/config.ts
git commit -m "feat(scraper): add poketrace config"
```

### Task 2.2: Poketrace source client (TDD)

**Files:**
- Create: `scraper/src/graded/sources/poketrace.ts`
- Create: `scraper/src/graded/sources/poketrace.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// scraper/src/graded/sources/poketrace.test.ts
import { describe, it, expect } from "vitest";
import { searchCardId, fetchPsa10, type PoketraceClient } from "./poketrace.js";

function clientWith(handler: (path: string) => { status: number; json: unknown; daily?: string }): PoketraceClient {
  return {
    apiKey: "k",
    baseUrl: "https://x/v1",
    fetchImpl: async (url: string) => {
      const path = url.replace("https://x/v1", "");
      const { status, json, daily } = handler(path);
      return new Response(JSON.stringify(json), {
        status,
        headers: {
          "content-type": "application/json",
          ...(daily ? { "x-ratelimit-daily-remaining": daily } : {}),
        },
      });
    },
  };
}

describe("searchCardId", () => {
  it("returns the first match uuid and the daily-remaining header", async () => {
    const c = clientWith(() => ({ status: 200, json: { data: [{ id: "uuid-1" }] }, daily: "950" }));
    const r = await searchCardId(c, 12345);
    expect(r).toEqual({ cardId: "uuid-1", dailyRemaining: 950 });
  });

  it("returns null cardId on zero results (sentinel case)", async () => {
    const c = clientWith(() => ({ status: 200, json: { data: [] }, daily: "900" }));
    const r = await searchCardId(c, 12345);
    expect(r).toEqual({ cardId: null, dailyRemaining: 900 });
  });

  it("returns undefined cardId (transient) on non-200 so the caller skips writing a sentinel", async () => {
    const c = clientWith(() => ({ status: 503, json: {} }));
    const r = await searchCardId(c, 12345);
    expect(r.cardId).toBeUndefined();
  });
});

describe("fetchPsa10", () => {
  it("extracts PSA_10 avg as cents plus trend/confidence/saleCount", async () => {
    const c = clientWith(() => ({
      status: 200,
      json: { data: { prices: { ebay: { PSA_10: { avg: 50.5, trend: "up", confidence: "high", saleCount: 12 } } } } },
      daily: "800",
    }));
    const r = await fetchPsa10(c, "uuid-1");
    expect(r).toEqual({
      psa10PriceCents: 5050, ptTrend: "up", ptConfidence: "high", ptSaleCount: 12, dailyRemaining: 800,
    });
  });

  it("returns null price when the card has no PSA_10 tier", async () => {
    const c = clientWith(() => ({ status: 200, json: { data: { prices: { ebay: { PSA_9: { avg: 10 } } } } }, daily: "799" }));
    const r = await fetchPsa10(c, "uuid-1");
    expect(r.psa10PriceCents).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scraper && bun run test poketrace.test`
Expected: FAIL — `./poketrace.js` has no `searchCardId`/`fetchPsa10`.

- [ ] **Step 3: Implement the client**

```ts
// scraper/src/graded/sources/poketrace.ts
// Minimal Poketrace client for the grade-comp backfill. Mirrors the
// edge function's poketrace/client.ts auth + parsing, scoped to the two
// calls the backfill needs: tcgplayer-id search and PSA 10 detail.

export interface PoketraceClient {
  apiKey: string;
  baseUrl: string;            // e.g. https://api.poketrace.com/v1
  fetchImpl?: typeof fetch;
  timeoutMs?: number;         // default 8000
}

export interface SearchResult { cardId: string | null | undefined; dailyRemaining: number | null }
// cardId: string = match; null = zero results (write sentinel); undefined = transient (do NOT write).

export interface Psa10Result {
  psa10PriceCents: number | null;
  ptTrend: "up" | "down" | "stable" | null;
  ptConfidence: "high" | "medium" | "low" | null;
  ptSaleCount: number | null;
  dailyRemaining: number | null;
}

const TREND = new Set(["up", "down", "stable"]);
const CONF = new Set(["high", "medium", "low"]);

async function get(c: PoketraceClient, path: string): Promise<{ status: number; body: any; daily: number | null }> {
  const fetchImpl = c.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), c.timeoutMs ?? 8000);
  let resp: Response;
  try {
    resp = await fetchImpl(`${c.baseUrl}${path}`, {
      method: "GET",
      headers: { "x-api-key": c.apiKey, accept: "application/json" },
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
  const dh = resp.headers.get("x-ratelimit-daily-remaining");
  const daily = dh !== null && Number.isFinite(Number(dh)) ? Number(dh) : null;
  let body: any = null;
  if (resp.headers.get("content-type")?.includes("application/json")) {
    try { body = await resp.json(); } catch { body = null; }
  }
  return { status: resp.status, body, daily };
}

export async function searchCardId(c: PoketraceClient, tcgplayerId: number): Promise<SearchResult> {
  const { status, body, daily } = await get(c, `/cards?tcgplayer_ids=${encodeURIComponent(String(tcgplayerId))}&limit=20`);
  if (status !== 200 || !body?.data) return { cardId: undefined, dailyRemaining: daily };
  if (body.data.length === 0) return { cardId: null, dailyRemaining: daily };
  return { cardId: String(body.data[0].id), dailyRemaining: daily };
}

function dollarsToCents(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? Math.round(v * 100) : null;
}

export async function fetchPsa10(c: PoketraceClient, cardId: string): Promise<Psa10Result> {
  const { status, body, daily } = await get(c, `/cards/${encodeURIComponent(cardId)}`);
  const empty: Psa10Result = { psa10PriceCents: null, ptTrend: null, ptConfidence: null, ptSaleCount: null, dailyRemaining: daily };
  if (status !== 200 || !body?.data?.prices) return empty;
  const prices: Record<string, Record<string, any>> = body.data.prices;
  for (const src of Object.keys(prices)) {
    const tp = prices[src]?.PSA_10;
    if (tp) {
      return {
        psa10PriceCents: dollarsToCents(tp.avg),
        ptTrend: typeof tp.trend === "string" && TREND.has(tp.trend) ? tp.trend : null,
        ptConfidence: typeof tp.confidence === "string" && CONF.has(tp.confidence) ? tp.confidence : null,
        ptSaleCount: typeof tp.saleCount === "number" && Number.isFinite(tp.saleCount) ? tp.saleCount : null,
        dailyRemaining: daily,
      };
    }
  }
  return empty;
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd scraper && bun run test poketrace.test`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scraper/src/graded/sources/poketrace.ts scraper/src/graded/sources/poketrace.test.ts
git commit -m "feat(scraper): poketrace grade-comp source client"
```

### Task 2.3: Backfill orchestrator (TDD)

**Files:**
- Create: `scraper/src/graded/ingest/poketrace-comp.ts`
- Create: `scraper/src/graded/ingest/poketrace-comp.test.ts`

The orchestrator is injectable: it takes a `products` list (already ordered newest-set-first, fetched by the caller), a `now` clock, a `searchImpl`/`detailImpl`, and an `upsert` sink. This keeps the budget/skip/sentinel logic pure and testable without a live DB or API.

- [ ] **Step 1: Write the failing test**

```ts
// scraper/src/graded/ingest/poketrace-comp.test.ts
import { describe, it, expect, vi } from "vitest";
import { backfillProducts, type CompProduct, type BackfillDeps } from "./poketrace-comp.js";

const NOW = Date.parse("2026-06-01T00:00:00Z");
const day = 86_400_000;

function deps(over: Partial<BackfillDeps> = {}): BackfillDeps {
  return {
    now: () => NOW,
    dailyFloor: 200,
    maxRequests: Infinity,
    search: async () => ({ cardId: "uuid", dailyRemaining: 5000 }),
    detail: async () => ({ psa10PriceCents: 5000, ptTrend: null, ptConfidence: null, ptSaleCount: null, dailyRemaining: 5000 }),
    upsert: vi.fn(async () => {}),
    ...over,
  };
}

describe("backfillProducts", () => {
  it("skips products resolved within 7 days", async () => {
    const upsert = vi.fn(async () => {});
    const products: CompProduct[] = [
      { productId: 1, resolvedAt: new Date(NOW - 2 * day).toISOString() }, // fresh → skip
      { productId: 2, resolvedAt: null },                                   // never → process
    ];
    const r = await backfillProducts(products, deps({ upsert }));
    expect(r.skippedFresh).toBe(1);
    expect(upsert).toHaveBeenCalledTimes(1);
    expect(upsert).toHaveBeenCalledWith(expect.objectContaining({ product_id: 2, psa10_price_cents: 5000 }));
  });

  it("writes the empty-string sentinel on zero search results", async () => {
    const upsert = vi.fn(async () => {});
    const r = await backfillProducts([{ productId: 9, resolvedAt: null }],
      deps({ upsert, search: async () => ({ cardId: null, dailyRemaining: 5000 }) }));
    expect(r.noMatch).toBe(1);
    expect(upsert).toHaveBeenCalledWith(expect.objectContaining({ product_id: 9, poketrace_card_id: "", psa10_price_cents: null }));
  });

  it("does NOT write on transient failure (undefined cardId)", async () => {
    const upsert = vi.fn(async () => {});
    const r = await backfillProducts([{ productId: 9, resolvedAt: null }],
      deps({ upsert, search: async () => ({ cardId: undefined, dailyRemaining: 5000 }) }));
    expect(upsert).not.toHaveBeenCalled();
    expect(r.transient).toBe(1);
  });

  it("stops when daily-remaining drops below the floor", async () => {
    const upsert = vi.fn(async () => {});
    const products: CompProduct[] = [
      { productId: 1, resolvedAt: null },
      { productId: 2, resolvedAt: null },
    ];
    // First search returns just-above-floor; detail returns below-floor → stop before product 2.
    const r = await backfillProducts(products, deps({
      upsert,
      search: async () => ({ cardId: "uuid", dailyRemaining: 250 }),
      detail: async () => ({ psa10PriceCents: 5000, ptTrend: null, ptConfidence: null, ptSaleCount: null, dailyRemaining: 150 }),
    }));
    expect(r.covered).toBe(1);
    expect(r.stoppedOnBudget).toBe(true);
    expect(upsert).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scraper && bun run test poketrace-comp.test`
Expected: FAIL — module/exports missing.

- [ ] **Step 3: Implement the pure orchestrator**

```ts
// scraper/src/graded/ingest/poketrace-comp.ts (pure core; DB wiring in runPoketraceCompIngest below)
import type { SearchResult, Psa10Result } from "@/graded/sources/poketrace.js";

export interface CompProduct { productId: number; resolvedAt: string | null }

export interface CompUpsertRow {
  product_id: number;
  poketrace_card_id: string;
  psa10_price_cents: number | null;
  pt_trend: string | null;
  pt_confidence: string | null;
  pt_sale_count: number | null;
  resolved_at: string;
}

export interface BackfillDeps {
  now: () => number;
  dailyFloor: number;
  maxRequests: number;
  search: (tcgplayerId: number) => Promise<SearchResult>;
  detail: (cardId: string) => Promise<Psa10Result>;
  upsert: (row: CompUpsertRow) => Promise<void>;
}

export interface BackfillResult {
  covered: number;       // wrote a real comp (uuid + maybe price)
  noMatch: number;       // wrote the '' sentinel
  transient: number;     // skipped, will retry next run
  skippedFresh: number;  // < 7d old, untouched
  requests: number;
  stoppedOnBudget: boolean;
}

const SEVEN_DAYS = 7 * 86_400_000;

export async function backfillProducts(products: CompProduct[], deps: BackfillDeps): Promise<BackfillResult> {
  const r: BackfillResult = { covered: 0, noMatch: 0, transient: 0, skippedFresh: 0, requests: 0, stoppedOnBudget: false };
  const nowMs = deps.now();
  for (const p of products) {
    if (p.resolvedAt && nowMs - Date.parse(p.resolvedAt) < SEVEN_DAYS) { r.skippedFresh++; continue; }
    if (r.requests >= deps.maxRequests) { r.stoppedOnBudget = true; break; }

    const s = await deps.search(p.productId);
    r.requests++;
    if (s.cardId === undefined) { r.transient++; }       // transient — write nothing
    else if (s.cardId === null) {                         // confirmed no match — sentinel
      await deps.upsert({
        product_id: p.productId, poketrace_card_id: "", psa10_price_cents: null,
        pt_trend: null, pt_confidence: null, pt_sale_count: null,
        resolved_at: new Date(nowMs).toISOString(),
      });
      r.noMatch++;
    } else {                                              // match — fetch PSA 10
      const d = await deps.detail(s.cardId);
      r.requests++;
      await deps.upsert({
        product_id: p.productId, poketrace_card_id: s.cardId, psa10_price_cents: d.psa10PriceCents,
        pt_trend: d.ptTrend, pt_confidence: d.ptConfidence, pt_sale_count: d.ptSaleCount,
        resolved_at: new Date(nowMs).toISOString(),
      });
      r.covered++;
      if (d.dailyRemaining !== null && d.dailyRemaining < deps.dailyFloor) { r.stoppedOnBudget = true; break; }
    }
    if (s.dailyRemaining !== null && s.dailyRemaining < deps.dailyFloor) { r.stoppedOnBudget = true; break; }
    if (r.requests >= deps.maxRequests) { r.stoppedOnBudget = true; break; }
  }
  return r;
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd scraper && bun run test poketrace-comp.test`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add scraper/src/graded/ingest/poketrace-comp.ts scraper/src/graded/ingest/poketrace-comp.test.ts
git commit -m "feat(scraper): grade-comp backfill core (budget + skip + sentinel)"
```

### Task 2.4: DB-backed runner + product ordering

**Files:**
- Modify: `scraper/src/graded/ingest/poketrace-comp.ts` (append `runPoketraceCompIngest`)

This wraps the pure core with: fetching products newest-set-first, building the live client closures, run bookkeeping, and `tcg_grade_comp` upserts. No new unit test (it is thin glue over tested parts + the live API); it is exercised by the live smoke run in Step 3.

- [ ] **Step 1: Append the runner**

```ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Logger } from "@/shared/logger.js";
import { throwIfError } from "@/shared/db/supabase.js";
import { searchCardId, fetchPsa10, type PoketraceClient } from "@/graded/sources/poketrace.js";

export interface RunOptions {
  supabase: SupabaseClient;
  client: PoketraceClient;
  dailyFloor: number;
  maxRequests: number;
  log: Logger;
}

/**
 * Pull English (category 3) products ordered by their group's
 * published_on DESC, joined to any existing comp row's resolved_at so
 * the core can skip fresh ones. Oldest-stale-first falls out naturally
 * because freshly-resolved rows are skipped and re-run picks up where it
 * stopped.
 */
async function loadProducts(supabase: SupabaseClient): Promise<CompProduct[]> {
  // tcg_products has no published_on; order via the group. A SQL view or
  // RPC keeps this tidy — but a direct join query is fine here.
  const { data, error } = await supabase.rpc("grade_comp_candidates");
  if (error) throw error;
  return (data ?? []).map((r: { product_id: number; resolved_at: string | null }) => ({
    productId: r.product_id, resolvedAt: r.resolved_at,
  }));
}

export async function runPoketraceCompIngest(opts: RunOptions): Promise<BackfillResult & { runId: string }> {
  const runId = crypto.randomUUID();
  await throwIfError(opts.supabase.from("graded_ingest_runs").insert({
    id: runId, source: "poketrace-comp", status: "running", started_at: new Date().toISOString(), stats: {},
  }));
  try {
    const products = await loadProducts(opts.supabase);
    const result = await backfillProducts(products, {
      now: () => Date.now(),
      dailyFloor: opts.dailyFloor,
      maxRequests: opts.maxRequests,
      search: (id) => searchCardId(opts.client, id),
      detail: (cardId) => fetchPsa10(opts.client, cardId),
      upsert: async (row) => {
        await throwIfError(opts.supabase.from("tcg_grade_comp").upsert(row, { onConflict: "product_id" }));
      },
    });
    opts.log.info("grade-comp backfill", { ...result });
    await throwIfError(opts.supabase.from("graded_ingest_runs").update({
      status: "completed", finished_at: new Date().toISOString(), stats: result as unknown as Record<string, number>,
    }).eq("id", runId));
    return { ...result, runId };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    await opts.supabase.from("graded_ingest_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg,
    }).eq("id", runId);
    throw e;
  }
}
```

- [ ] **Step 2: Add the `grade_comp_candidates` helper RPC**

Append to `supabase/migrations/20260601120000_tcg_grade_comp.sql`, then `supabase db push`:

```sql
-- Candidate products for the backfill: English products with a raw price,
-- newest set first, carrying any existing comp resolved_at so the worker
-- can skip fresh ones. service_role only — it's an ingest helper.
create or replace function public.grade_comp_candidates()
returns table (product_id int, resolved_at timestamptz)
language sql
stable
as $$
  select p.product_id, c.resolved_at
  from public.tcg_products p
  join public.tcg_groups g on g.group_id = p.group_id
  join public.tcg_prices pr
    on pr.product_id = p.product_id and pr.market_price is not null and pr.market_price > 0
  left join public.tcg_grade_comp c on c.product_id = p.product_id
  where g.category_id = 3
  group by p.product_id, c.resolved_at, g.published_on
  order by g.published_on desc nulls last, p.product_id asc;
$$;

grant execute on function public.grade_comp_candidates() to service_role;
```

- [ ] **Step 3: Typecheck**

Run: `cd scraper && bun run typecheck`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add scraper/src/graded/ingest/poketrace-comp.ts supabase/migrations/20260601120000_tcg_grade_comp.sql
git commit -m "feat(scraper): db-backed grade-comp runner + candidates RPC"
```

### Task 2.5: Wire the CLI job

**Files:**
- Modify: `scraper/src/cli.ts`

- [ ] **Step 1: Import the runner and the client config**

Add to the imports at the top:

```ts
import { runPoketraceCompIngest } from "@/graded/ingest/poketrace-comp.js";
```

- [ ] **Step 2: Extend the `run graded` action to handle `poketrace-comp`**

In `run.command("graded")`, add `--max-requests` and `--daily-floor` options to the command chain:

```ts
  .option("--max-requests <n>", "poketrace-comp: hard cap on requests this run", "0")
  .option("--daily-floor <n>", "poketrace-comp: stop when x-ratelimit-daily-remaining < floor", "200")
```

Then inside the action, before the final `log.error("unknown graded job")`, add:

```ts
    if (job === "poketrace-comp") {
      if (!cfg.poketrace.apiKey) { log.error("POKETRACE_API_KEY not set"); process.exit(2); }
      const maxRequests = Number(o.maxRequests) > 0 ? Number(o.maxRequests) : Infinity;
      const res = await runPoketraceCompIngest({
        supabase: getSupabase(),
        client: { apiKey: cfg.poketrace.apiKey, baseUrl: cfg.poketrace.baseUrl },
        dailyFloor: Number(o.dailyFloor),
        maxRequests,
        log,
      });
      log.info("poketrace-comp done", { runId: res.runId, covered: res.covered, noMatch: res.noMatch,
        transient: res.transient, skippedFresh: res.skippedFresh, requests: res.requests, stoppedOnBudget: res.stoppedOnBudget });
      return;
    }
```

Also update the `argument("<job>", "job: pop")` help text to `"job: pop | poketrace-comp"`.

- [ ] **Step 3: Typecheck + run the full scraper test suite**

Run: `cd scraper && bun run typecheck && bun run test`
Expected: typecheck clean; all tests pass.

- [ ] **Step 4: Live smoke run (small budget) — verify the wire contract**

Run: `cd scraper && bun run cli run graded poketrace-comp --max-requests 20`
Expected: logs `poketrace-comp done` with `covered`+`noMatch`+`transient` ≈ requests/calls; no throw. Per CLAUDE.md rule 6, this is the live round-trip that confirms the real Poketrace response decodes — do not declare the source done without it. Then verify rows landed:

Run: `psql "$DATABASE_URL" -c "select count(*), count(psa10_price_cents) from public.tcg_grade_comp;"`
Expected: a small non-zero count.

- [ ] **Step 5: Commit**

```bash
git add scraper/src/cli.ts
git commit -m "feat(scraper): wire run graded poketrace-comp CLI job"
```

### Task 2.6: Seed enough data for the iOS phase

- [ ] **Step 1: Run a larger budgeted pass over the newest English sets**

Run: `cd scraper && bun run cli run graded poketrace-comp --max-requests 2000`
Expected: `poketrace-comp done` with several hundred `covered`. Confirms the page will have real rows. Record the printed counts in the commit message of the next phase's first task for traceability.

(No code change / commit — this is a data run.)

---

## Phase 3 — iOS page

### Task 3.0: Locate the tab container

- [ ] **Step 1: Find where top-level tabs/pages are registered**

Run: `grep -rn "MoversListView" ios/slabbist/slabbist --include=*.swift | grep -v "/Movers/"`
Expected: identifies the parent (e.g. a `TabView` or root navigation file) that instantiates `MoversListView`. Note the file path — Task 3.7 adds the Grade Gains entry alongside it. Match whatever pattern that file uses (tab item vs. nav link).

(No commit.)

### Task 3.1: DTOs

**Files:**
- Create: `ios/slabbist/slabbist/Core/Data/DTOs/GradeGainDTO.swift`
- Create: `ios/slabbist/slabbist/Core/Data/DTOs/GradeGainSetDTO.swift`

Cents are integers server-side (`round(...)::int`), so plain `Int` decoding — no flexible-double coercion needed.

- [ ] **Step 1: Write `GradeGainDTO`**

```swift
import Foundation

/// One row from `get_set_grade_gains`. Profit (psa10 − raw − fee) is
/// computed client-side because the fee is user-adjustable; this DTO
/// carries only server facts.
nonisolated struct GradeGainDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let productId: Int
    let productName: String
    let groupName: String?
    let imageUrl: String?
    let subTypeName: String
    let rawPriceCents: Int
    let psa10PriceCents: Int
    let spreadCents: Int
    let ptTrend: String?
    let ptConfidence: String?
    let ptSaleCount: Int?

    var id: Int { productId }

    /// Profit in cents for a given grading fee (cents). Clamped at the
    /// raw spread — fee only ever reduces it.
    func profitCents(feeCents: Int) -> Int { spreadCents - feeCents }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productName = "product_name"
        case groupName = "group_name"
        case imageUrl = "image_url"
        case subTypeName = "sub_type_name"
        case rawPriceCents = "raw_price_cents"
        case psa10PriceCents = "psa10_price_cents"
        case spreadCents = "spread_cents"
        case ptTrend = "pt_trend"
        case ptConfidence = "pt_confidence"
        case ptSaleCount = "pt_sale_count"
    }
}
```

- [ ] **Step 2: Write `GradeGainSetDTO`**

```swift
import Foundation

/// One row from `get_grade_gain_sets` — an English set with ≥1
/// positive-spread product. `gainsCount` is the number of such products.
nonisolated struct GradeGainSetDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let groupId: Int
    let groupName: String
    let gainsCount: Int
    let publishedOn: Date?

    var id: Int { groupId }

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case groupName = "group_name"
        case gainsCount = "gains_count"
        case publishedOn = "published_on"
    }
}
```

- [ ] **Step 3: Build to typecheck**

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build -quiet`
Expected: BUILD SUCCEEDED (new files compile). If the project doesn't auto-add files to the target, add them to the `slabbist` target in Xcode first.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/DTOs/GradeGainDTO.swift ios/slabbist/slabbist/Core/Data/DTOs/GradeGainSetDTO.swift
git commit -m "feat(ios): grade gains DTOs"
```

### Task 3.2: Repository

**Files:**
- Create: `ios/slabbist/slabbist/Core/Data/Repositories/GradeGainRepository.swift`

Mirror `SupabaseMoversRepository`'s structure (protocol + `nonisolated struct` + `SupabaseError.map`).

- [ ] **Step 1: Write the repository**

```swift
import Foundation
import Supabase

protocol GradeGainRepository: Sendable {
    func sets() async throws -> [GradeGainSetDTO]
    func setGains(groupId: Int, priceTier: MoversPriceTier) async throws -> [GradeGainDTO]
}

nonisolated struct SupabaseGradeGainRepository: GradeGainRepository, Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    func sets() async throws -> [GradeGainSetDTO] {
        do {
            let response = try await client.rpc("get_grade_gain_sets").execute()
            return try JSONCoders.decoder.decode([GradeGainSetDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func setGains(groupId: Int, priceTier: MoversPriceTier) async throws -> [GradeGainDTO] {
        do {
            let response = try await client.rpc(
                "get_set_grade_gains",
                params: SetGainsParams(p_group_id: groupId, p_price_tier: priceTier.rawValue)
            ).execute()
            return try JSONCoders.decoder.decode([GradeGainDTO].self, from: response.data)
        } catch {
            throw SupabaseError.map(error)
        }
    }

    private struct SetGainsParams: Encodable { let p_group_id: Int; let p_price_tier: String }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build -quiet`
Expected: BUILD SUCCEEDED. (`AppSupabase`, `JSONCoders`, `SupabaseError` already exist — confirm the exact symbol names match `MoversRepository.swift`; if `get_grade_gain_sets` needs an empty params struct, add `params:` accordingly.)

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/Repositories/GradeGainRepository.swift
git commit -m "feat(ios): grade gains repository"
```

### Task 3.3: View model (TDD)

**Files:**
- Create: `ios/slabbist/slabbist/Features/GradeGains/GradeGainModels.swift`
- Create: `ios/slabbist/slabbist/Features/GradeGains/GradeGainViewModel.swift`
- Create: `ios/slabbist/slabbistTests/GradeGainViewModelTests.swift`

The view model reuses `MoversPriceTier` (no new tier enum). It owns: selected set, selected tier, fee (cents), loaded rows, and the set list — with the same fingerprint-reload + inflight-drop discipline as `MoversViewModel`, minus tabs/language.

- [ ] **Step 1: Write `GradeGainModels.swift` (loading-state enum + a fake repo for tests)**

```swift
import Foundation

enum GradeGainSection: Equatable {
    case idle
    case loading
    case loaded([GradeGainDTO])
    case error(String)
}
```

- [ ] **Step 2: Write the failing test**

The key business rules under test: (a) fee reduces profit and hides rows that go non-positive, (b) sets default to the newest when none selected, (c) a stale in-flight response is dropped after the filter changes.

```swift
import XCTest
@testable import slabbist

@MainActor
final class GradeGainViewModelTests: XCTestCase {

    private func row(_ id: Int, raw: Int, psa10: Int) -> GradeGainDTO {
        GradeGainDTO(productId: id, productName: "C\(id)", groupName: "S", imageUrl: nil,
                     subTypeName: "Holofoil", rawPriceCents: raw, psa10PriceCents: psa10,
                     spreadCents: psa10 - raw, ptTrend: nil, ptConfidence: nil, ptSaleCount: nil)
    }

    struct FakeRepo: GradeGainRepository {
        let sets_: [GradeGainSetDTO]
        let gains_: [GradeGainDTO]
        func sets() async throws -> [GradeGainSetDTO] { sets_ }
        func setGains(groupId: Int, priceTier: MoversPriceTier) async throws -> [GradeGainDTO] { gains_ }
    }

    func test_fee_hides_rows_that_go_unprofitable() async {
        // Card with $30 spread survives a $25 fee; $10-spread card does not.
        let repo = FakeRepo(
            sets_: [GradeGainSetDTO(groupId: 1, groupName: "S", gainsCount: 2, publishedOn: nil)],
            gains_: [row(1, raw: 500, psa10: 3500), row(2, raw: 500, psa10: 1500)] // spreads 3000, 1000
        )
        let vm = GradeGainViewModel(repository: repo)
        await vm.load()
        vm.feeCents = 2500
        let visible = vm.visibleRows
        XCTAssertEqual(visible.map(\.productId), [1], "only the >$25-spread card stays profitable after the fee")
        XCTAssertEqual(visible.first?.profitCents(feeCents: vm.feeCents), 500)
    }

    func test_bootstraps_to_newest_set_when_none_selected() async {
        let repo = FakeRepo(
            sets_: [
                GradeGainSetDTO(groupId: 10, groupName: "Older", gainsCount: 1, publishedOn: Date(timeIntervalSince1970: 0)),
                GradeGainSetDTO(groupId: 20, groupName: "Newer", gainsCount: 1, publishedOn: Date(timeIntervalSince1970: 10_000)),
            ],
            gains_: [row(1, raw: 100, psa10: 5000)]
        )
        let vm = GradeGainViewModel(repository: repo)
        await vm.load()
        XCTAssertEqual(vm.selectedSet, 20, "newest set (by published_on, server-ordered first) is selected")
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:slabbistTests/GradeGainViewModelTests`
Expected: FAIL — `GradeGainViewModel` undefined.

- [ ] **Step 4: Implement the view model**

```swift
import Foundation
import SwiftUI

@Observable
@MainActor
final class GradeGainViewModel {
    private let repository: GradeGainRepository

    var sets: [GradeGainSetDTO] = []
    var selectedSet: Int?
    var priceTier: MoversPriceTier = .under5
    /// User-adjustable grading fee in cents. Persisted across launches.
    var feeCents: Int {
        didSet { UserDefaults.standard.set(feeCents, forKey: Self.feeKey) }
    }
    var section: GradeGainSection = .idle

    private static let feeKey = "gradeGain.feeCents"
    private var inflight: String?

    init(repository: GradeGainRepository = SupabaseGradeGainRepository()) {
        self.repository = repository
        let saved = UserDefaults.standard.integer(forKey: Self.feeKey)
        self.feeCents = saved > 0 ? saved : 2500   // default $25
    }

    /// Rows that remain profitable after the current fee, server-sorted by
    /// spread (so the fee, a constant, preserves order).
    var visibleRows: [GradeGainDTO] {
        guard case let .loaded(rows) = section else { return [] }
        return rows.filter { $0.profitCents(feeCents: feeCents) > 0 }
    }

    private var fingerprint: String { "\(selectedSet.map(String.init) ?? "nil")|\(priceTier.rawValue)" }

    func load() async {
        if sets.isEmpty {
            do { sets = try await repository.sets() }
            catch { section = .error(String(describing: error)); return }
        }
        if selectedSet == nil {
            // Newest set by release date. The RPC already orders newest-first,
            // but selecting on publishedOn explicitly makes the intent (and the
            // test) independent of server ordering.
            selectedSet = sets.max(by: { ($0.publishedOn ?? .distantPast) < ($1.publishedOn ?? .distantPast) })?.groupId
                ?? sets.first?.groupId
        }
        guard let group = selectedSet else { section = .loaded([]); return }

        let fp = fingerprint
        inflight = fp
        section = .loading
        do {
            let rows = try await repository.setGains(groupId: group, priceTier: priceTier)
            guard inflight == fp else { return }   // a newer filter superseded this fetch
            section = .loaded(rows)
        } catch {
            guard inflight == fp else { return }
            section = .error(String(describing: error))
        }
    }

    func select(set groupId: Int) { selectedSet = groupId }
    func select(tier: MoversPriceTier) { priceTier = tier }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:slabbistTests/GradeGainViewModelTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add ios/slabbist/slabbist/Features/GradeGains/GradeGainModels.swift ios/slabbist/slabbist/Features/GradeGains/GradeGainViewModel.swift ios/slabbist/slabbistTests/GradeGainViewModelTests.swift
git commit -m "feat(ios): grade gains view model with fee math"
```

### Task 3.4: List view

**Files:**
- Create: `ios/slabbist/slabbist/Features/GradeGains/GradeGainsListView.swift`

This view is **adapted from `MoversListView.swift`** — reuse its layout idioms (the `SlabbedRoot` container, the price-tier chip rail bound to `MoversPriceTier`, the set search + set chip rail, the skeleton/loaded/error body). Use the SwiftUI skill's rules. The concrete differences from Movers are enumerated below; everything else mirrors `MoversListView`.

Differences:
1. **No tab segmented control** (single surface), and no gainers/losers split — one ranked list (`viewModel.visibleRows`).
2. **Header** title "Grade Gains", subtitle "Raw → PSA 10 upside".
3. **Fee control** in the header: a stepper bound to `viewModel.feeCents` (step 500¢ = $5), label formatted as currency.
4. **Rows** use the new `GradeGainRow` (Task 3.5) instead of `MoverRow`.
5. **Set rail** is fed by `viewModel.sets` (`GradeGainSetDTO`); chip label = `groupName`.
6. Reuse the same `.task(id:)` fingerprint-reload pattern: `.task(id: "\(viewModel.selectedSet ?? -1)|\(viewModel.priceTier.rawValue)") { await viewModel.load() }`.
7. Tapping a row sets `selectedGain` and pushes `GradeGainDetailView` via `.navigationDestination(item:)`.

- [ ] **Step 1: Implement `GradeGainsListView`** following the `MoversListView` structure with the differences above. Bind tier chips to `MoversPriceTier.pickerOptions`, default `.under5`. (Reproduce the rail/search subviews from `MoversListView` adapted to the new view model — copy the visual treatment verbatim so the page matches Movers.)

- [ ] **Step 2: Build**

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/GradeGains/GradeGainsListView.swift
git commit -m "feat(ios): grade gains list view"
```

### Task 3.5: Row view

**Files:**
- Modify: `ios/slabbist/slabbist/Features/GradeGains/GradeGainsListView.swift` (add `GradeGainRow` in-file, mirroring how `MoverRow` lives alongside `MoversListView`)

- [ ] **Step 1: Implement `GradeGainRow`**

Shows: rank, product name + `subTypeName` badge, set name, and a profit-forward stat block: **profit** (big, gold), with raw and PSA 10 beneath (e.g. "$4 → $50"). Takes the current `feeCents` so it can render profit. Visual treatment copied from `MoverRow` (same typography/spacing tokens from `.impeccable.md`).

```swift
struct GradeGainRow: View {
    let rank: Int
    let gain: GradeGainDTO
    let feeCents: Int
    let onTap: () -> Void

    private func dollars(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    var body: some View {
        Button(action: onTap) {
            // … mirror MoverRow's HStack layout: rank, name+badge+set on the
            // leading edge; trailing stat block shows profit prominently with
            // "raw → psa10" underneath and a chevron.
            // Profit = gain.profitCents(feeCents: feeCents).
            EmptyView() // replace with the adapted MoverRow layout
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Fill in the layout** by copying `MoverRow`'s body and swapping the price/percent block for the profit/raw→psa10 block. Build:

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build -quiet`
Expected: BUILD SUCCEEDED, no `EmptyView` placeholder left.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/GradeGains/GradeGainsListView.swift
git commit -m "feat(ios): grade gains row"
```

### Task 3.6: Detail view

**Files:**
- Create: `ios/slabbist/slabbist/Features/GradeGains/GradeGainDetailView.swift`

v1 detail = hero image + profit breakdown (raw / PSA 10 / fee / profit) + the **raw** card's 90-day price history. Reuse the existing `get_product_price_history` RPC via `MoversRepository.priceHistory(productId:subType:days:)` and the same chart component `MoverDetailView` uses. Graded history is out of scope (v2).

- [ ] **Step 1: Implement `GradeGainDetailView`** taking a `GradeGainDTO` and the current `feeCents`. Fetch raw history with `SupabaseMoversRepository().priceHistory(productId: gain.productId, subType: gain.subTypeName, days: 90)` in a `.task`, render with the same chart view used by `MoverDetailView` (locate it: `grep -n "Chart" ios/slabbist/slabbist/Features/Movers/MoverDetailView.swift`). Show the profit breakdown rows above the chart.

- [ ] **Step 2: Build**

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Features/GradeGains/GradeGainDetailView.swift
git commit -m "feat(ios): grade gains detail view"
```

### Task 3.7: Register the tab + live decode round-trip

**Files:**
- Modify: the tab container located in Task 3.0

- [ ] **Step 1: Add the Grade Gains entry** alongside `MoversListView` in the root container, matching that file's pattern (tab item icon/label or nav link). Label "Grade Gains".

- [ ] **Step 2: Build + run the app against the real RPCs**

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build -quiet`
Then launch in the simulator (or via the `run` skill) and open the Grade Gains tab.
Expected: sets load, the newest set is preselected, rows render with profit, the fee stepper changes profits and hides rows, tapping opens detail with the raw history chart. Per CLAUDE.md rule 6, this live `Decodable` round-trip against the deployed RPCs is required before declaring the wire contract done — a curl/unit pass is not sufficient.

- [ ] **Step 3: Run the full iOS test suite**

Run: `xcodebuild test -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
Expected: all `slabbistTests` pass (including `GradeGainViewModelTests`).

- [ ] **Step 4: Commit**

```bash
git add -A ios/slabbist/slabbist
git commit -m "feat(ios): register grade gains tab"
```

---

## Final Verification

- [ ] DB: `psql "$DATABASE_URL" -f supabase/tests/grade_gains_rpcs.sql` → `ALL ASSERTIONS PASSED`.
- [ ] Scraper: `cd scraper && bun run typecheck && bun run test` → clean.
- [ ] iOS: full `xcodebuild test` → green.
- [ ] App: Grade Gains tab loads real data, fee control works, detail shows raw history.
- [ ] Spec open questions resolved: (1) live run confirmed per-card request count (search+detail = 2) — if the live `/cards?tcgplayer_ids=` payload already includes `prices`, file a follow-up to drop the detail call; (2) `gains_count` naming adopted; (3) final tab name confirmed in Task 3.7.
