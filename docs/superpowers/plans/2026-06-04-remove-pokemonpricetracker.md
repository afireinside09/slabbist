# Remove PokemonPriceTracker → Poketrace-only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove PokemonPriceTracker (PPT) from every surface; make Poketrace the sole graded-pricing provider, with PPT-free identity resolution and richer eBay sold-listing display.

**Architecture:** The `price-comp` Edge Function drops its `ppt/` layer and two-provider `reconcile()`. A new `poketrace/resolve.ts` resolves identities via local `tcg_products` cross-walk (Tier A) then Poketrace native `/cards?search=` (Tier B). A new `poketrace/listings.ts` fetches individual sold eBay comps (graceful-degrade off the Scale plan). The wire contract becomes a clean v3 with no PPT fields. iOS decodes v3, drops the source toggle, and adds a sold-comps section. DB drops PPT columns, renames `ppt_tcgplayer_id → tcgplayer_product_id`, and recreates `graded_market_sales` for sold comps.

**Tech Stack:** Deno 2 + TypeScript (Edge Functions, `deno test`), Postgres 17 (migrations + `psql` RLS tests), SwiftUI + SwiftData (iOS, XCTest + snapshot tests), Bun + Vitest (scraper).

**Spec:** `docs/superpowers/specs/2026-06-04-poketrace-only-comp-design.md` — read it before starting.

**Branch:** `remove-pokemonpricetracker` (already created; the spec commit is its first commit).

**Reference — Poketrace API v1.7.0** (probed live 2026-06-04, `https://api.poketrace.com/v1/openapi.json`):
- `GET /cards?search=<name>&card_number=<n>&set=<slug>&tcgplayer_ids=<csv>&has_graded=&limit=20` → `{ data: Card[], pagination }`. `Card = { id, name, cardNumber, set, variant, rarity, marketplaceUrls, prices, ... }`.
- `GET /cards/{id}` → `{ data: { id, prices: { <source>: { <TIER>: TierPrice } }, marketplaceUrls, lastUpdated } }`. Sources: `ebay` (all tiers, US), `tcgplayer` (raw).
- `GET /cards/{id}/prices/{tier}/history?period=30d&limit=50` → `{ data: [{ date, avg }] }`.
- `GET /cards/{id}/listings?grader=&grade=&min_price=&max_price=&sort=sold_at_desc&limit=20` → `{ data: Listing[], pagination }`. **Scale plan only**; non-Scale returns `403`. `Listing = { id, sourceItemId, listingType:'sold', title, price, currency, listingUrl, condition, grader, grade, soldAt, anomalyFlag, anomalyReason }`.
- Auth header: `x-api-key: <POKETRACE_API_KEY>`.

---

## Phase 1 — Database

### Task 1.1: Verify live schema before writing the migration

**Files:** none (read-only verification).

- [ ] **Step 1: Get a DB connection string**

The local env has no `DATABASE_URL`. Obtain the pooler URI from the Supabase dashboard (Project `ksildxueezkvrwryybln` → Settings → Database → Connection string → URI) or via `supabase link` + `supabase db dump`. Export it:

```bash
export DATABASE_URL="postgresql://postgres.<ref>:<password>@<pooler-host>:6543/postgres"
```

- [ ] **Step 2: Dump the two table definitions**

Run:
```bash
psql "$DATABASE_URL" -c '\d public.graded_market'
psql "$DATABASE_URL" -c '\d public.graded_card_identities'
psql "$DATABASE_URL" -c "select to_regclass('public.graded_market_sales');"
```
Expected: `graded_market` shows `headline_price, price_history, source, updated_at, loose_price, psa_7_price, psa_8_price, psa_9_price, psa_9_5_price, psa_10_price, bgs_10_price, cgc_10_price, sgc_10_price, ppt_tcgplayer_id, ppt_url, pt_avg … pt_sale_count, pt_tier_prices_cents`. `graded_card_identities` shows `ppt_tcgplayer_id, ppt_url, poketrace_card_id, poketrace_card_id_resolved_at`. `graded_market_sales` resolves to `NULL` (dropped).

If the live columns differ from the migration-reconstructed list in the spec, **update Task 1.2's SQL to match the live DB** — drop only columns that actually exist.

### Task 1.2: Write the migration

**Files:**
- Create: `supabase/migrations/20260604120000_remove_ppt_poketrace_only.sql`

- [ ] **Step 1: Write the migration SQL**

```sql
-- supabase/migrations/20260604120000_remove_ppt_poketrace_only.sql
-- Remove PokemonPriceTracker; Poketrace becomes the sole graded source.
-- Spec: docs/superpowers/specs/2026-06-04-poketrace-only-comp-design.md

-- 1. Drop PPT-only rows from the market table.
delete from public.graded_market where source = 'pokemonpricetracker';

-- 2. Default future rows to poketrace.
alter table public.graded_market alter column source set default 'poketrace';

-- 3. Drop the PPT ladder + identifiers. Keep headline_price + price_history
--    (written for the poketrace source too) and all pt_* columns.
alter table public.graded_market
  drop column if exists ppt_tcgplayer_id,
  drop column if exists ppt_url,
  drop column if exists loose_price,
  drop column if exists psa_7_price,
  drop column if exists psa_8_price,
  drop column if exists psa_9_price,
  drop column if exists psa_9_5_price,
  drop column if exists psa_10_price,
  drop column if exists bgs_10_price,
  drop column if exists cgc_10_price,
  drop column if exists sgc_10_price;

-- 4. Identities: drop PPT url, rename the tcgplayer id (still needed for the
--    Tier A cross-walk), rename its partial index.
alter table public.graded_card_identities drop column if exists ppt_url;
alter table public.graded_card_identities
  rename column ppt_tcgplayer_id to tcgplayer_product_id;
alter index if exists graded_card_identities_ppt_tcgplayer_idx
  rename to graded_card_identities_tcgplayer_product_idx;

-- 5. Recreate graded_market_sales (dropped in 20260505120200) for sold comps.
create table if not exists public.graded_market_sales (
  id                bigserial primary key,
  identity_id       uuid not null references public.graded_card_identities(id) on delete cascade,
  grading_service   text not null check (grading_service in ('PSA','CGC','BGS','SGC','TAG')),
  grade             text not null,
  source            text not null default 'ebay',
  source_listing_id text not null,
  sold_price        numeric(12,2) not null,
  sold_at           timestamptz not null,
  title             text,
  url               text,
  grader            text,
  condition         text,
  anomaly_flag      text,
  captured_at       timestamptz not null default now(),
  unique (source, source_listing_id)
);
create index if not exists graded_market_sales_sold_at_idx
  on public.graded_market_sales (sold_at desc);
create index if not exists graded_market_sales_lookup_idx
  on public.graded_market_sales (identity_id, grading_service, grade);

-- 6. RLS: readable by authenticated; writes are service-role only (Edge Fn).
alter table public.graded_market_sales enable row level security;
drop policy if exists graded_market_sales_select_authenticated on public.graded_market_sales;
create policy graded_market_sales_select_authenticated
  on public.graded_market_sales for select
  to authenticated
  using (true);
```

- [ ] **Step 2: Apply the migration**

Run: `supabase db push`
Expected: applies `20260604120000_remove_ppt_poketrace_only`. If it errors `relation ... already exists`, reconcile the ledger per CLAUDE.md (INSERT into `supabase_migrations.schema_migrations`) rather than re-running DDL.

- [ ] **Step 3: Verify post-state**

Run:
```bash
psql "$DATABASE_URL" -c '\d public.graded_market' | grep -E 'ppt_|psa_7_price|loose_price' || echo "PPT columns gone: OK"
psql "$DATABASE_URL" -c '\d public.graded_card_identities' | grep -E 'tcgplayer_product_id|ppt_'
psql "$DATABASE_URL" -c '\d public.graded_market_sales' >/dev/null && echo "sales table exists: OK"
```
Expected: "PPT columns gone: OK"; `tcgplayer_product_id` present, no `ppt_*`; sales table exists.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260604120000_remove_ppt_poketrace_only.sql
git commit -m "feat(db): drop PPT columns, rename tcgplayer_product_id, recreate graded_market_sales"
```

### Task 1.3: RLS test for graded_market_sales

**Files:**
- Create: `supabase/tests/rls_graded_market_sales.sql`

- [ ] **Step 1: Write the RLS test**

Model it on the existing `supabase/tests/rls_*.sql` files (read one first for the exact harness — role switching, `set local role`, expected-failure idiom). It must assert:
1. An `authenticated` role can `select` from `graded_market_sales`.
2. An `authenticated` role canNOT `insert`/`update`/`delete` (no write policy).
3. `service_role` can insert.

```sql
-- supabase/tests/rls_graded_market_sales.sql
-- graded_market_sales: authenticated may read; only service_role may write.
begin;

-- service_role can insert (Edge Function path)
set local role service_role;
insert into public.graded_market_sales
  (identity_id, grading_service, grade, source, source_listing_id, sold_price, sold_at)
values
  (gen_random_uuid(), 'PSA', '10', 'ebay', 'test-listing-1', 100.00, now());

-- authenticated can read
set local role authenticated;
do $$
begin
  perform 1 from public.graded_market_sales limit 1;
end $$;

-- authenticated cannot write → expect failure
do $$
begin
  begin
    insert into public.graded_market_sales
      (identity_id, grading_service, grade, source, source_listing_id, sold_price, sold_at)
    values (gen_random_uuid(), 'PSA', '10', 'ebay', 'test-listing-2', 1.0, now());
    raise exception 'RLS FAIL: authenticated insert succeeded';
  exception when insufficient_privilege then
    null; -- expected
  end;
end $$;

rollback;
```

- [ ] **Step 2: Run it**

Run: `psql "$DATABASE_URL" -f supabase/tests/rls_graded_market_sales.sql`
Expected: completes without "RLS FAIL"; ends with `ROLLBACK`.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/rls_graded_market_sales.sql
git commit -m "test(db): RLS coverage for graded_market_sales"
```

---

## Phase 2 — Edge Function `price-comp`

Work in `supabase/functions/price-comp/`. Tests run with `deno test --allow-env --allow-net=<none-needed-for-unit>` — match the existing test invocation (check `deno.json` tasks; existing tests use injected `fetchJsonImpl`/`fetchImpl` overrides so no real network).

### Task 2.1: v3 wire types

**Files:**
- Modify: `supabase/functions/price-comp/types.ts`

- [ ] **Step 1: Replace the PPT/reconciled types with v3**

In `types.ts`: keep `GradingService`, `PriceCompRequest`, `PriceHistoryWirePoint`, `CacheState`, `PoketraceTierFields`, `PoketraceLadderCents`, `PoketraceBlock`. **Delete** `PriceCompResponse` (the PPT-shaped one), `ReconciledSource`, `ReconciledBlock`, `PriceCompResponseV2`. Update `GradedCardIdentity` to drop `ppt_url` and rename `ppt_tcgplayer_id` → `tcgplayer_product_id`. Add:

```ts
export interface SoldListingWire {
  source_listing_id: string;
  title: string | null;
  price_cents: number | null;
  sold_at: string;            // ISO8601
  grader: string | null;      // PSA | BGS | CGC | SGC
  grade: string | null;
  condition: string | null;
  url: string | null;
  anomaly_flag: string | null;
}

// v3 response — Poketrace is the sole source. No PPT fields, no reconciled block.
export interface PriceCompResponse {
  grading_service: GradingService;
  grade: string;
  headline_price_cents: number | null;   // = poketrace avg
  poketrace: PoketraceBlock | null;       // null when no graded tier data
  sold_listings: SoldListingWire[];       // [] off the Scale plan
  marketplace_url: string | null;         // ebay sold-results deep link
  fetched_at: string;
  cache_hit: boolean;
}
```

- [ ] **Step 2: Typecheck**

Run: `deno check supabase/functions/price-comp/types.ts`
Expected: PASS (note: many other files still import deleted names — they get fixed in later tasks; this step only checks `types.ts` parses).

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/types.ts
git commit -m "feat(price-comp): v3 wire types (poketrace-only + sold listings)"
```

### Task 2.2: Card-search scoring + parsing helpers in `poketrace/parse.ts`

**Files:**
- Modify: `supabase/functions/price-comp/poketrace/parse.ts`
- Test: `supabase/functions/price-comp/__tests__/poketrace-parse.test.ts`

- [ ] **Step 1: Write failing tests for `scoreSearchCard` and `parseListings`**

Append to `poketrace-parse.test.ts`:

```ts
import { scoreSearchCard, parseListings } from "../poketrace/parse.ts";

Deno.test("scoreSearchCard: exact number + name accepts", () => {
  const card = { id: "u1", name: "Charizard", cardNumber: "4/102", set: { name: "Base Set" } };
  const r = scoreSearchCard(card, { card_name: "Charizard", card_number: "4", set_name: "Base Set" });
  assert(r.accept);
});

Deno.test("scoreSearchCard: name mismatch rejects", () => {
  const card = { id: "u1", name: "Blastoise", cardNumber: "2/102", set: { name: "Base Set" } };
  const r = scoreSearchCard(card, { card_name: "Charizard", card_number: "4", set_name: "Base Set" });
  assert(!r.accept);
});

Deno.test("parseListings: maps Listing → SoldListingWire, drops invalid", () => {
  const body = { data: [
    { sourceItemId: "e1", title: "Charizard PSA 10", price: 1200.50, listingUrl: "http://x",
      condition: "Graded", grader: "PSA", grade: "10", soldAt: "2026-05-01T00:00:00Z", anomalyFlag: null },
    { sourceItemId: "", title: "bad", price: 1, soldAt: "2026-05-01T00:00:00Z" }, // no id → dropped
  ] };
  const out = parseListings(body);
  assertEquals(out.length, 1);
  assertEquals(out[0].price_cents, 120050);
  assertEquals(out[0].source_listing_id, "e1");
});
```
(Use the same `assert`/`assertEquals` imports the file already has.)

- [ ] **Step 2: Run, verify fail**

Run: `deno test supabase/functions/price-comp/__tests__/poketrace-parse.test.ts`
Expected: FAIL — `scoreSearchCard`/`parseListings` not exported.

- [ ] **Step 3: Implement**

Add to `poketrace/parse.ts`. Reuse the normalize helpers already in `ppt/match.ts` by copying the small pure functions (`cleanName`, `normalizeCardNumber`, `distinctiveSetTokens`, `tokenize`, `SET_STOPWORDS`) into `parse.ts` — `ppt/match.ts` is deleted in Task 2.9, so these must live in the poketrace layer now.

```ts
import type { SoldListingWire } from "../types.ts";

export interface SearchCardLite {
  id: string;
  name?: string | null;
  cardNumber?: string | null;
  set?: { name?: string | null; slug?: string | null } | null;
}
export interface IdentityForSearch {
  card_name: string;
  card_number: string | null;
  set_name: string;
}

// ── pure normalizers (ported from the deleted ppt/match.ts) ──────────
const SET_STOPWORDS = new Set(["promo","promos","set","cards","series","pokemon","tcg","championship","championships"]);
function cleanName(n: string): string {
  return (n ?? "").replace(/\s*\([^)]*\)\s*/g, " ").trim().replace(/\s+/g, " ").toLowerCase();
}
function tokenize(s: string): string[] {
  return s.toLowerCase().replace(/['’]s\b/g, "").replace(/['’]/g, "")
    .replace(/[^a-z0-9\s]+/g, " ").split(/\s+/).filter((t) => t.length > 0);
}
function distinctiveSetTokens(setName: string): string[] {
  return tokenize(setName).filter((t) => t.length >= 4 && !SET_STOPWORDS.has(t));
}
function normalizeCardNumber(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const t = String(raw).trim(); if (!t) return null;
  const lower = t.split("/")[0].toLowerCase().replace(/[^a-z0-9]/g, "");
  if (!lower) return null;
  const stripped = lower.replace(/^0+/, "");
  return stripped.length > 0 ? stripped : "0";
}

export function scoreSearchCard(
  card: SearchCardLite,
  identity: IdentityForSearch,
): { score: number; accept: boolean } {
  const idName = cleanName(identity.card_name);
  const cardName = cleanName(card.name ?? "");
  if (!idName || !cardName) return { score: 0, accept: false };
  if (!(idName.includes(cardName) || cardName.includes(idName))) return { score: 0, accept: false };
  let score = 2; // name hit
  let numberExact = false;
  const idNum = normalizeCardNumber(identity.card_number);
  const cardNum = normalizeCardNumber(card.cardNumber);
  if (idNum && cardNum) {
    if (idNum === cardNum) { score += 3; numberExact = true; }
    else if (idNum.startsWith(cardNum) || cardNum.startsWith(idNum)) score += 1;
  }
  const idSet = new Set(distinctiveSetTokens(identity.set_name));
  const cardSet = new Set(distinctiveSetTokens(card.set?.name ?? ""));
  let overlap = 0;
  for (const t of idSet) if (cardSet.has(t)) overlap += 1;
  score += overlap;
  return { score, accept: numberExact || overlap >= 2 };
}

function dollarsToCents(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? Math.round(v * 100) : null;
}

export function parseListings(body: unknown): SoldListingWire[] {
  const data = (body as { data?: unknown })?.data;
  if (!Array.isArray(data)) return [];
  const out: SoldListingWire[] = [];
  for (const it of data) {
    if (!it || typeof it !== "object") continue;
    const r = it as Record<string, unknown>;
    const id = typeof r.sourceItemId === "string" ? r.sourceItemId : "";
    const soldAt = typeof r.soldAt === "string" ? r.soldAt : "";
    if (!id || !soldAt) continue;
    out.push({
      source_listing_id: id,
      title: typeof r.title === "string" ? r.title : null,
      price_cents: dollarsToCents(r.price),
      sold_at: soldAt,
      grader: typeof r.grader === "string" ? r.grader : null,
      grade: typeof r.grade === "string" ? r.grade : null,
      condition: typeof r.condition === "string" ? r.condition : null,
      url: typeof r.listingUrl === "string" ? r.listingUrl : null,
      anomaly_flag: typeof r.anomalyFlag === "string" ? r.anomalyFlag : null,
    });
  }
  return out;
}
```

- [ ] **Step 4: Run, verify pass**

Run: `deno test supabase/functions/price-comp/__tests__/poketrace-parse.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/poketrace/parse.ts supabase/functions/price-comp/__tests__/poketrace-parse.test.ts
git commit -m "feat(price-comp): card-search scoring + sold-listing parsing"
```

### Task 2.3: `poketrace/resolve.ts` — Tier A + Tier B resolver

**Files:**
- Create: `supabase/functions/price-comp/poketrace/resolve.ts`
- Test: `supabase/functions/price-comp/__tests__/poketrace-resolve.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// __tests__/poketrace-resolve.test.ts
import { assertEquals } from "https://deno.land/std/assert/mod.ts";
import { resolvePoketraceCard } from "../poketrace/resolve.ts";

const baseIdentity = {
  id: "id-1",
  card_name: "Charizard",
  card_number: "4",
  set_name: "Base Set",
  tcgplayer_product_id: null,
  poketrace_card_id: null,
  poketrace_card_id_resolved_at: null,
};

Deno.test("positive cache hit returns cached UUID without any fetch", async () => {
  let calls = 0;
  const id = await resolvePoketraceCard(
    { supabase: fakeSupabase(), client: fakeClient(), now: () => 0,
      findTcgProduct: async () => { calls++; return null; },
      fetchJsonImpl: async () => { calls++; return { status: 200, body: { data: [] } }; } },
    { ...baseIdentity, poketrace_card_id: "cached-uuid" },
  );
  assertEquals(id, "cached-uuid");
  assertEquals(calls, 0);
});

Deno.test("Tier A: tcg_products → tcgplayer_ids cross-walk", async () => {
  const id = await resolvePoketraceCard(
    { supabase: fakeSupabase(), client: fakeClient(), now: () => 0,
      findTcgProduct: async () => ({ productId: 12345, cardName: "Charizard", cardNumber: "4/102" }),
      fetchJsonImpl: async (_c, path) => {
        if (path.includes("tcgplayer_ids=12345")) return { status: 200, body: { data: [{ id: "uuid-A" }] } };
        return { status: 200, body: { data: [] } };
      } },
    baseIdentity,
  );
  assertEquals(id, "uuid-A");
});

Deno.test("Tier B: search fallback when Tier A misses", async () => {
  const id = await resolvePoketraceCard(
    { supabase: fakeSupabase(), client: fakeClient(), now: () => 0,
      findTcgProduct: async () => null, // alias/tcg_products miss
      fetchJsonImpl: async (_c, path) => {
        if (path.includes("search=")) return { status: 200, body: { data: [
          { id: "uuid-B", name: "Charizard", cardNumber: "4/102", set: { name: "Base Set" } } ] } };
        return { status: 200, body: { data: [] } };
      } },
    baseIdentity,
  );
  assertEquals(id, "uuid-B");
});

Deno.test("total miss persists '' sentinel and returns null", async () => {
  let persisted: string | null = "unset";
  const id = await resolvePoketraceCard(
    { supabase: fakeSupabase((v) => { persisted = v; }), client: fakeClient(), now: () => 0,
      findTcgProduct: async () => null,
      fetchJsonImpl: async () => ({ status: 200, body: { data: [] } }) },
    baseIdentity,
  );
  assertEquals(id, null);
  assertEquals(persisted, "");
});

// helpers: fakeSupabase(onPersist?) returns a stub whose update() captures the
// poketrace_card_id; fakeClient() returns { apiKey:"k", baseUrl:"http://x" }.
```
Write `fakeSupabase`/`fakeClient` as small stubs at the top of the test file (the existing `poketrace-match.test.ts` has a Supabase stub pattern to copy).

- [ ] **Step 2: Run, verify fail**

Run: `deno test supabase/functions/price-comp/__tests__/poketrace-resolve.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `resolve.ts`**

```ts
// supabase/functions/price-comp/poketrace/resolve.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// PPT-free identity resolver. Resolves a graded_card_identity to a
// Poketrace card UUID and caches it on graded_card_identities.poketrace_card_id.
//   Tier A: alias → tcg_products → tcgplayer product_id → /cards?tcgplayer_ids=
//   Tier B: native /cards?search=<name>&card_number=<n> with scoring.
//   '' sentinel = looked, no match (re-attempt after 7 days).

import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import { scoreSearchCard, type SearchCardLite } from "./parse.ts";
import { aliasForPsaSet } from "../lib/psa-aliases.ts";
import { findTcgProductByGroupAndCard, type TcgProductMatch } from "../lib/tcg-products.ts";
import {
  persistIdentityPoketraceCardId,
  poketraceNegativeCacheStillFresh,
} from "../persistence/identity-product-id.ts";

export interface IdentityForResolve {
  id: string;
  card_name: string;
  card_number: string | null;
  set_name: string;
  tcgplayer_product_id: string | null;
  poketrace_card_id: string | null;
  poketrace_card_id_resolved_at: string | null;
}

export interface ResolveDeps {
  supabase: SupabaseClient;
  client: PoketraceClientOptions;
  now: () => number;
  // Test seams (default to the real impls).
  findTcgProduct?: (sb: unknown, a: { groupId: number; cardNumber: string | null; cardName: string }) => Promise<TcgProductMatch | null>;
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

interface CardSearch { data: SearchCardLite[] }

export async function resolvePoketraceCard(
  deps: ResolveDeps,
  identity: IdentityForResolve,
): Promise<string | null> {
  const fetchImpl = deps.fetchJsonImpl ?? fetchJson;
  const findProduct = deps.findTcgProduct ?? findTcgProductByGroupAndCard;

  // 1. Positive cache hit.
  if (identity.poketrace_card_id && identity.poketrace_card_id !== "") {
    return identity.poketrace_card_id;
  }
  // 2. Negative cache fresh → skip.
  if (identity.poketrace_card_id === "" &&
      poketraceNegativeCacheStillFresh(identity.poketrace_card_id_resolved_at, deps.now())) {
    return null;
  }

  // 3. Tier A — alias → tcg_products → tcgplayer_ids cross-walk.
  //    Try a tcgplayer_product_id already on the identity first, then resolve
  //    a fresh product_id from the local tcg_products table.
  const productIds: string[] = [];
  if (identity.tcgplayer_product_id) productIds.push(identity.tcgplayer_product_id);
  const alias = aliasForPsaSet(identity.set_name);
  if (alias) {
    for (const gid of [alias.groupId, alias.altGroupId].filter((g): g is number => !!g)) {
      const product = await findProduct(deps.supabase, {
        groupId: gid, cardNumber: identity.card_number, cardName: identity.card_name,
      });
      if (product) { productIds.push(String(product.productId)); break; }
    }
  }
  for (const pid of productIds) {
    const res = await fetchImpl<CardSearch>(deps.client, `/cards?tcgplayer_ids=${encodeURIComponent(pid)}&limit=20`);
    if (res.status === 200 && res.body?.data?.length) {
      const uuid = res.body.data[0].id;
      await persistIdentityPoketraceCardId(deps.supabase, identity.id, uuid);
      return uuid;
    }
  }

  // 4. Tier B — native search by name (+ card number), scored.
  const searchPaths = [
    `/cards?search=${encodeURIComponent(identity.card_name)}${identity.card_number ? `&card_number=${encodeURIComponent(identity.card_number)}` : ""}&limit=20`,
    `/cards?search=${encodeURIComponent(identity.card_name)}&limit=20`,
  ];
  for (const path of searchPaths) {
    const res = await fetchImpl<CardSearch>(deps.client, path);
    if (res.status !== 200 || !res.body?.data?.length) continue;
    let best: { card: SearchCardLite; score: number } | null = null;
    for (const card of res.body.data) {
      const sc = scoreSearchCard(card, identity);
      if (sc.accept && (!best || sc.score > best.score)) best = { card, score: sc.score };
    }
    if (best) {
      await persistIdentityPoketraceCardId(deps.supabase, identity.id, best.card.id);
      return best.card.id;
    }
  }

  // 5. Total miss → negative sentinel.
  await persistIdentityPoketraceCardId(deps.supabase, identity.id, "");
  return null;
}
```

Note: `aliasForPsaSet` returns `{ groupId, altGroupId?, abbreviation? }` (see `lib/psa-aliases.ts`); confirm the `altGroupId` field name when implementing.

- [ ] **Step 4: Run, verify pass**

Run: `deno test supabase/functions/price-comp/__tests__/poketrace-resolve.test.ts`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/poketrace/resolve.ts supabase/functions/price-comp/__tests__/poketrace-resolve.test.ts
git commit -m "feat(price-comp): PPT-free poketrace resolver (Tier A cross-walk + Tier B search)"
```

### Task 2.4: `poketrace/listings.ts` — sold eBay comps

**Files:**
- Create: `supabase/functions/price-comp/poketrace/listings.ts`
- Test: `supabase/functions/price-comp/__tests__/poketrace-listings.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
import { assertEquals } from "https://deno.land/std/assert/mod.ts";
import { fetchPoketraceListings } from "../poketrace/listings.ts";

Deno.test("200 → parsed listings", async () => {
  const r = await fetchPoketraceListings(
    { apiKey: "k", baseUrl: "http://x" }, "uuid", "PSA", "10",
    { fetchJsonImpl: async () => ({ status: 200, body: { data: [
      { sourceItemId: "e1", title: "t", price: 100, soldAt: "2026-05-01T00:00:00Z",
        grader: "PSA", grade: "10", listingUrl: "u" } ] } }) },
  );
  assertEquals(r.status, 200);
  assertEquals(r.listings.length, 1);
});

Deno.test("403 UPGRADE_REQUIRED → empty, no throw", async () => {
  const r = await fetchPoketraceListings(
    { apiKey: "k", baseUrl: "http://x" }, "uuid", "PSA", "10",
    { fetchJsonImpl: async () => ({ status: 403, body: { code: "UPGRADE_REQUIRED" } }) },
  );
  assertEquals(r.status, 403);
  assertEquals(r.listings, []);
});
```

- [ ] **Step 2: Run, verify fail**

Run: `deno test supabase/functions/price-comp/__tests__/poketrace-listings.test.ts` → FAIL (module missing).

- [ ] **Step 3: Implement**

```ts
// supabase/functions/price-comp/poketrace/listings.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import { parseListings } from "./parse.ts";
import type { SoldListingWire } from "../types.ts";

export interface FetchListingsOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

export interface PoketraceListingsResult {
  status: number;
  listings: SoldListingWire[];
}

// Scale-plan endpoint. Graceful-degrades to [] on any non-200 (incl. 403
// UPGRADE_REQUIRED off lower plans) so it never blocks the price happy path.
export async function fetchPoketraceListings(
  client: PoketraceClientOptions,
  cardId: string,
  grader: string,
  grade: string,
  overrides: FetchListingsOverrides = {},
): Promise<PoketraceListingsResult> {
  const fetchImpl = overrides.fetchJsonImpl ?? fetchJson;
  const path =
    `/cards/${encodeURIComponent(cardId)}/listings` +
    `?grader=${encodeURIComponent(grader)}&grade=${encodeURIComponent(grade)}` +
    `&sort=sold_at_desc&limit=20`;
  const res = await fetchImpl<{ data?: unknown }>(client, path);
  if (res.status !== 200 || !res.body) return { status: res.status, listings: [] };
  return { status: 200, listings: parseListings(res.body) };
}
```
Note: `grader` is the grading service (PSA/BGS/CGC/SGC); Poketrace's `grader` enum excludes TAG — when `grading_service === "TAG"`, skip the listings call (return `{status:200, listings:[]}`) in the caller (Task 2.6 `index.ts`).

- [ ] **Step 4: Run, verify pass** → `deno test .../poketrace-listings.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/poketrace/listings.ts supabase/functions/price-comp/__tests__/poketrace-listings.test.ts
git commit -m "feat(price-comp): fetch sold eBay listings (graceful-degrade off Scale plan)"
```

### Task 2.5: `persistence/market.ts` — poketrace-only

**Files:**
- Modify: `supabase/functions/price-comp/persistence/market.ts`
- Test: `supabase/functions/price-comp/__tests__/market.test.ts` (create if absent)

- [ ] **Step 1: Rewrite `market.ts` to the poketrace-only shape**

Remove `MarketSource` PPT member, the `isPpt` branch, the PPT ladder write/read, `pptTCGPlayerId`/`pptUrl` params, and the `LadderPrices` import (it came from the deleted `ppt/parse.ts`). New shape:

```ts
// supabase/functions/price-comp/persistence/market.ts
// @ts-nocheck
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PriceHistoryWirePoint } from "../types.ts";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  headlinePriceCents: number | null;
  priceHistory: PriceHistoryWirePoint[];
  poketrace: {
    avgCents: number | null; lowCents: number | null; highCents: number | null;
    avg1dCents: number | null; avg7dCents: number | null; avg30dCents: number | null;
    median3dCents: number | null; median7dCents: number | null; median30dCents: number | null;
    trend: "up" | "down" | "stable" | null;
    confidence: "high" | "medium" | "low" | null;
    saleCount: number | null;
    tierPricesCents: Record<string, number>;
  };
}

const c2d = (c: number | null) => (c === null ? null : Math.round(c) / 100);
const d2c = (d: string | number | null) => {
  if (d === null || d === undefined) return null;
  const n = typeof d === "string" ? Number(d) : d;
  return Number.isFinite(n) ? Math.round(n * 100) : null;
};

export async function upsertMarketLadder(supabase: SupabaseClient, input: MarketUpsertInput): Promise<void> {
  const row = {
    identity_id: input.identityId,
    grading_service: input.gradingService,
    grade: input.grade,
    source: "poketrace",
    headline_price: c2d(input.headlinePriceCents),
    price_history: input.priceHistory,
    pt_avg: c2d(input.poketrace.avgCents),
    pt_low: c2d(input.poketrace.lowCents),
    pt_high: c2d(input.poketrace.highCents),
    pt_avg_1d: c2d(input.poketrace.avg1dCents),
    pt_avg_7d: c2d(input.poketrace.avg7dCents),
    pt_avg_30d: c2d(input.poketrace.avg30dCents),
    pt_median_3d: c2d(input.poketrace.median3dCents),
    pt_median_7d: c2d(input.poketrace.median7dCents),
    pt_median_30d: c2d(input.poketrace.median30dCents),
    pt_trend: input.poketrace.trend,
    pt_confidence: input.poketrace.confidence,
    pt_sale_count: input.poketrace.saleCount,
    pt_tier_prices_cents: input.poketrace.tierPricesCents,
    updated_at: new Date().toISOString(),
  };
  const { error } = await supabase.from("graded_market")
    .upsert(row, { onConflict: "identity_id,grading_service,grade,source" });
  if (error) throw new Error(`graded_market upsert: ${error.message}`);
}

export interface MarketReadResult {
  headlinePriceCents: number | null;
  priceHistory: PriceHistoryWirePoint[];
  updatedAt: string | null;
  poketrace: {
    avgCents: number | null; lowCents: number | null; highCents: number | null;
    avg1dCents: number | null; avg7dCents: number | null; avg30dCents: number | null;
    median3dCents: number | null; median7dCents: number | null; median30dCents: number | null;
    trend: "up" | "down" | "stable" | null;
    confidence: "high" | "medium" | "low" | null;
    saleCount: number | null;
    tierPricesCents: Record<string, number>;
  };
}

export async function readMarketLadder(
  supabase: SupabaseClient, identityId: string, gradingService: GradingService, grade: string,
): Promise<MarketReadResult | null> {
  const { data } = await supabase.from("graded_market")
    .select("headline_price, price_history, updated_at, pt_avg, pt_low, pt_high, " +
      "pt_avg_1d, pt_avg_7d, pt_avg_30d, pt_median_3d, pt_median_7d, pt_median_30d, " +
      "pt_trend, pt_confidence, pt_sale_count, pt_tier_prices_cents")
    .eq("identity_id", identityId).eq("grading_service", gradingService)
    .eq("grade", grade).eq("source", "poketrace").maybeSingle();
  if (!data) return null;
  const history = Array.isArray(data.price_history)
    ? (data.price_history as Array<{ ts?: unknown; price_cents?: unknown }>)
        .filter((p) => typeof p.ts === "string" && typeof p.price_cents === "number")
        .map((p) => ({ ts: p.ts as string, price_cents: p.price_cents as number }))
    : [];
  return {
    headlinePriceCents: d2c(data.headline_price),
    priceHistory: history,
    updatedAt: data.updated_at ?? null,
    poketrace: {
      avgCents: d2c(data.pt_avg), lowCents: d2c(data.pt_low), highCents: d2c(data.pt_high),
      avg1dCents: d2c(data.pt_avg_1d), avg7dCents: d2c(data.pt_avg_7d), avg30dCents: d2c(data.pt_avg_30d),
      median3dCents: d2c(data.pt_median_3d), median7dCents: d2c(data.pt_median_7d), median30dCents: d2c(data.pt_median_30d),
      trend: (data.pt_trend ?? null), confidence: (data.pt_confidence ?? null),
      saleCount: typeof data.pt_sale_count === "number" ? data.pt_sale_count : null,
      tierPricesCents: parseTierPricesCents(data.pt_tier_prices_cents),
    },
  };
}

function parseTierPricesCents(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const out: Record<string, number> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>))
    if (typeof v === "number" && Number.isFinite(v)) out[k] = Math.round(v);
  return out;
}
```

- [ ] **Step 2: Write a persistence test** (`market.test.ts`) asserting `upsertMarketLadder` writes a row with `source:'poketrace'` and `pt_avg` set, using a Supabase stub that captures the upserted row. Run → it should pass against the new impl.

Run: `deno test supabase/functions/price-comp/__tests__/market.test.ts`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/persistence/market.ts supabase/functions/price-comp/__tests__/market.test.ts
git commit -m "refactor(price-comp): poketrace-only market persistence"
```

### Task 2.6: `persistence/identity-product-id.ts` + new `persistence/sales.ts`

**Files:**
- Modify: `supabase/functions/price-comp/persistence/identity-product-id.ts`
- Create: `supabase/functions/price-comp/persistence/sales.ts`
- Test: `supabase/functions/price-comp/__tests__/sales.test.ts`

- [ ] **Step 1: Trim `identity-product-id.ts`**

Delete `persistIdentityPPTId` and `clearIdentityPPTId`. Keep `persistIdentityPoketraceCardId` and `poketraceNegativeCacheStillFresh` unchanged (they write `poketrace_card_id` / `poketrace_card_id_resolved_at`, not PPT columns). If any helper writes `ppt_tcgplayer_id`, repoint it to `tcgplayer_product_id`.

- [ ] **Step 2: Write failing test for `upsertSoldListings`**

```ts
// __tests__/sales.test.ts
import { assertEquals } from "https://deno.land/std/assert/mod.ts";
import { upsertSoldListings } from "../persistence/sales.ts";

Deno.test("upserts listings with identity + tier, dollars→numeric", async () => {
  let captured: any[] = [];
  const sb = { from: () => ({ upsert: async (rows: any[]) => { captured = rows; return { error: null }; } }) };
  await upsertSoldListings(sb as any, "id-1", "PSA", "10", [
    { source_listing_id: "e1", title: "t", price_cents: 12050, sold_at: "2026-05-01T00:00:00Z",
      grader: "PSA", grade: "10", condition: "Graded", url: "u", anomaly_flag: null },
  ]);
  assertEquals(captured.length, 1);
  assertEquals(captured[0].sold_price, 120.5);
  assertEquals(captured[0].identity_id, "id-1");
});

Deno.test("empty list is a no-op", async () => {
  let called = false;
  const sb = { from: () => ({ upsert: async () => { called = true; return { error: null }; } }) };
  await upsertSoldListings(sb as any, "id-1", "PSA", "10", []);
  assertEquals(called, false);
});
```

- [ ] **Step 3: Implement `sales.ts`**

```ts
// supabase/functions/price-comp/persistence/sales.ts
// @ts-nocheck
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, SoldListingWire } from "../types.ts";

export async function upsertSoldListings(
  supabase: SupabaseClient,
  identityId: string,
  gradingService: GradingService,
  grade: string,
  listings: SoldListingWire[],
): Promise<void> {
  if (listings.length === 0) return;
  const rows = listings.map((l) => ({
    identity_id: identityId,
    grading_service: gradingService,
    grade,
    source: "ebay",
    source_listing_id: l.source_listing_id,
    sold_price: l.price_cents === null ? 0 : Math.round(l.price_cents) / 100,
    sold_at: l.sold_at,
    title: l.title,
    url: l.url,
    grader: l.grader,
    condition: l.condition,
    anomaly_flag: l.anomaly_flag,
    captured_at: new Date().toISOString(),
  }));
  const { error } = await supabase.from("graded_market_sales")
    .upsert(rows, { onConflict: "source,source_listing_id" });
  if (error) throw new Error(`graded_market_sales upsert: ${error.message}`);
}
```

- [ ] **Step 4: Run tests** → `deno test .../sales.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/price-comp/persistence/identity-product-id.ts supabase/functions/price-comp/persistence/sales.ts supabase/functions/price-comp/__tests__/sales.test.ts
git commit -m "feat(price-comp): sold-listings persistence; drop PPT identity helpers"
```

### Task 2.7: Rewrite `index.ts` (handler flow)

**Files:**
- Modify: `supabase/functions/price-comp/index.ts`
- Test: `supabase/functions/price-comp/__tests__/index.test.ts` (rewrite)

- [ ] **Step 1: Rewrite `index.ts`**

Replace the whole file. New `HandleDeps` drops `pptBaseUrl`/`pptToken`/`ttlSeconds`-for-PPT; keeps `supabase`, `poketraceBaseUrl`, `poketraceApiKey`, `ttlSeconds`, `now`. New `handle`:

```ts
// supabase/functions/price-comp/index.ts
// @ts-nocheck — Deno runtime.
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PriceCompRequest, PriceCompResponse, CacheState, PoketraceBlock } from "./types.ts";
import { upsertMarketLadder, readMarketLadder } from "./persistence/market.ts";
import { upsertSoldListings } from "./persistence/sales.ts";
import { evaluateFreshness } from "./cache/freshness.ts";
import { resolvePoketraceCard } from "./poketrace/resolve.ts";
import { fetchPoketracePrices } from "./poketrace/prices.ts";
import { fetchPoketraceHistory } from "./poketrace/history.ts";
import { fetchPoketraceListings } from "./poketrace/listings.ts";
import { poketraceTierKey } from "./lib/poketrace-tier-key.ts";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
function env(name: string, fallback?: string): string {
  const v = Deno.env.get(name);
  if (v !== undefined && v !== "") return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`missing env: ${name}`);
}

export interface HandleDeps {
  supabase: SupabaseClient | unknown;
  poketraceBaseUrl: string;
  poketraceApiKey: string | null;
  ttlSeconds: number;
  now: () => number;
}

function blockToResponse(
  service: GradingService, grade: string,
  block: PoketraceBlock | null, soldListings: PriceCompResponse["sold_listings"],
  marketplaceUrl: string | null, cacheHit: boolean,
): PriceCompResponse {
  return {
    grading_service: service, grade,
    headline_price_cents: block?.avg_cents ?? null,
    poketrace: block,
    sold_listings: soldListings,
    marketplace_url: marketplaceUrl,
    fetched_at: new Date().toISOString(),
    cache_hit: cacheHit,
  };
}

export async function handle(req: Request, deps: HandleDeps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  let body: PriceCompRequest;
  try { body = (await req.json()) as PriceCompRequest; } catch { return json(400, { error: "invalid_json" }); }
  if (!body.graded_card_identity_id || !body.grading_service || !body.grade)
    return json(400, { error: "missing_fields" });

  const supabase = deps.supabase as SupabaseClient;

  // 1. Identity.
  const { data: identity, error: idErr } = await supabase
    .from("graded_card_identities").select("*").eq("id", body.graded_card_identity_id).single();
  if (idErr || !identity) return json(404, { code: "IDENTITY_NOT_FOUND" });

  // 2. Cache read + freshness.
  const cached = await readMarketLadder(supabase, body.graded_card_identity_id, body.grading_service, body.grade);
  const state: CacheState = evaluateFreshness({
    updatedAtMs: cached?.updatedAt ? Date.parse(cached.updatedAt) : null,
    nowMs: deps.now(), ttlSeconds: deps.ttlSeconds,
  });
  if (state === "hit" && cached) {
    const block = toBlock(cached, body.grading_service, body.grade, identity.poketrace_card_id ?? "");
    // Sold listings come from the table (no upstream call on cache hit).
    const sold = await readSold(supabase, body.graded_card_identity_id, body.grading_service, body.grade);
    return json(200, blockToResponse(body.grading_service, body.grade, block, sold, null, true));
  }

  if (!deps.poketraceApiKey) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  const client = { apiKey: deps.poketraceApiKey, baseUrl: deps.poketraceBaseUrl };

  // 3. Resolve UUID.
  const cardId = await resolvePoketraceCard(
    { supabase, client, now: deps.now },
    {
      id: identity.id, card_name: identity.card_name, card_number: identity.card_number ?? null,
      set_name: identity.set_name, tcgplayer_product_id: identity.tcgplayer_product_id ?? null,
      poketrace_card_id: identity.poketrace_card_id ?? null,
      poketrace_card_id_resolved_at: identity.poketrace_card_id_resolved_at ?? null,
    },
  );
  if (!cardId) return json(404, { code: "PRODUCT_NOT_RESOLVED" });

  // 4. Parallel fetch: prices + history + listings.
  const tierKey = poketraceTierKey(body.grading_service, body.grade);
  const grader = body.grading_service === "TAG" ? null : body.grading_service;
  const [pricesR, historyR, listingsR] = await Promise.allSettled([
    fetchPoketracePrices(client, cardId, tierKey),
    fetchPoketraceHistory(client, cardId, tierKey),
    grader ? fetchPoketraceListings(client, cardId, grader, body.grade) : Promise.resolve({ status: 200, listings: [] }),
  ]);
  const prices = pricesR.status === "fulfilled" ? pricesR.value : null;
  const history = historyR.status === "fulfilled" ? historyR.value.history : [];
  const sold = listingsR.status === "fulfilled" ? listingsR.value.listings : [];

  if (!prices || !prices.fields) {
    // No graded tier data. Still persist any listings we got, then 404.
    if (sold.length) { try { await upsertSoldListings(supabase, body.graded_card_identity_id, body.grading_service, body.grade, sold); } catch {} }
    if (sold.length === 0) return json(404, { code: "NO_MARKET_DATA" });
  }

  const block: PoketraceBlock | null = prices?.fields ? {
    card_id: cardId, tier: tierKey, ...prices.fields,
    tier_prices_cents: prices.ladderCents, price_history: history, fetched_at: new Date().toISOString(),
  } : null;

  // 5. Persist market + listings.
  if (block) {
    try { await upsertMarketLadder(supabase, {
      identityId: body.graded_card_identity_id, gradingService: body.grading_service, grade: body.grade,
      headlinePriceCents: block.avg_cents, priceHistory: history,
      poketrace: {
        avgCents: block.avg_cents, lowCents: block.low_cents, highCents: block.high_cents,
        avg1dCents: block.avg_1d_cents, avg7dCents: block.avg_7d_cents, avg30dCents: block.avg_30d_cents,
        median3dCents: block.median_3d_cents, median7dCents: block.median_7d_cents, median30dCents: block.median_30d_cents,
        trend: block.trend, confidence: block.confidence, saleCount: block.sale_count,
        tierPricesCents: block.tier_prices_cents,
      },
    }); } catch (e) { console.error("poketrace.persist_failed", { message: String(e) }); }
  }
  if (sold.length) { try { await upsertSoldListings(supabase, body.graded_card_identity_id, body.grading_service, body.grade, sold); } catch (e) { console.error("sales.persist_failed", { message: String(e) }); } }

  return json(200, blockToResponse(body.grading_service, body.grade, block, sold, null, false));
}

// Helper: rebuild a PoketraceBlock from a cached MarketReadResult.
function toBlock(cached, service, grade, cardId): PoketraceBlock {
  const p = cached.poketrace;
  return {
    card_id: cardId, tier: poketraceTierKey(service, grade),
    avg_cents: p.avgCents, low_cents: p.lowCents, high_cents: p.highCents,
    avg_1d_cents: p.avg1dCents, avg_7d_cents: p.avg7dCents, avg_30d_cents: p.avg30dCents,
    median_3d_cents: p.median3dCents, median_7d_cents: p.median7dCents, median_30d_cents: p.median30dCents,
    trend: p.trend, confidence: p.confidence, sale_count: p.saleCount,
    tier_prices_cents: p.tierPricesCents, price_history: cached.priceHistory,
    fetched_at: cached.updatedAt ?? new Date().toISOString(),
  };
}

// Helper: read cached sold listings for the cache-hit path.
async function readSold(supabase: SupabaseClient, identityId, service, grade) {
  const { data } = await supabase.from("graded_market_sales")
    .select("source_listing_id, title, sold_price, sold_at, grader, grade, condition, url, anomaly_flag")
    .eq("identity_id", identityId).eq("grading_service", service).eq("grade", grade)
    .order("sold_at", { ascending: false }).limit(20);
  return (data ?? []).map((r) => ({
    source_listing_id: r.source_listing_id, title: r.title,
    price_cents: r.sold_price === null ? null : Math.round(Number(r.sold_price) * 100),
    sold_at: typeof r.sold_at === "string" ? r.sold_at : new Date(r.sold_at).toISOString(),
    grader: r.grader, grade: r.grade, condition: r.condition, url: r.url, anomaly_flag: r.anomaly_flag,
  }));
}

Deno.serve(async (req) => {
  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
  const poketraceApiKey = (() => { try { return env("POKETRACE_API_KEY"); } catch { return null; } })();
  if (!poketraceApiKey) console.warn("price-comp.poketrace_disabled", { reason: "POKETRACE_API_KEY not set" });
  return await handle(req, {
    supabase,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey,
    ttlSeconds: Number(env("POKETRACE_FRESHNESS_TTL_SECONDS", "86400")),
    now: () => Date.now(),
  });
});
```

- [ ] **Step 2: Rewrite `index.test.ts`**

Replace PPT-era cases with: (a) `IDENTITY_NOT_FOUND` on missing identity; (b) cache-hit returns `cache_hit:true` with the poketrace block + cached sold listings, no upstream call; (c) cold path resolves → fetches → returns `poketrace` block + `sold_listings`; (d) resolver miss → `404 PRODUCT_NOT_RESOLVED`; (e) prices present but listings 403 → block present, `sold_listings:[]`. Inject `deps` with stubbed supabase + a fake `fetchJsonImpl` via the module seams. Use the existing `index.test.ts` Supabase-stub scaffolding as a base.

Run: `deno test supabase/functions/price-comp/__tests__/index.test.ts`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/index.ts supabase/functions/price-comp/__tests__/index.test.ts
git commit -m "refactor(price-comp): poketrace-only handler with sold listings (v3 contract)"
```

### Task 2.8: Delete the PPT layer + dead tests/fixtures

**Files (delete):**
- `supabase/functions/price-comp/ppt/` (whole dir: `cards.ts, client.ts, match.ts, parse.ts`)
- `supabase/functions/price-comp/__fixtures__/ppt/` (whole dir)
- `supabase/functions/price-comp/poketrace/match.ts` (superseded by `resolve.ts`)
- PPT tests: `__tests__/index-fanout.test.ts, match.test.ts, match-property.test.ts, parse.test.ts, cards.test.ts, client.test.ts, regression.test.ts, poketrace-match.test.ts, poketrace-client.test.ts` (audit each — delete those that import the deleted modules; keep `poketrace-tier-key.test.ts`, `grade-key.test.ts`, `psa-aliases.test.ts`, `tcg-products*.test.ts`).

- [ ] **Step 1: Delete the files**

```bash
cd supabase/functions/price-comp
git rm -r ppt __fixtures__/ppt poketrace/match.ts
git rm __tests__/index-fanout.test.ts __tests__/match.test.ts __tests__/match-property.test.ts \
       __tests__/parse.test.ts __tests__/cards.test.ts __tests__/client.test.ts \
       __tests__/poketrace-match.test.ts
```
Then check the remaining `__tests__/*` and `__tests__/regression.test.ts` / `poketrace-client.test.ts` / `poketrace-parse.test.ts` for imports of deleted modules and either delete or repoint them. `parsePriceHistory`/`priceHistoryForTier`/`PriceHistoryPoint` lived in `ppt/parse.ts` — `PriceHistoryPoint` is imported by `poketrace/history.ts` and `poketrace/parse.ts`. **Move `PriceHistoryPoint` and `parseHistoryResponse`'s point type into `poketrace/parse.ts`** (or `types.ts`) and repoint those imports.

- [ ] **Step 2: Fix dangling imports**

```bash
grep -rn "ppt/\|poketrace/match\|PPTCard\|ReconciledBlock\|PriceCompResponseV2" supabase/functions/price-comp --include=*.ts | grep -v __tests__
```
Expected after fixes: no output. Repoint any `import { PriceHistoryPoint } from "../ppt/parse.ts"` → the new home.

- [ ] **Step 3: Full type + test pass**

Run: `deno check supabase/functions/price-comp/index.ts` then `deno test supabase/functions/price-comp/`
Expected: type check PASS; all remaining tests PASS.

- [ ] **Step 4: Commit**

```bash
git add -A supabase/functions/price-comp
git commit -m "chore(price-comp): delete PPT layer, fixtures, and dead tests"
```

### Task 2.9: Deploy + live smoke

- [ ] **Step 1: Unset the PPT secret, confirm Poketrace key is Scale-tier**

```bash
supabase secrets unset POKEMONPRICETRACKER_API_TOKEN POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS
supabase secrets set POKETRACE_FRESHNESS_TTL_SECONDS=86400
supabase secrets list   # expect POKETRACE_API_KEY present; no POKEMONPRICETRACKER_*
```

- [ ] **Step 2: Deploy**

Run: `supabase functions deploy price-comp`
Expected: deploy succeeds.

- [ ] **Step 3: Live curl smoke** (pick a known identity id from the DB)

```bash
curl -s -X POST "$SUPABASE_URL/functions/v1/price-comp" \
  -H "authorization: Bearer $SUPABASE_PUBLISHABLE_KEY" -H "content-type: application/json" \
  -d '{"graded_card_identity_id":"<known-uuid>","grading_service":"PSA","grade":"10"}' | jq .
```
Expected: 200 with `poketrace` block, `sold_listings` array (populated if on Scale; `[]` otherwise), no `ppt_*` keys, no `reconciled`. Note: curl only confirms shape coarsely — the authoritative check is the iOS live decode in Task 3.7.

- [ ] **Step 4: Commit** (no code change; this is a verification gate — record results in the PR description).

---

## Phase 3 — iOS

Invoke `swiftui-expert-skill` and pass its rules into any subagent doing view work (CLAUDE.md). Build command:
`xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`

### Task 3.1: `GradedMarketSnapshot` model + `SoldListing`

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift`
- Create: `ios/slabbist/slabbist/Core/Models/SoldListing.swift`

- [ ] **Step 1: Add `SoldListing` value type**

```swift
// ios/slabbist/slabbist/Core/Models/SoldListing.swift
import Foundation

/// One individual sold eBay comp surfaced from Poketrace's listings endpoint.
struct SoldListing: Codable, Identifiable, Equatable {
    var id: String { sourceListingId }
    let sourceListingId: String
    let title: String?
    let priceCents: Int64?
    let soldAt: Date
    let grader: String?
    let grade: String?
    let condition: String?
    let url: URL?
    let anomalyFlag: String?
}
```

- [ ] **Step 2: Strip PPT from `GradedMarketSnapshot`, add sold listings + marketplace URL**

In `GradedMarketSnapshot.swift`: remove `loosePriceCents, psa7..psa10, bgs10, cgc10, sgc10PriceCents, pptTCGPlayerId, pptURL` stored props + their init params + assignments. Change the `source` default from `"pokemonpricetracker"` to `"poketrace"` (update the migration-backfill comment accordingly). Add:

```swift
var marketplaceURL: URL?
/// JSON-encoded [SoldListing]; decoded on demand. Same blob convention as priceHistoryJSON.
var soldListingsJSON: String?
```
Add init params (defaulted) + assignments for both. Add a computed accessor:

```swift
var soldListings: [SoldListing] {
    guard let json = soldListingsJSON, let data = json.data(using: .utf8) else { return [] }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([SoldListing].self, from: data)) ?? []
}
```
Remove `static let sourcePPT`; keep `static let sourcePoketrace = "poketrace"`.

> **SwiftData migration note:** removing stored properties is a destructive lightweight-migration change. Confirm `ModelContainer.swift`'s catch-init-failure path handles a store reset, and that the `source` default still backfills cleanly. Since the app is pre-release, a store reset on upgrade is acceptable — verify on a clean simulator install.

- [ ] **Step 3: Build** → must compile after CompFetchService/CompRepository updates (Tasks 3.2–3.3). Defer the build check to Task 3.3 Step 4 since these are interdependent.

- [ ] **Step 4: Commit**

```bash
git add ios/slabbist/slabbist/Core/Models/GradedMarketSnapshot.swift ios/slabbist/slabbist/Core/Models/SoldListing.swift
git commit -m "feat(ios): poketrace-only snapshot model + SoldListing"
```

### Task 3.2: `CompRepository` v3 decode

**Files:**
- Modify: `ios/slabbist/slabbist/Core/Data/Repositories/CompRepository.swift`
- Test: `ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift`

- [ ] **Step 1: Replace `Wire` / `Decoded` with v3**

`Wire`: drop the PPT fields (`headline ladder, ppt_*, is_stale_fallback, reconciled`), keep `grading_service, grade, fetched_at, cache_hit`, add `headline_price_cents: Int64?`, `poketrace: PoketraceWire?` (unchanged inner shape minus nothing), `sold_listings: [SoldListingWire]`, `marketplace_url: String?`. Add:

```swift
struct SoldListingWire: Decodable {
    let source_listing_id: String
    let title: String?
    let price_cents: Int64?
    let sold_at: Date
    let grader: String?
    let grade: String?
    let condition: String?
    let url: String?
    let anomaly_flag: String?
}
```
`Decoded`: drop PPT ladder + `pptTCGPlayerId/pptURL/isStaleFallback/reconciled*`. Keep `poketrace: SourceComp?`. Add `headlinePriceCents: Int64?`, `marketplaceURL: URL?`, `soldListings: [SoldListing]`. Update `decode(data:)` to map the new wire → `Decoded`, mapping each `SoldListingWire` → `SoldListing` and `URL(string:)` for urls. Remove the `reconciled` fallback logic.

`decodeErrorBody`: keep the `code` switch but drop `AUTH_INVALID`/`is_stale` cases that no longer occur; keep `NO_MARKET_DATA`, `PRODUCT_NOT_RESOLVED`, `IDENTITY_NOT_FOUND`, `UPSTREAM_UNAVAILABLE`. Remove `.authInvalid` from the `Error` enum (and its `classify` case in Task 3.3).

- [ ] **Step 2: Update tests**

Rewrite `CompRepositoryTests.swift`: feed a v3 JSON fixture (poketrace block + 2 sold_listings + marketplace_url) → assert `decoded.poketrace?.avgCents`, `decoded.soldListings.count == 2`, `decoded.headlinePriceCents`. Add a fixture with `poketrace: null, sold_listings: []` → assert empties. Remove PPT-ladder assertions.

Run (after 3.3 compiles): `xcodebuild ... test -only-testing:slabbistTests/CompRepositoryTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist/Core/Data/Repositories/CompRepository.swift ios/slabbist/slabbistTests/Features/Comp/CompRepositoryTests.swift
git commit -m "feat(ios): decode v3 comp contract (poketrace + sold listings)"
```

### Task 3.3: `CompFetchService` persist + classify

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompFetchService.swift`
- Test: `ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift`, `CompFetchE2ETests.swift`

- [ ] **Step 1: Rewrite `persistSnapshots`**

Drop the PPT snapshot insert entirely. Insert a single `source: .sourcePoketrace` snapshot built from `decoded.poketrace` (+ `headlinePriceCents = decoded.headlinePriceCents`, `marketplaceURL = decoded.marketplaceURL`, `soldListingsJSON = encodeSoldListings(decoded.soldListings)`). Mirror `decoded.headlinePriceCents` onto `scan.reconciledHeadlinePriceCents` (keep the field name; it's the scan's hero number) and set `scan.reconciledSource = "poketrace"`. Add an `encodeSoldListings([SoldListing]) -> String?` helper (ISO8601 encoder, nil for empty). When `decoded.poketrace == nil` but `soldListings` exist, still insert a snapshot (headline nil) so the sold list renders.

- [ ] **Step 2: Update `classify`**

Reword PPT-named messages → Poketrace: `.noMarketData` → "Poketrace has no comp for this slab yet."; `.productNotResolved` → "We couldn't find this card on Poketrace."; `.upstreamUnavailable` → "Poketrace lookup unavailable — try again."; keep `.identityNotFound`, `.httpStatus`, `.decoding`. Remove the `.authInvalid` case.

- [ ] **Step 3: Update tests** — `CompFetchServiceTests` / `CompFetchE2ETests`: replace dual-snapshot assertions with single poketrace snapshot + sold-listings persistence; update the `Decoded` fixtures to v3. Keep the sibling-scan / in-flight absorption tests (they don't depend on PPT).

- [ ] **Step 4: Build + run Comp tests**

Run: `xcodebuild -project ios/slabbist/slabbist.xcodeproj -scheme slabbist -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
Expected: BUILD SUCCEEDED.
Run: `xcodebuild ... test -only-testing:slabbistTests/CompFetchServiceTests -only-testing:slabbistTests/CompRepositoryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompFetchService.swift ios/slabbist/slabbistTests/Features/Comp/CompFetchServiceTests.swift ios/slabbist/slabbistTests/Features/Comp/CompFetchE2ETests.swift
git commit -m "feat(ios): persist poketrace snapshot + sold listings; reword comp errors"
```

### Task 3.4: `CompCardView` — drop toggle, add sold-comps section

**Files:**
- Modify: `ios/slabbist/slabbist/Features/Comp/CompCardView.swift`
- Create: `ios/slabbist/slabbist/Features/Comp/CompSoldListingsView.swift`
- Test: `ios/slabbist/slabbistTests/Features/Comp/CompCardViewTests.swift`, `CompCardViewSnapshotTests.swift`

- [ ] **Step 1: Remove the PPT/Poketrace source toggle + PPT ladder**

In `CompCardView.swift`: delete any `@State` source-toggle and the branch that reads PPT ladder fields. The ladder now always reads `snapshot.ptTierPricesCents` (the poketrace map). Render aggregates from the `pt*` fields (saleCount, trend, confidence, medians). Keep the sparkline reading `snapshot.priceHistory`.

- [ ] **Step 2: Build `CompSoldListingsView`** (invoke `swiftui-expert-skill`)

A section that takes `[SoldListing]` and a `marketplaceURL: URL?`:
- Header "Recent eBay sales" + count.
- For each listing (cap ~10 shown): row with title (truncated), grade chip, price (formatted from `priceCents`), relative sold date; tap opens `url` via `Link`/`openURL`. Dim/annotate rows where `anomalyFlag != nil`.
- Footer: "View all sold on eBay" `Link` to `marketplaceURL` when present.
- Empty state: when `soldListings.isEmpty`, show a compact "No individual sales available" line (this is the non-Scale-plan degrade path) — do NOT show a spinner.
Follow `.impeccable.md` tokens (dark+gold, 4pt spacing, mono for prices). Embed it in `CompCardView` below the ladder/aggregates.

- [ ] **Step 3: Update unit + snapshot tests**

`CompCardViewTests`: drop toggle assertions; assert ladder reads poketrace map; assert sold-listings section renders N rows and the empty state. `CompCardViewSnapshotTests`: replace PPT-source snapshot cases with poketrace + sold-listings cases (with-listings, empty-listings). Regenerate snapshots:

Run once to record, then commit the new PNGs:
`xcodebuild ... test -only-testing:slabbistTests/CompCardViewSnapshotTests` (set record mode per the existing snapshot harness, then turn it off and re-run to confirm pass).
Expected: PASS after regeneration. Delete the stale `*.2.png` artifacts currently untracked in the repo if they no longer correspond to a test.

- [ ] **Step 4: Build + test**

Run: `xcodebuild ... build` → SUCCEEDED; `xcodebuild ... test -only-testing:slabbistTests/CompCardViewTests -only-testing:slabbistTests/CompCardViewSnapshotTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/slabbist/slabbist/Features/Comp/CompCardView.swift ios/slabbist/slabbist/Features/Comp/CompSoldListingsView.swift ios/slabbist/slabbistTests/Features/Comp/
git commit -m "feat(ios): sold-comps section; drop source toggle + PPT ladder"
```

### Task 3.5: Clean remaining iOS PPT references

**Files:** `Scan.swift`, `ScanDetailView.swift`, `ScanRowTrailingState.swift`, `Core/Persistence/Outbox/OutboxPayloads.swift`, `Core/Config/UITestEnvironment.swift`.

- [ ] **Step 1: Find and remove each PPT reference**

```bash
grep -rn "ppt\|Ppt\|PPT\|pokemonpricetracker\|Pokemon Price Tracker" ios/slabbist/slabbist
```
For each hit: if it's a stored value or label tied to the removed PPT source/ladder, delete it; if it's a comment/string mentioning "Pokemon Price Tracker", reword to "Poketrace". `Scan.swift` (2 refs) likely a comment + the `reconciledSource` doc — reword. `ScanDetailView.swift` (7 refs) likely caption strings — reword to Poketrace and ensure it reads the poketrace snapshot. `UITestEnvironment.swift` (1) — if it seeds a PPT snapshot for UI tests, switch to a poketrace snapshot.

- [ ] **Step 2: Build**

Run: `xcodebuild ... build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add ios/slabbist/slabbist
git commit -m "chore(ios): purge remaining PokemonPriceTracker references"
```

### Task 3.6: Live decode round-trip (the authoritative cutover gate)

- [ ] **Step 1: Add a live decode test** (or a one-off harness) that POSTs to the deployed `price-comp` for a real identity and runs the bytes through `CompRepository.decode(data:)`.

Per the repo rule ([[feedback_live_decode_round_trip]]), curl smoke is insufficient. Add `CompFetchE2ETests` case gated behind an env flag (so CI without network skips it) that hits the deployed function and asserts `decode` succeeds and yields a non-nil `poketrace` (for a known-good slab) and a `soldListings` array.

Run: `LIVE_COMP=1 xcodebuild ... test -only-testing:slabbistTests/CompFetchE2ETests/testLiveDecodeRoundTrip`
Expected: PASS — no `Error.decoding`.

- [ ] **Step 2: Commit**

```bash
git add ios/slabbist/slabbistTests/Features/Comp/CompFetchE2ETests.swift
git commit -m "test(ios): live v3 decode round-trip against deployed price-comp"
```

---

## Phase 4 — Cleanup & verification

### Task 4.1: Scraper + scripts

**Files:** `scripts/probe-resolver.ts`, `scraper/src/shared/config.ts`, `scraper/src/cli.ts`.

- [ ] **Step 1: Audit scraper for PPT**

```bash
grep -rn "pokemonpricetracker\|PokemonPriceTracker\|POKEMONPRICETRACKER\|\bppt\b" scraper scripts
```
- `scripts/probe-resolver.ts` probes the PPT resolver → **delete** it (`git rm scripts/probe-resolver.ts`) unless it can be cheaply repointed at `poketrace/resolve.ts`; deletion is fine (it's a dev probe).
- `scraper/src/shared/config.ts` / `cli.ts`: the grep earlier showed only `POKETRACE_*` config — confirm no `POKEMONPRICETRACKER_*` remains. If a PPT config block exists, remove it.

- [ ] **Step 2: Scraper typecheck + test**

Run: `cd scraper && bun run typecheck && bun run test`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add -A scraper scripts
git commit -m "chore(scraper): remove PPT resolver probe / config"
```

### Task 4.2: Env, secrets, docs, memory

**Files:** `.envrc`, `CLAUDE.md` (if it names PPT envs), `.claude/skills/slabbist-product/references/{glossary,value-loops}.md`, superseded specs/plans.

- [ ] **Step 1: Remove PPT env from `.envrc`**

If `.envrc` exports `POKEMONPRICETRACKER_API_TOKEN`, remove the line; run `direnv allow`. (The earlier check showed it set in the environment — confirm where it originates and remove.)

- [ ] **Step 2: Update product-skill references**

```bash
grep -rln "pokemonpricetracker\|Pokemon Price Tracker\|PPT" .claude/skills/slabbist-product docs/superpowers
```
Reword `glossary.md` / `value-loops.md` PPT mentions to Poketrace. Add a one-line "Superseded by 2026-06-04-poketrace-only-comp-design.md" banner to the two PPT specs/plans (do not delete historical docs).

- [ ] **Step 3: Commit**

```bash
git add -A .envrc .claude docs
git commit -m "docs: mark PPT specs superseded; reword product skill + remove PPT env"
```

### Task 4.3: Repo-wide gate

- [ ] **Step 1: Confirm zero live PPT references**

```bash
grep -rin "pokemonpricetracker\|pokemon price tracker" . \
  --include=*.swift --include=*.ts --include=*.tsx --include=*.sql --include=*.json \
  | grep -v node_modules | grep -v '/docs/superpowers/' | grep -v '2026-06-04-'
```
Expected: **no output** (only the superseded dated docs may legitimately still name it, hence the `docs/superpowers/` exclusion). Audit any remaining hits.

```bash
grep -rin "\bppt\b" . --include=*.swift --include=*.ts --include=*.sql | grep -v node_modules | grep -v '/docs/'
```
Expected: no output (or only unrelated acronyms — inspect each).

- [ ] **Step 2: Full suites**

Run: `deno test supabase/functions/price-comp/` → PASS.
Run: `xcodebuild ... test -only-testing:slabbistTests` (at least the Comp suites) → PASS.
Run: `cd scraper && bun run test` → PASS.

- [ ] **Step 3: Finish the branch**

Use `superpowers:finishing-a-development-branch` to open the PR. PR description must record: the live curl smoke result (Task 2.9), the live decode round-trip result (Task 3.6), the Poketrace plan tier in use (whether sold listings are live or degraded), and the breaking-cutover note.

---

## Self-review notes (for the executor)

- **Spec coverage:** Edge rework (Tasks 2.1–2.9) ✓; DB drop+rename+sales recreate (1.2) ✓; resolution Tier A+B (2.3) ✓; sold listings build + graceful-degrade (2.4, 3.4) ✓; iOS decode/UI (3.1–3.4) ✓; ref cleanup (3.5, 4.1–4.3) ✓; RLS test (1.3) ✓; live decode round-trip (3.6) ✓.
- **Known seams to verify at implementation time** (don't assume — read the file): `aliasForPsaSet`'s exact return field for the alt group id; `poketraceTierKey` signature; `evaluateFreshness` arg shape; `fetchJson`/`PoketraceClientOptions` exact exports in `poketrace/client.ts`; `fetchPoketracePrices` return (`{ status, fields, ladderCents }`); the snapshot-test record-mode toggle; `ModelContainer.swift` reset path.
- **Ordering constraint:** Phase 2 must land + deploy before Phase 3's live decode (3.6). DB (Phase 1) must land before edge deploy (2.9).
