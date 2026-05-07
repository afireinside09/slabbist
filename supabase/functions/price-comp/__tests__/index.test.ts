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
    // buildSearchQuery strips parens + drops year — keeps card name + number + set.
    assertEquals(state.calls[0].query.get("search"), "Charizard 4/102 Base Set");
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

Deno.test("buildSearchQuery: strips parenthesized variant suffix from card_name", async () => {
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
        card_name: "Charizard ex (Special Illustration Rare)",
        card_number: "199",
        set_name: "Scarlet & Violet 151",
        year: 2023,
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
    await handle(req, { supabase: fake, pptBaseUrl: mock.url, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
    // Parens stripped, year dropped, internal whitespace collapsed.
    assertEquals(state.calls[0].query.get("search"), "Charizard ex 199 Scarlet & Violet 151");
  } finally {
    await mock.close();
  }
});

Deno.test("buildSearchQuery: drops year token from query", async () => {
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
        card_name: "Pikachu",
        card_number: "025",
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
    await handle(req, { supabase: fake, pptBaseUrl: mock.url, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
    const search = state.calls[0].query.get("search") ?? "";
    assert(!search.includes("1999"), `query should not contain year, got: ${search}`);
    assertEquals(search, "Pikachu 025 Base Set");
  } finally {
    await mock.close();
  }
});

Deno.test("buildSearchQuery: omits null card_number cleanly", async () => {
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
        card_name: "Mew",
        card_number: null,
        set_name: "Promo",
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
    await handle(req, { supabase: fake, pptBaseUrl: mock.url, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
    assertEquals(state.calls[0].query.get("search"), "Mew Promo");
  } finally {
    await mock.close();
  }
});
