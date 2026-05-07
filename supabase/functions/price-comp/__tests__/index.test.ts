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

interface FakeTcgProductRow {
  product_id: number;
  group_id: number;
  name: string;
  card_number: string;
}

function fakeSupabase(state: {
  identity: FakeIdentity;
  market: FakeMarketRow | null;
  tcgProducts?: FakeTcgProductRow[];
}) {
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
      if (table === "tcg_products") {
        // Tier A's lookup. Default to empty so cold-path tests fall
        // through to the existing search behavior. Naive emulation of
        // PostgREST eq + or chain.
        let filtered = [...(state.tcgProducts ?? [])];
        const builder: any = {
          select(_cols: string) { return builder; },
          eq(col: string, value: unknown) {
            if (col === "group_id") filtered = filtered.filter((r) => r.group_id === value);
            return builder;
          },
          or(filter: string) {
            const clauses = filter.split(",");
            filtered = filtered.filter((r) => {
              for (const cl of clauses) {
                const [c, op, ...rest] = cl.split(".");
                const v = rest.join(".");
                if (c !== "card_number") continue;
                if (op === "eq" && r.card_number === v) return true;
                if (op === "ilike") {
                  const re = new RegExp("^" + v.replace(/%/g, ".*") + "$", "i");
                  if (re.test(r.card_number)) return true;
                }
              }
              return false;
            });
            return builder;
          },
          limit(n: number) {
            filtered = filtered.slice(0, n);
            return Promise.resolve({ data: filtered, error: null });
          },
          then(resolve: (v: any) => void) {
            resolve({ data: filtered, error: null });
          },
        };
        return builder;
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
    // Multi-tier resolver: T1 search (1 credit, no ebay/history) +
    // full fetchCard by tcgPlayerId (3 credits) = 2 PPT calls on the
    // happy path.
    assertEquals(state.calls.length, 2, "T1 search + full fetch by tcgPlayerId");
    assertEquals(state.calls[0].query.get("search"), "Charizard 4/102 Base Set");
    assertEquals(state.calls[0].query.get("includeEbay"), null, "T1 search must not pay for ebay");
    assertEquals(state.calls[1].query.get("tcgPlayerId"), "243172");
    assertEquals(state.calls[1].query.get("includeEbay"), "true");
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
    // Resolver attempt log surfaced for debugging — at least one tier
    // line per attempted tier (A no-alias + B + D = 3 lines minimum).
    assert(Array.isArray(body.attempt_log));
    assert(body.attempt_log.length >= 3, `expected attempt_log >= 3 lines, got ${body.attempt_log.length}`);
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

Deno.test("resolver T1: parens stripped from card_name in T1 query, full fetch follows", async () => {
  _resetPauseForTests();
  // Match the SIR-tagged Charizard against a card whose name+number agree.
  const matchCard = { tcgPlayerId: "243172", name: "Charizard ex", cardNumber: "199/165", setName: "Scarlet & Violet 151" };
  const state: MockState = {
    responses: new Map([
      ["Charizard ex 199 Scarlet & Violet 151", { status: 200, body: [matchCard] }],
      ["243172", { status: 200, body: [fullLadder] }],
    ]),
    defaultBody: [],
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
    const res = await handle(req, { supabase: fake, pptBaseUrl: mock.url, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
    assertEquals(res.status, 200);
    // T1 hits → only T1 is run (no T2/T3 fall-through). Then full fetch.
    assertEquals(state.calls.length, 2);
    assertEquals(state.calls[0].query.get("search"), "Charizard ex 199 Scarlet & Violet 151");
    assertEquals(state.calls[0].query.get("limit"), "10");
    assertEquals(state.calls[0].query.get("includeEbay"), null);
    assertEquals(state.calls[1].query.get("tcgPlayerId"), "243172");
  } finally {
    await mock.close();
  }
});

Deno.test("resolver T2 fallback: T1 misses, ?set= filter resolves on overlap", async () => {
  _resetPauseForTests();
  // Identity: Charizard V #050 from "Champion's Path ETB Promo".
  // T1 returns nothing. T2 ?set=champion (or champions) returns a
  // Champion's Path candidate whose number disagrees ("079" vs "050")
  // but whose set tokens overlap by >=2.
  const t2Card = { tcgPlayerId: "999111", name: "Charizard V", cardNumber: "079", setName: "Champion's Path" };
  const state: MockState = {
    responses: new Map(),
    defaultBody: [],
    calls: [],
  };
  // Custom router: T1 = empty, T2 with set=champion(s) = [t2Card], T3 = ignored.
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, (req) => {
    const u = new URL(req.url);
    state.calls.push({ url: u.pathname, query: u.searchParams });
    const tcg = u.searchParams.get("tcgPlayerId");
    const set = u.searchParams.get("set");
    if (tcg === "999111") {
      return new Response(JSON.stringify([{ ...t2Card, ebay: { salesByGrade: { psa10: { smartMarketPrice: { price: 250 } } } } }]), { status: 200 });
    }
    if (set && (set === "champion" || set === "champions")) {
      return new Response(JSON.stringify([t2Card]), { status: 200 });
    }
    return new Response(JSON.stringify([]), { status: 200 });
  });
  const mockUrl = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-2",
        card_name: "Charizard V",
        card_number: "050",
        set_name: "Champion's Path ETB Promo",
        year: 2020,
        ppt_tcgplayer_id: null,
        ppt_url: null,
      },
      market: null,
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ graded_card_identity_id: "id-2", grading_service: "PSA", grade: "10" }),
    });
    const res = await handle(req, { supabase: fake, pptBaseUrl: mockUrl, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
    const body = await res.json();
    assertEquals(res.status, 200);
    assertEquals(body.ppt_tcgplayer_id, "999111");
    // T1 (no hit) + T2 (hit) + full fetch = 3 calls.
    assertEquals(state.calls.length, 3);
    assertEquals(state.calls[0].query.get("search"), "Charizard V 050 Champion's Path ETB Promo");
    assertEquals(state.calls[1].query.get("search"), "Charizard V");
    const t2Set = state.calls[1].query.get("set") ?? "";
    assert(t2Set === "champion" || t2Set === "champions", `unexpected T2 set: ${t2Set}`);
    assertEquals(state.calls[2].query.get("tcgPlayerId"), "999111");
  } finally {
    ac.abort();
    try { await server.finished; } catch {}
  }
});

Deno.test("resolver Tier A: alias hit + tcg_products hit → direct PPT fetch, no search", async () => {
  _resetPauseForTests();
  const state: MockState = {
    responses: new Map([
      ["243172", { status: 200, body: [fullLadder] }],
    ]),
    defaultBody: [],
    calls: [],
  };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-A",
        card_name: "Charizard ex",
        card_number: "199",
        set_name: "Scarlet & Violet 151",
        year: 2023,
        ppt_tcgplayer_id: null,
        ppt_url: null,
      },
      market: null,
      // Tier A's tcg_products hit: this group_id (23237 = SV: Scarlet
      // & Violet 151) is what the alias maps to.
      tcgProducts: [
        { product_id: 243172, group_id: 23237, name: "Charizard ex - 199/165", card_number: "199/165" },
      ],
    });
    const req = new Request("http://localhost/price-comp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ graded_card_identity_id: "id-A", grading_service: "PSA", grade: "10" }),
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
    assertEquals(body.ppt_tcgplayer_id, "243172");
    assertEquals(body.headline_price_cents, 18500);
    // Tier A path: 1 PPT call (the direct fetchCard by tcgPlayerId). No
    // searchCards calls.
    assertEquals(state.calls.length, 1, "only the full fetchCard, no PPT search");
    assertEquals(state.calls[0].query.get("tcgPlayerId"), "243172");
    assertEquals(state.calls[0].query.get("includeEbay"), "true");
  } finally {
    await mock.close();
  }
});

Deno.test("resolver: null card_number → T1 query has no number", async () => {
  _resetPauseForTests();
  const matchCard = { tcgPlayerId: "243172", name: "Mew", cardNumber: "151", setName: "Promo" };
  const state: MockState = {
    responses: new Map([
      ["Mew Promo", { status: 200, body: [matchCard] }],
      ["243172", { status: 200, body: [fullLadder] }],
    ]),
    defaultBody: [],
    calls: [],
  };
  const mock = startMock(state);
  try {
    const fake = fakeSupabase({
      identity: {
        id: "id-3",
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
      body: JSON.stringify({ graded_card_identity_id: "id-3", grading_service: "PSA", grade: "10" }),
    });
    await handle(req, { supabase: fake, pptBaseUrl: mock.url, pptToken: "t", ttlSeconds: 86400, now: () => Date.now() });
    // T1 with name+set only. Card-name match alone doesn't pass scoreCard
    // accept (overlap 0 since "Promo" is a stopword), so T1 candidate is
    // rejected → fall through to T3 (T2 skipped, no distinctive token in
    // "Promo"). T3 also rejects. End result: PRODUCT_NOT_RESOLVED is fine
    // here; we just want to assert the T1 query shape.
    assertEquals(state.calls[0].query.get("search"), "Mew Promo");
  } finally {
    await mock.close();
  }
});
