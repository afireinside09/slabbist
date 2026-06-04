// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// index.test.ts — poketrace-only handler tests (v3 contract).
//
// Cases:
//  (a) IDENTITY_NOT_FOUND when identity row is missing
//  (b) cache-hit returns cache_hit:true with poketrace block + cached sold listings,
//      NO upstream fetch calls
//  (c) cold path: resolver returns UUID → prices+history+listings fetched → v3 response
//  (d) resolver returns null → 404 PRODUCT_NOT_RESOLVED
//  (e) prices present, listings 403 → block present, sold_listings:[]
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handle } from "../index.ts";

// ─── Supabase stub factory ────────────────────────────────────────────────────
//
// Tracks tables: graded_card_identities, graded_market, graded_market_sales.
// Supports the query chains index.ts uses: select+eq+single / eq+maybeSingle /
// eq+order+limit / upsert. The eq() builder chain accumulates filters then
// applies them all at read time.

function fakeSupabase(opts: {
  identity?: Record<string, unknown> | null;
  market?: Record<string, unknown> | null;
  sales?: Record<string, unknown>[];
}) {
  const market = opts.market ? { ...opts.market } : null;
  const sales: Record<string, unknown>[] = opts.sales ? [...opts.sales] : [];
  let upsertedMarket: Record<string, unknown> | null = null;
  let upsertedSales: Record<string, unknown>[] = [];

  return {
    _upsertedMarket: () => upsertedMarket,
    _upsertedSales: () => upsertedSales,
    from(table: string) {
      if (table === "graded_card_identities") {
        const identity = opts.identity === undefined ? null : opts.identity;
        let pendingUpdate: Record<string, unknown> | null = null;
        const builder: any = {
          select() { return builder; },
          eq(_col: string, _val: unknown) { return builder; },
          single: async () => {
            if (!identity) return { data: null, error: { message: "not found" } };
            return { data: { ...identity }, error: null };
          },
          update(patch: Record<string, unknown>) {
            pendingUpdate = patch;
            return {
              eq(_col: string, _val: unknown) {
                if (identity && pendingUpdate) Object.assign(identity, pendingUpdate);
                return { error: null };
              },
            };
          },
        };
        return builder;
      }

      if (table === "graded_market") {
        return {
          select(_cols: string) { return this; },
          eq(_col: string, _val: unknown) { return this; },
          maybeSingle: async () => ({ data: market, error: null }),
          upsert(row: Record<string, unknown>, _opts: unknown) {
            upsertedMarket = row;
            return Promise.resolve({ error: null });
          },
        };
      }

      if (table === "graded_market_sales") {
        const builder: any = {
          select(_cols: string) { return builder; },
          eq(_col: string, _val: unknown) { return builder; },
          order(_col: string, _opts: unknown) { return builder; },
          limit(_n: number) {
            return Promise.resolve({ data: [...sales], error: null });
          },
          upsert(rows: Record<string, unknown>[], _opts: unknown) {
            upsertedSales = [...rows];
            return Promise.resolve({ error: null });
          },
        };
        return builder;
      }

      if (table === "tcg_products") {
        // Resolve requests come through here for Tier A; return empty so
        // the stub falls through to Tier B search.
        const b: any = {
          select() { return b; },
          eq() { return b; },
          or() { return b; },
          limit(_n: number) { return Promise.resolve({ data: [], error: null }); },
        };
        return b;
      }

      throw new Error(`unexpected table: ${table}`);
    },
  };
}

// ─── Shared identity fixture ──────────────────────────────────────────────────

const baseIdentity = {
  id: "id-1",
  card_name: "Charizard",
  card_number: "4",
  set_name: "Base Set",
  tcgplayer_product_id: null,
  poketrace_card_id: null,
  poketrace_card_id_resolved_at: null,
};

// A fully-populated cached market row (for the cache-hit test).
const cachedMarketRow = {
  identity_id: "id-1",
  grading_service: "PSA",
  grade: "10",
  source: "poketrace",
  headline_price: 185.0,
  price_history: [{ ts: "2026-05-01T00:00:00Z", price_cents: 18500 }],
  updated_at: new Date().toISOString(), // fresh — within TTL
  pt_avg: 185.0,
  pt_low: 120.0,
  pt_high: 250.0,
  pt_avg_1d: null,
  pt_avg_7d: 190.0,
  pt_avg_30d: 180.0,
  pt_median_3d: null,
  pt_median_7d: 188.0,
  pt_median_30d: 175.0,
  pt_trend: "up",
  pt_confidence: "high",
  pt_sale_count: 42,
  pt_tier_prices_cents: { PSA_10: 18500, PSA_9: 9000 },
};

function makeRequest(body: object): Request {
  return new Request("http://localhost/price-comp", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

// ─── (a) IDENTITY_NOT_FOUND ───────────────────────────────────────────────────

Deno.test("(a) IDENTITY_NOT_FOUND when identity row is missing", async () => {
  const fake = fakeSupabase({ identity: null });
  const req = makeRequest({
    graded_card_identity_id: "missing",
    grading_service: "PSA",
    grade: "10",
  });
  const res = await handle(req, {
    supabase: fake,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: "key",
    ttlSeconds: 86400,
    now: () => Date.now(),
  });
  const body = await res.json();
  assertEquals(res.status, 404);
  assertEquals(body.code, "IDENTITY_NOT_FOUND");
});

// ─── (b) cache-hit: returns cache_hit:true, poketrace block + cached sold listings, no upstream call ───

Deno.test("(b) cache-hit returns cache_hit:true with block + sold listings, zero upstream fetches", async () => {
  const cachedSales = [
    {
      source_listing_id: "e1",
      title: "Charizard PSA 10",
      sold_price: 185.0,
      sold_at: "2026-05-01T00:00:00Z",
      grader: "PSA",
      grade: "10",
      condition: "Graded",
      url: "http://ebay/e1",
      anomaly_flag: null,
    },
  ];
  const identity = { ...baseIdentity, poketrace_card_id: "pt-uuid-1" };
  const fake = fakeSupabase({
    identity,
    market: { ...cachedMarketRow },
    sales: cachedSales,
  });

  let fetchCalls = 0;
  // Override global fetch to detect any upstream HTTP calls.
  const origFetch = globalThis.fetch;
  globalThis.fetch = () => { fetchCalls++; return Promise.reject(new Error("should not call fetch on cache hit")); };

  try {
    const req = makeRequest({
      graded_card_identity_id: "id-1",
      grading_service: "PSA",
      grade: "10",
    });
    const res = await handle(req, {
      supabase: fake,
      poketraceBaseUrl: "https://api.poketrace.com/v1",
      poketraceApiKey: "key",
      ttlSeconds: 86400,
      now: () => Date.now(),
    });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.cache_hit, true);
    assert(body.poketrace !== null, "expected poketrace block");
    assertEquals(body.poketrace.avg_cents, 18500);
    assertEquals(body.poketrace.sale_count, 42);
    assertEquals(body.poketrace.trend, "up");
    assertEquals(body.sold_listings.length, 1);
    assertEquals(body.sold_listings[0].source_listing_id, "e1");
    assertEquals(body.sold_listings[0].price_cents, 18500);
    assertEquals(fetchCalls, 0, "no upstream HTTP calls on cache hit");
  } finally {
    globalThis.fetch = origFetch;
  }
});

// ─── (c) cold path: resolver → prices + history + listings → v3 response ─────

Deno.test("(c) cold path: resolve UUID → fetch prices+history+listings → v3 block + sold_listings", async () => {
  const identity = { ...baseIdentity };
  const fake = fakeSupabase({ identity, market: null, sales: [] });

  // Inject fetchImpl into HandleDeps so all Poketrace HTTP goes through this stub
  // without needing a real network server.
  const fetchedUrls: string[] = [];
  const stubFetch: typeof fetch = (input, _init) => {
    const url = typeof input === "string" ? input : (input as Request).url;
    fetchedUrls.push(url);
    const u = new URL(url);

    // /cards?search= (resolve Tier B)
    if (u.pathname.endsWith("/cards") && u.searchParams.get("search")) {
      return Promise.resolve(new Response(JSON.stringify({
        data: [
          { id: "pt-uuid-cold", name: "Charizard", cardNumber: "4/102", set: { name: "Base Set" } },
        ],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    // /cards/{id}/prices/{tier}/history
    if (u.pathname.includes("/prices/") && u.pathname.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify({
        data: [{ date: "2026-05-01", avg: 185.0 }],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    // /cards/{id}/listings
    if (u.pathname.includes("/listings")) {
      return Promise.resolve(new Response(JSON.stringify({
        data: [
          {
            sourceItemId: "e1",
            title: "Charizard PSA 10",
            price: 185.0,
            soldAt: "2026-05-01T00:00:00Z",
            grader: "PSA",
            grade: "10",
            listingUrl: "http://ebay/e1",
            condition: "Graded",
            anomalyFlag: null,
          },
        ],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    // /cards/{id} (prices endpoint — card detail)
    if (u.pathname.match(/\/cards\/[^/]+$/)) {
      return Promise.resolve(new Response(JSON.stringify({
        data: {
          id: "pt-uuid-cold",
          prices: {
            ebay: {
              PSA_10: {
                avg: 185.0, low: 120.0, high: 250.0,
                avg1d: null, avg7d: 190.0, avg30d: 180.0,
                median3d: null, median7d: 188.0, median30d: 175.0,
                trend: "up", confidence: "high", saleCount: 42,
              },
            },
          },
        },
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    return Promise.resolve(new Response(JSON.stringify({ data: [] }), {
      status: 200, headers: { "content-type": "application/json" },
    }));
  };

  const req = makeRequest({
    graded_card_identity_id: "id-1",
    grading_service: "PSA",
    grade: "10",
  });
  const res = await handle(req, {
    supabase: fake,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: "test-key",
    ttlSeconds: 86400,
    now: () => Date.now(),
    fetchImpl: stubFetch,
  });
  const body = await res.json();
  assertEquals(res.status, 200);
  assertEquals(body.cache_hit, false);
  assert(body.poketrace !== null, "expected poketrace block");
  assertEquals(body.poketrace.avg_cents, 18500);
  assertEquals(body.poketrace.trend, "up");
  assertEquals(body.sold_listings.length, 1);
  assertEquals(body.sold_listings[0].source_listing_id, "e1");
  assertEquals(body.sold_listings[0].price_cents, 18500);
  // Should have persisted the market row
  assert(fake._upsertedMarket() !== null, "market row should be persisted");
  // Cold path must hit the upstream — symmetric with case (b)'s fetchCalls === 0.
  assert(fetchedUrls.length > 0, "cold path must make upstream fetches");
});

// ─── (d) resolver returns null → 404 PRODUCT_NOT_RESOLVED ────────────────────

Deno.test("(d) resolver miss → 404 PRODUCT_NOT_RESOLVED", async () => {
  const identity = { ...baseIdentity };
  const fake = fakeSupabase({ identity, market: null });

  // Every Poketrace call returns empty data → resolver persists '' sentinel → returns null.
  const stubFetch: typeof fetch = () =>
    Promise.resolve(new Response(JSON.stringify({ data: [] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }));

  const req = makeRequest({
    graded_card_identity_id: "id-1",
    grading_service: "PSA",
    grade: "10",
  });
  const res = await handle(req, {
    supabase: fake,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: "test-key",
    ttlSeconds: 86400,
    now: () => Date.now(),
    fetchImpl: stubFetch,
  });
  const body = await res.json();
  assertEquals(res.status, 404);
  assertEquals(body.code, "PRODUCT_NOT_RESOLVED");
});

// ─── (e) prices present + listings 403 → block present, sold_listings:[] ─────

Deno.test("(e) prices present + listings 403 → block returned, sold_listings:[]", async () => {
  const identity = { ...baseIdentity };
  const fake = fakeSupabase({ identity, market: null, sales: [] });

  const stubFetch: typeof fetch = (input, _init) => {
    const url = typeof input === "string" ? input : (input as Request).url;
    const u = new URL(url);

    // Resolve: /cards?search= → return a matching card.
    if (u.pathname.endsWith("/cards") && u.searchParams.get("search")) {
      return Promise.resolve(new Response(JSON.stringify({
        data: [
          { id: "pt-uuid-e", name: "Charizard", cardNumber: "4/102", set: { name: "Base Set" } },
        ],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    // History: /cards/{id}/prices/{tier}/history
    if (u.pathname.includes("/prices/") && u.pathname.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify({ data: [] }), {
        status: 200, headers: { "content-type": "application/json" },
      }));
    }

    // Listings: 403 UPGRADE_REQUIRED
    if (u.pathname.includes("/listings")) {
      return Promise.resolve(new Response(JSON.stringify({ code: "UPGRADE_REQUIRED" }), {
        status: 403, headers: { "content-type": "application/json" },
      }));
    }

    // Prices: /cards/{id} (card detail)
    if (u.pathname.match(/\/cards\/[^/]+$/)) {
      return Promise.resolve(new Response(JSON.stringify({
        data: {
          id: "pt-uuid-e",
          prices: {
            ebay: {
              PSA_10: {
                avg: 200.0, low: 150.0, high: 280.0,
                avg1d: null, avg7d: 210.0, avg30d: 195.0,
                median3d: null, median7d: 205.0, median30d: 190.0,
                trend: "stable", confidence: "medium", saleCount: 20,
              },
            },
          },
        },
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    return Promise.resolve(new Response(JSON.stringify({ data: [] }), {
      status: 200, headers: { "content-type": "application/json" },
    }));
  };

  const req = makeRequest({
    graded_card_identity_id: "id-1",
    grading_service: "PSA",
    grade: "10",
  });
  const res = await handle(req, {
    supabase: fake,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: "test-key",
    ttlSeconds: 86400,
    now: () => Date.now(),
    fetchImpl: stubFetch,
  });
  const body = await res.json();
  assertEquals(res.status, 200);
  assertEquals(body.cache_hit, false);
  assert(body.poketrace !== null, "block should be present");
  assertEquals(body.poketrace.avg_cents, 20000);
  assertEquals(body.sold_listings, [], "sold_listings must be [] on 403");
});

// ─── (f) no tier aggregate + sold listings present → 200 poketrace:null, listings ───
//
// A slab can have eBay sold comps without a computed graded-tier aggregate.
// The feature's whole point is to surface those comps, so the handler MUST
// return 200 with poketrace:null and the listings — NOT 404 NO_MARKET_DATA.

Deno.test("(f) no tier aggregate but listings present → 200 poketrace:null + sold_listings", async () => {
  const identity = { ...baseIdentity };
  const fake = fakeSupabase({ identity, market: null, sales: [] });

  const stubFetch: typeof fetch = (input, _init) => {
    const url = typeof input === "string" ? input : (input as Request).url;
    const u = new URL(url);

    // Resolve succeeds.
    if (u.pathname.endsWith("/cards") && u.searchParams.get("search")) {
      return Promise.resolve(new Response(JSON.stringify({
        data: [
          { id: "pt-uuid-f", name: "Charizard", cardNumber: "4/102", set: { name: "Base Set" } },
        ],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    // History empty.
    if (u.pathname.includes("/prices/") && u.pathname.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify({ data: [] }), {
        status: 200, headers: { "content-type": "application/json" },
      }));
    }

    // Listings present.
    if (u.pathname.includes("/listings")) {
      return Promise.resolve(new Response(JSON.stringify({
        data: [
          {
            sourceItemId: "e9",
            title: "Charizard PSA 10",
            price: 195.0,
            soldAt: "2026-05-02T00:00:00Z",
            grader: "PSA",
            grade: "10",
            listingUrl: "http://ebay/e9",
            condition: "Graded",
            anomalyFlag: null,
          },
        ],
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    // Card detail: NO matching tier → fetchPoketracePrices returns fields:null.
    if (u.pathname.match(/\/cards\/[^/]+$/)) {
      return Promise.resolve(new Response(JSON.stringify({
        data: { id: "pt-uuid-f", prices: {} },
      }), { status: 200, headers: { "content-type": "application/json" } }));
    }

    return Promise.resolve(new Response(JSON.stringify({ data: [] }), {
      status: 200, headers: { "content-type": "application/json" },
    }));
  };

  const req = makeRequest({
    graded_card_identity_id: "id-1",
    grading_service: "PSA",
    grade: "10",
  });
  const res = await handle(req, {
    supabase: fake,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: "test-key",
    ttlSeconds: 86400,
    now: () => Date.now(),
    fetchImpl: stubFetch,
  });
  const body = await res.json();
  assertEquals(res.status, 200);
  assertEquals(body.cache_hit, false);
  assertEquals(body.poketrace, null, "poketrace block must be null with no tier aggregate");
  assert(body.sold_listings.length > 0, "sold_listings must be surfaced");
  assertEquals(body.sold_listings[0].source_listing_id, "e9");
  // No market row persisted (no aggregate), but sold listings ARE persisted.
  assertEquals(fake._upsertedMarket(), null, "no market row without a tier aggregate");
  assert(fake._upsertedSales().length > 0, "sold listings must be persisted");
});
