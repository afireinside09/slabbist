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
