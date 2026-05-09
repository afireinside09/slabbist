// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handle, type HandleDeps } from "../index.ts";
import { _resetPauseForTests } from "../ppt/cards.ts";

// ─── Source-aware in-memory Supabase stub ────────────────────────────────────
//
// The handler queries graded_market with a 4-column PK filter:
//   .eq("identity_id", ...).eq("grading_service", ...).eq("grade", ...).eq("source", ...)
//
// This fake accumulates all filter pairs in a closure and applies them all
// at maybeSingle()/single() time, so two rows with different `source` values
// coexist and are returned correctly.
//
function makeSupabase(initial: { identity?: Record<string, unknown>; market?: Record<string, unknown> }) {
  const tables: Record<string, Record<string, unknown>[]> = {
    graded_card_identities: initial.identity ? [{ ...initial.identity }] : [],
    graded_market: initial.market ? [{ ...initial.market }] : [],
  };

  return {
    from(tableName: string) {
      const rows = (tables[tableName] ??= []);

      // Fluent builder that accumulates eq-filters and applies them at terminal ops.
      function builder(filters: Array<[string, unknown]>) {
        function matches(row: Record<string, unknown>): boolean {
          return filters.every(([col, val]) => row[col] === val);
        }
        return {
          select(_cols?: string) {
            // select returns the same builder (filter accumulation continues)
            return builder(filters);
          },
          eq(col: string, val: unknown) {
            return builder([...filters, [col, val]]);
          },
          maybeSingle() {
            const r = rows.find(matches) ?? null;
            return Promise.resolve({ data: r, error: null });
          },
          single() {
            const r = rows.find(matches) ?? null;
            return Promise.resolve({
              data: r,
              error: r ? null : { message: "not found" },
            });
          },
          upsert(row: Record<string, unknown>, _opts?: unknown) {
            // Replace-or-insert by 4-column composite key.
            const idx = rows.findIndex((r) =>
              r.identity_id === row.identity_id &&
              r.grading_service === row.grading_service &&
              r.grade === row.grade &&
              r.source === row.source
            );
            if (idx >= 0) rows[idx] = row;
            else rows.push(row);
            return Promise.resolve({ error: null });
          },
          update(patch: Record<string, unknown>) {
            // Returns a new builder so .eq(...) can scope the update.
            const patchFilters = [...filters];
            return {
              eq(col: string, val: unknown) {
                const allFilters = [...patchFilters, [col, val]];
                const r = rows.find((row) => allFilters.every(([c, v]) => row[c] === v));
                if (r) Object.assign(r, patch);
                return Promise.resolve({ error: null });
              },
            };
          },
        };
      }

      // Top-level table facade
      return {
        select(cols?: string) {
          return builder([]).select(cols);
        },
        eq(col: string, val: unknown) {
          return builder([[col, val]]);
        },
        upsert(row: Record<string, unknown>, opts?: unknown) {
          return builder([]).upsert(row, opts);
        },
        update(patch: Record<string, unknown>) {
          return builder([]).update(patch);
        },
      };
    },
    // Expose tables for post-test inspection
    _tables() { return tables; },
  } as unknown;
}

// ─── Fixtures ────────────────────────────────────────────────────────────────

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

// Proper PPT card response shape: salesByGrade → smartMarketPrice.price
// (dollars). The handler calls fetchCard(warm path) which uses this.
const PPT_CARD_BODY = {
  tcgPlayerId: "243172",
  name: "Charizard",
  ebay: {
    salesByGrade: {
      psa10:  { count: 12, smartMarketPrice: { price: 185.0,  confidence: "high"   } },
      psa9_5: { count: 5,  smartMarketPrice: { price: 120.0,  confidence: "medium" } },
      psa9:   { count: 8,  smartMarketPrice: { price: 80.0,   confidence: "medium" } },
      psa8:   { count: 6,  smartMarketPrice: { price: 50.0,   confidence: "medium" } },
      psa7:   { count: 3,  smartMarketPrice: { price: 30.0,   confidence: "low"    } },
      bgs10:  { count: 4,  smartMarketPrice: { price: 220.0,  confidence: "high"   } },
      cgc10:  { count: 2,  smartMarketPrice: { price: 170.0,  confidence: "low"    } },
      sgc10:  { count: 1,  smartMarketPrice: { price: 165.0,  confidence: "low"    } },
    },
    priceHistory: {},
  },
  prices: { market: 4.0 },
  url: "https://www.pokemonpricetracker.com/card/charizard",
};

const POKETRACE_CARD_ID = "22222222-2222-2222-2222-222222222222";

// Proper Poketrace card detail response: data.prices.ebay.PSA_10 = { avg: 195, ... }
const POKETRACE_CARD_BODY = {
  data: {
    id: POKETRACE_CARD_ID,
    prices: {
      ebay: {
        PSA_10: {
          avg:        195.00,
          low:        180.00,
          high:       210.00,
          avg1d:      null,
          avg7d:      192.00,
          avg30d:     194.00,
          median3d:   null,
          median7d:   193.00,
          median30d:  195.00,
          trend:      "stable",
          confidence: "high",
          saleCount:  24,
        },
      },
    },
  },
};

const POKETRACE_HISTORY_BODY = {
  data: [
    { date: "2026-04-30", avg: 192.00 },
    { date: "2026-05-01", avg: 195.00 },
  ],
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

// Temporarily replaces globalThis.fetch for the duration of fn().
// Both PPT and Poketrace clients ultimately call global fetch.
async function withStubFetch<T>(stub: typeof fetch, fn: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  try {
    return await fn();
  } finally {
    globalThis.fetch = original;
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

Deno.test("v2 envelope: both PPT and Poketrace succeed → reconciled is the average", async () => {
  _resetPauseForTests();
  const supabase = makeSupabase({ identity: { ...IDENTITY } });

  const stubFetch: typeof fetch = (input, init) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);

    // PPT warm-path fetch: /api/v2/cards?tcgPlayerId=243172
    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(
        JSON.stringify([PPT_CARD_BODY]),
        { status: 200, headers: { "content-type": "application/json" } },
      ));
    }

    // Poketrace cross-walk: /cards?tcgplayer_ids=243172
    if (url.includes("api.poketrace.com") && url.includes("tcgplayer_ids=")) {
      return Promise.resolve(new Response(
        JSON.stringify({ data: [{ id: POKETRACE_CARD_ID }] }),
        { status: 200, headers: { "content-type": "application/json" } },
      ));
    }

    // Poketrace history: /cards/{id}/prices/{tier}/history
    if (url.includes("api.poketrace.com") && url.includes("/history")) {
      return Promise.resolve(new Response(
        JSON.stringify(POKETRACE_HISTORY_BODY),
        { status: 200, headers: { "content-type": "application/json" } },
      ));
    }

    // Poketrace card detail: /cards/{uuid}  (no query string, ends after UUID)
    if (url.includes("api.poketrace.com") && url.includes("/cards/")) {
      return Promise.resolve(new Response(
        JSON.stringify(POKETRACE_CARD_BODY),
        { status: 200, headers: { "content-type": "application/json" } },
      ));
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

  // PPT headline for PSA 10 = $185 → 18500 cents
  assertEquals(body.headline_price_cents, 18500, "PPT psa_10 headline");
  assertEquals(body.psa_10_price_cents, 18500, "ladder psa_10");
  assertEquals(body.cache_hit, false);

  // Poketrace block populated
  assert(body.poketrace !== null, "poketrace block must be non-null");
  assertEquals(body.poketrace.tier, "PSA_10");
  assertEquals(body.poketrace.avg_cents, 19500, "poketrace avg $195 → 19500¢");
  assertEquals(body.poketrace.trend, "stable");
  assertEquals(body.poketrace.sale_count, 24);

  // Reconciled = average of 18500 and 19500 = 19000
  assertEquals(body.reconciled.source, "avg");
  assertEquals(body.reconciled.headline_price_cents, 19000, "(18500+19500)/2 = 19000");

  // Verify the source-aware upsert: two rows in graded_market
  const tables = (supabase as any)._tables();
  const marketRows: Record<string, unknown>[] = tables.graded_market;
  const pptRow = marketRows.find((r) => r.source === "pokemonpricetracker");
  const ptRow  = marketRows.find((r) => r.source === "poketrace");
  assert(pptRow, "PPT row must exist in graded_market");
  assert(ptRow,  "Poketrace row must exist in graded_market");
  assertEquals(pptRow.psa_10_price, 185.0, "PPT row stores dollar value");
  assertEquals(ptRow.pt_avg, 195.0, "Poketrace row stores pt_avg");
});

Deno.test("v2 envelope: poketrace down (5xx) → reconciled = ppt-only, ppt data present", async () => {
  _resetPauseForTests();
  const supabase = makeSupabase({ identity: { ...IDENTITY } });

  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);

    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(
        JSON.stringify([PPT_CARD_BODY]),
        { status: 200, headers: { "content-type": "application/json" } },
      ));
    }

    // All Poketrace calls return 5xx
    if (url.includes("api.poketrace.com")) {
      return Promise.resolve(new Response("upstream down", { status: 503 }));
    }

    return Promise.resolve(new Response("not stubbed: " + url, { status: 599 }));
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

  assertEquals(resp.status, 200);
  const body = await resp.json();

  // PPT data still present
  assertEquals(body.headline_price_cents, 18500, "PPT psa_10 still returned");
  assertEquals(body.psa_10_price_cents, 18500);
  assertEquals(body.cache_hit, false);

  // Poketrace block null (5xx swallowed)
  assertEquals(body.poketrace, null, "poketrace must be null when source is down");

  // Reconciled falls back to PPT-only
  assertEquals(body.reconciled.source, "ppt-only");
  assertEquals(body.reconciled.headline_price_cents, 18500);
});

Deno.test("v2 envelope: poketrace saleCount >=5 + divergence >20% → poketrace-preferred", async () => {
  _resetPauseForTests();
  const supabase = makeSupabase({ identity: { ...IDENTITY } });

  // PPT reports psa10 = $500 (deliberately wrong, the Charizard JP case).
  // Poketrace reports $1,236 across 57 sales.
  // Divergence = |1236-500|/500 = 147% → poketrace-preferred kicks in.
  const PPT_BAD_BODY = {
    ...PPT_CARD_BODY,
    ebay: {
      ...PPT_CARD_BODY.ebay,
      salesByGrade: {
        ...PPT_CARD_BODY.ebay.salesByGrade,
        psa10: { count: 12, smartMarketPrice: { price: 500.0, confidence: "low" } },
      },
    },
  };
  const POKETRACE_HIGH_VOL_BODY = {
    data: {
      id: POKETRACE_CARD_ID,
      prices: {
        ebay: {
          PSA_10: { avg: 1236.0, low: 949.99, high: 1236.0, saleCount: 57, trend: null, confidence: null },
        },
      },
    },
  };

  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);
    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(JSON.stringify([PPT_BAD_BODY]), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("tcgplayer_ids=")) {
      return Promise.resolve(new Response(JSON.stringify({ data: [{ id: POKETRACE_CARD_ID }] }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_HISTORY_BODY), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/cards/")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_HIGH_VOL_BODY), { status: 200, headers: { "content-type": "application/json" } }));
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

  assertEquals(body.headline_price_cents, 50000, "PPT psa_10 = $500");
  assertEquals(body.poketrace.avg_cents, 123600, "Poketrace avg = $1,236");
  assertEquals(body.poketrace.sale_count, 57);
  assertEquals(body.reconciled.source, "poketrace-preferred");
  assertEquals(body.reconciled.headline_price_cents, 123600, "Reconciled = Poketrace avg, not the simple-average $868");
});

Deno.test("v2 envelope: poketrace saleCount <5 → simple avg even when divergence is high", async () => {
  _resetPauseForTests();
  const supabase = makeSupabase({ identity: { ...IDENTITY } });

  // Same wide divergence, but only 3 Poketrace sales — below the
  // confidence threshold, so we fall back to a simple average.
  const PPT_BAD_BODY = {
    ...PPT_CARD_BODY,
    ebay: {
      ...PPT_CARD_BODY.ebay,
      salesByGrade: {
        ...PPT_CARD_BODY.ebay.salesByGrade,
        psa10: { count: 12, smartMarketPrice: { price: 500.0, confidence: "low" } },
      },
    },
  };
  const POKETRACE_LOW_VOL_BODY = {
    data: {
      id: POKETRACE_CARD_ID,
      prices: { ebay: { PSA_10: { avg: 1236.0, low: 1236.0, high: 1236.0, saleCount: 3 } } },
    },
  };

  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);
    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(JSON.stringify([PPT_BAD_BODY]), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("tcgplayer_ids=")) {
      return Promise.resolve(new Response(JSON.stringify({ data: [{ id: POKETRACE_CARD_ID }] }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_HISTORY_BODY), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/cards/")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_LOW_VOL_BODY), { status: 200, headers: { "content-type": "application/json" } }));
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
  const body = await resp.json();
  assertEquals(body.poketrace.sale_count, 3);
  assertEquals(body.reconciled.source, "avg");
  // (50000 + 123600) / 2 = 86800
  assertEquals(body.reconciled.headline_price_cents, 86800);
});

Deno.test("v2 envelope: cache-hit path live-fetches Poketrace when no cached PT row exists", async () => {
  _resetPauseForTests();
  // Pre-populated: PPT cache row, fresh, but no Poketrace row yet.
  const FRESH_PPT_ROW = {
    identity_id: IDENTITY.id,
    grading_service: "PSA",
    grade: "10",
    source: "pokemonpricetracker",
    headline_price: 500.0,
    psa_10_price: 500.0,
    ppt_tcgplayer_id: "243172",
    ppt_url: "https://www.pokemonpricetracker.com/card/charizard",
    price_history: [],
    updated_at: "2026-05-08T11:00:00Z", // 1h before now → fresh
  };
  const supabase = makeSupabase({ identity: { ...IDENTITY }, market: FRESH_PPT_ROW });

  let pptCalls = 0;
  let ptCardCalls = 0;
  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);
    if (url.includes("pokemonpricetracker.com")) {
      pptCalls += 1;
      return Promise.resolve(new Response(JSON.stringify([PPT_CARD_BODY]), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("tcgplayer_ids=")) {
      return Promise.resolve(new Response(JSON.stringify({ data: [{ id: POKETRACE_CARD_ID }] }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_HISTORY_BODY), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/cards/")) {
      ptCardCalls += 1;
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_CARD_BODY), { status: 200, headers: { "content-type": "application/json" } }));
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

  assertEquals(body.cache_hit, true, "PPT path is a cache hit");
  assertEquals(pptCalls, 0, "no PPT HTTP call on cache hit");
  assert(ptCardCalls >= 1, "Poketrace was live-fetched as backfill");
  assert(body.poketrace !== null, "Poketrace block populated by backfill");
  assertEquals(body.poketrace.avg_cents, 19500);

  // Verify the backfill persisted
  const tables = (supabase as any)._tables();
  const ptRow = tables.graded_market.find((r: Record<string, unknown>) => r.source === "poketrace");
  assert(ptRow, "Poketrace row was persisted by the cache-hit backfill");
});

Deno.test("v2 envelope: poketrace api key not configured → branch quietly skipped, no poketrace HTTP calls", async () => {
  _resetPauseForTests();
  const supabase = makeSupabase({ identity: { ...IDENTITY } });

  let poketraceCallCount = 0;

  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);

    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(
        JSON.stringify([PPT_CARD_BODY]),
        { status: 200, headers: { "content-type": "application/json" } },
      ));
    }

    // Any Poketrace call is unexpected when apiKey is null
    if (url.includes("api.poketrace.com")) {
      poketraceCallCount++;
      return Promise.resolve(new Response("should not be called", { status: 599 }));
    }

    return Promise.resolve(new Response("not stubbed: " + url, { status: 599 }));
  };

  const resp = await withStubFetch(stubFetch, () => handle(makeRequest(), {
    supabase,
    pptBaseUrl: "https://www.pokemonpricetracker.com",
    pptToken: "ppt-token",
    ttlSeconds: 86400,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey: null,   // ← disabled
    now: () => Date.parse("2026-05-08T12:00:00Z"),
  }));

  assertEquals(resp.status, 200);
  const body = await resp.json();

  assertEquals(body.poketrace, null, "poketrace null when key not configured");
  assertEquals(body.reconciled.source, "ppt-only");
  assertEquals(body.reconciled.headline_price_cents, 18500);

  // No Poketrace HTTP calls should have been made
  assertEquals(poketraceCallCount, 0, "zero Poketrace HTTP calls when apiKey is null");
});
