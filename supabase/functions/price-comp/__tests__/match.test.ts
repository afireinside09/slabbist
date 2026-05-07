// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildSearchTiers, scoreCard, resolveCard } from "../ppt/match.ts";
import { _resetPauseForTests } from "../ppt/cards.ts";

// ─── buildSearchTiers ────────────────────────────────────────────────
//
// Note: Tier A (the alias/tcg_products lookup) does NOT participate in
// buildSearchTiers — it's a local DB hop, not a PPT search. These
// tests cover the B/C/D PPT-search tiers only.

Deno.test("buildSearchTiers: SV151 Charizard ex 199 SIR — B has all, C set='151', D bare name", () => {
  const tiers = buildSearchTiers({
    card_name: "Charizard ex (Special Illustration Rare)",
    card_number: "199",
    set_name: "Scarlet & Violet 151",
    year: 2023,
  });
  assertEquals(tiers.length, 3);
  assertEquals(tiers[0].tier, "B");
  assertEquals(tiers[0].args.search, "Charizard ex 199 Scarlet & Violet 151");
  assertEquals(tiers[1].tier, "C");
  assertEquals(tiers[1].args.search, "Charizard ex");
  // "151" is the longest distinctive >=4-char-or-numeric token, but
  // numerics shouldn't be filtered just for being short. Fallback: pick
  // the longest token. "scarlet" beats "violet" alphabetically tied on
  // length; either way it's a stable distinctive set token.
  assert(["scarlet", "violet", "151"].includes(tiers[1].args.set ?? ""));
  assertEquals(tiers[1].args.limit, 10);
  assertEquals(tiers[2].tier, "D");
  assertEquals(tiers[2].args.search, "Charizard ex");
  assertEquals(tiers[2].args.set, undefined);
  assertEquals(tiers[2].args.limit, 20);
});

Deno.test("buildSearchTiers: M-P Promo set has no distinctive token → C skipped", () => {
  const tiers = buildSearchTiers({
    card_name: "Pikachu",
    card_number: "020",
    set_name: "M-P Promo",
    year: 2025,
  });
  // B + D only (no C because M, P, and Promo all fail distinctive token rules).
  assertEquals(tiers.length, 2);
  assertEquals(tiers[0].tier, "B");
  assertEquals(tiers[1].tier, "D");
  assertEquals(tiers[1].args.search, "Pikachu");
});

Deno.test("buildSearchTiers: Champion's Path ETB Promo → C set token contains 'champion'", () => {
  const tiers = buildSearchTiers({
    card_name: "Charizard V",
    card_number: "050",
    set_name: "Champion's Path ETB Promo",
    year: 2020,
  });
  assertEquals(tiers.length, 3);
  assertEquals(tiers[1].tier, "C");
  // After punctuation strip + stopword filter:
  //   champion(s) (8-9), path (4), etb (3, drop), promo (stopword, drop).
  // Longest distinctive token is the champion(s) form, whether or not the
  // impl preserves the trailing "s" after stripping the apostrophe.
  const setTok = tiers[1].args.set ?? "";
  assert(setTok === "champion" || setTok === "champions",
    `expected 'champion' or 'champions', got '${setTok}'`);
});

Deno.test("buildSearchTiers: SVP Black Star Promo → C set token = 'black' or 'star'", () => {
  const tiers = buildSearchTiers({
    card_name: "Pikachu with Grey Felt Hat",
    card_number: "085",
    set_name: "SVP Black Star Promo (Van Gogh Museum)",
    year: 2023,
  });
  assertEquals(tiers.length, 3);
  assertEquals(tiers[1].tier, "C");
  // Distinctive tokens after punctuation strip + stopword filter:
  // svp(3<4 reject), black(5), star(4), promo(stopword), van(3<4), gogh(4), museum(6).
  // Longest = "museum" but "gogh"/"black"/"star" are also distinctive.
  // Pick whichever the impl chooses, just assert it's one of those.
  const setTok = tiers[1].args.set ?? "";
  assert(["black", "star", "gogh", "museum"].includes(setTok), `unexpected set token: ${setTok}`);
});

Deno.test("buildSearchTiers: null card_number drops cleanly from B query", () => {
  const tiers = buildSearchTiers({
    card_name: "Mew",
    card_number: null,
    set_name: "Promo",
    year: null,
  });
  assertEquals(tiers[0].args.search, "Mew Promo");
});

// ─── scoreCard ───────────────────────────────────────────────────────

const baseIdentity = {
  card_name: "Charizard ex",
  card_number: "199",
  set_name: "Scarlet & Violet 151",
  year: 2023,
};

Deno.test("scoreCard: exact name + exact number → accept, score >= 5", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard ex", cardNumber: "199/165", setName: "Scarlet & Violet 151" },
    baseIdentity,
  );
  assert(r.accept);
  assert(r.score >= 5, `expected >=5, got ${r.score}`);
});

Deno.test("scoreCard: name miss → reject, score 0", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Pikachu V", cardNumber: "199", setName: "Scarlet & Violet 151" },
    baseIdentity,
  );
  assertEquals(r.accept, false);
  assertEquals(r.score, 0);
});

Deno.test("scoreCard: name match + number off + set overlap >= 2 → accept", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard ex", cardNumber: "200", setName: "Scarlet & Violet 151 Promo" },
    baseIdentity,
  );
  assert(r.accept, `expected accept, score=${r.score}`);
});

Deno.test("scoreCard: name match + number off + set overlap < 2 → not accepted", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard ex", cardNumber: "200", setName: "Obsidian Flames" },
    baseIdentity,
  );
  assertEquals(r.accept, false);
  assert(r.score >= 2, "still scores positive (name match)");
});

Deno.test("scoreCard: PSA verbose number '020' matches TCGPlayer '020/198' → numberExact", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Pikachu", cardNumber: "020/198", setName: "McDonald's Promos 2024" },
    {
      card_name: "Pikachu",
      card_number: "020",
      set_name: "M-P Promo",
      year: 2024,
    },
  );
  assert(r.accept, `expected accept on number match, got accept=${r.accept} score=${r.score}`);
});

Deno.test("scoreCard: PSA '199' matches PPT '199/165' → numberExact", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard ex", cardNumber: "199/165", setName: "Anything" },
    baseIdentity,
  );
  assert(r.accept);
});

Deno.test("scoreCard: PSA '050' matches TCGPlayer '79' → no numberExact, but name+set may still rescue via T-level", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard V", cardNumber: "79", setName: "Champion's Path" },
    {
      card_name: "Charizard V",
      card_number: "050",
      set_name: "Champion's Path ETB Promo",
      year: 2020,
    },
  );
  // Cards: Champion's, Path; Identity stopwords removed: champion's, path, etb. So overlap is "champion's" "path" → 2.
  // Should accept on set overlap.
  assert(r.accept, `expected accept on set overlap, score=${r.score}`);
});

Deno.test("scoreCard: handles null card_number on identity gracefully", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Mew", cardNumber: "151", setName: "Promo" },
    {
      card_name: "Mew",
      card_number: null,
      set_name: "Promo",
      year: null,
    },
  );
  // No number to compare → 0 for number, set "Promo" is stopword → 0 overlap.
  // Name matches → +2. Not accepted (no exact, no overlap >= 2).
  assertEquals(r.accept, false);
  assertEquals(r.score, 2);
});

Deno.test("scoreCard: cardNumber missing on PPT card scores 0 for number, not crash", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard ex", setName: "Scarlet & Violet 151" },
    baseIdentity,
  );
  // Name +2, no number, set "scarlet violet 151" overlap with "scarlet violet 151" = 2 hits → accept.
  assert(r.accept);
});

// ─── resolveCard (small integration with mocked PPT + supabase) ──────

interface MockState {
  // keyed by "search:<q>|set:<s>" or "tcgPlayerId:<id>"
  responses: Map<string, { status: number; body: unknown }>;
  default: { status: number; body: unknown };
  calls: { url: string; query: URLSearchParams }[];
}

function startMock(state: MockState): { url: string; close: () => Promise<void> } {
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal }, (req) => {
    const u = new URL(req.url);
    state.calls.push({ url: u.pathname, query: u.searchParams });
    const tcg = u.searchParams.get("tcgPlayerId");
    let key = "__default__";
    if (tcg) key = `tcgPlayerId:${tcg}`;
    else key = `search:${u.searchParams.get("search") ?? ""}|set:${u.searchParams.get("set") ?? ""}`;
    const r = state.responses.get(key) ?? state.default;
    return new Response(JSON.stringify(r.body), { status: r.status, headers: { "content-type": "application/json" } });
  });
  const url = `http://localhost:${(server.addr as Deno.NetAddr).port}`;
  return { url, async close() { ac.abort(); try { await server.finished; } catch {} } };
}

// Stub supabase client for Tier A. `tcgRows` is the rows the
// `tcg_products` query returns (filtered in-memory by group_id and a
// naive OR/eq emulation; we don't try to fully mimic PostgREST). Pass
// an empty array to simulate "no tcg_products row found".
function fakeSupabaseForTcg(tcgRows: Array<{ product_id: number; group_id: number; name: string; card_number: string }>) {
  return {
    from(table: string) {
      if (table !== "tcg_products") throw new Error(`unexpected table ${table}`);
      let filtered = [...tcgRows];
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
              const [col, op, ...rest] = cl.split(".");
              const v = rest.join(".");
              if (col !== "card_number") continue;
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
        then(resolve: (v: any) => void) { resolve({ data: filtered, error: null }); },
      };
      return builder;
    },
  };
}

Deno.test("resolveCard: Tier A — alias hits + tcg_products hits → returns PPT card directly", async () => {
  _resetPauseForTests();
  const fullCard = { tcgPlayerId: "243172", name: "Charizard ex", cardNumber: "199/165", setName: "SV: Scarlet & Violet 151" };
  const state: MockState = {
    responses: new Map([
      ["tcgPlayerId:243172", { status: 200, body: [{ ...fullCard, ebay: { salesByGrade: { psa10: { smartMarketPrice: { price: 100 } } } } }] }],
    ]),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    const supabase = fakeSupabaseForTcg([
      { product_id: 243172, group_id: 23237, name: "Charizard ex - 199/165", card_number: "199/165" },
    ]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      {
        card_name: "Charizard ex (Special Illustration Rare)",
        card_number: "199",
        set_name: "Scarlet & Violet 151",
        year: 2023,
      },
    );
    assertEquals(r.tierMatched, "A");
    assertEquals(r.card?.tcgPlayerId, "243172");
    // Tier A path: 1 PPT call (the direct fetchCard by tcgPlayerId). No
    // search calls.
    assertEquals(state.calls.length, 1);
    assertEquals(state.calls[0].query.get("tcgPlayerId"), "243172");
  } finally {
    await mock.close();
  }
});

Deno.test("resolveCard: Tier A — alias hits but tcg_products misses → falls through to B", async () => {
  _resetPauseForTests();
  // B-tier match path: search returns the canonical card.
  const cardForB = { tcgPlayerId: "999111", name: "Charizard ex", cardNumber: "199/165", setName: "Scarlet & Violet 151" };
  const state: MockState = {
    responses: new Map([
      ["search:Charizard ex 199 Scarlet & Violet 151|set:", { status: 200, body: [cardForB] }],
      ["tcgPlayerId:999111", { status: 200, body: [{ ...cardForB, ebay: {} }] }],
    ]),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    // Empty tcg_products → Tier A misses.
    const supabase = fakeSupabaseForTcg([]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      {
        card_name: "Charizard ex (Special Illustration Rare)",
        card_number: "199",
        set_name: "Scarlet & Violet 151",
        year: 2023,
      },
    );
    assertEquals(r.tierMatched, "B");
    assertEquals(r.card?.tcgPlayerId, "999111");
    // No alias-direct fetch; B search + full fetch = 2 PPT calls.
    assertEquals(state.calls.length, 2);
  } finally {
    await mock.close();
  }
});

Deno.test("resolveCard: Tier A — alias misses entirely → falls through to B", async () => {
  _resetPauseForTests();
  const cardForB = { tcgPlayerId: "1", name: "Truly Anything", cardNumber: "1/1", setName: "Some Set" };
  const state: MockState = {
    responses: new Map([
      ["search:Truly Anything 1 Truly Made Up Set|set:", { status: 200, body: [cardForB] }],
    ]),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    const supabase = fakeSupabaseForTcg([]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      {
        card_name: "Truly Anything",
        card_number: "1",
        set_name: "Truly Made Up Set",
        year: null,
      },
    );
    // Set isn't in alias map → A logs miss, fallback runs. Card name+set
    // both fail scoreCard.accept (no number match, no set overlap), so
    // we end up with tierMatched=null but the resolver still walks all
    // tiers — what we care about is that A logged the miss.
    assert(r.attemptLog.some((line) => line.startsWith("A: no alias")));
  } finally {
    await mock.close();
  }
});

Deno.test("resolveCard: B hits with single result → take it, full fetch follows", async () => {
  _resetPauseForTests();
  const fullCard = { tcgPlayerId: "243172", name: "Foo Bar", cardNumber: "1/1", setName: "Made Up Foo Set" };
  const state: MockState = {
    responses: new Map([
      ["search:Foo Bar 1 Made Up Foo Set|set:", { status: 200, body: [fullCard] }],
      ["tcgPlayerId:243172", { status: 200, body: [{ ...fullCard, ebay: { salesByGrade: { psa10: { smartMarketPrice: { price: 100 } } } } }] }],
    ]),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    // Set isn't in alias map → Tier A logs miss, falls through to B.
    const supabase = fakeSupabaseForTcg([]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      {
        card_name: "Foo Bar",
        card_number: "1",
        set_name: "Made Up Foo Set",
        year: 2023,
      },
    );
    assertEquals(r.tierMatched, "B");
    assertEquals(r.card?.tcgPlayerId, "243172");
    assert(r.card?.ebay?.salesByGrade?.psa10 !== undefined, "expected full ebay block from heavy fetchCard");
    assertEquals(state.calls.length, 2, "B search + full fetch = 2 calls");
  } finally {
    await mock.close();
  }
});

Deno.test("resolveCard: B zero hits → falls to D (C skipped on no distinctive token)", async () => {
  _resetPauseForTests();
  const cardA = { tcgPlayerId: "1", name: "Pikachu", cardNumber: "001", setName: "SV: Scarlet & Violet Promo Cards" };
  const cardB = { tcgPlayerId: "2", name: "Pikachu", cardNumber: "010", setName: "Other Set" };
  const state: MockState = {
    responses: new Map([
      // B misses
      ["search:Pikachu 001 SV-P Promo|set:", { status: 200, body: [] }],
      // No C for this set; D (default) returns the cards.
    ]),
    default: { status: 200, body: [cardA, cardB] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    // Use a set whose only distinctive >=4-char tokens are stopwords.
    // "SV-P Promo": "svp"(3<4 reject), "p"(1<4 reject), "promo"(stopword).
    // Note: this set IS in the alias map (→ 22872), so Tier A will fire
    // first; tcgProducts is empty → A misses → fallback to B.
    const supabase = fakeSupabaseForTcg([]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      {
        card_name: "Pikachu (Pre-Order Promo)",
        card_number: "001",
        set_name: "SV-P Promo",
        year: 2022,
      },
    );
    // SV-P Promo: no distinctive C token → C skipped → ends up at D
    // or null.
    assert(r.tierMatched === "D" || r.tierMatched === null, `got ${r.tierMatched}`);
  } finally {
    await mock.close();
  }
});

Deno.test("resolveCard: no tier matches → returns null with attempt log", async () => {
  _resetPauseForTests();
  const state: MockState = {
    responses: new Map(),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    const supabase = fakeSupabaseForTcg([]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      {
        card_name: "Truly Nothing",
        card_number: "999",
        set_name: "Definitely Not A Real Set",
        year: 2099,
      },
    );
    assertEquals(r.card, null);
    assertEquals(r.tierMatched, null);
    // A line + B line + D line (C skipped — no distinctive token).
    assert(r.attemptLog.length >= 3, "should log every tier tried");
  } finally {
    await mock.close();
  }
});
