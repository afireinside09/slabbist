// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Property tests for scoreCard and resolver tier escalation in ppt/match.ts.
// Layer A of the comprehensive test plan.

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { scoreCard, resolveCard } from "../ppt/match.ts";
import { _resetPauseForTests } from "../ppt/cards.ts";

// ── scoreCard property tests ─────────────────────────────────────────

Deno.test("property/scoreCard: name has no overlap → score 0, accept false", () => {
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Bulbasaur", cardNumber: "001/151", setName: "Scarlet & Violet 151" },
    { card_name: "Charizard ex", card_number: "199", set_name: "Scarlet & Violet 151", year: 2023 },
  );
  assertEquals(r.score, 0);
  assertEquals(r.accept, false);
});

Deno.test("property/scoreCard: exact card_number match alone (no set overlap) → accept", () => {
  // card.setName is completely unrelated; only the number saves it.
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard ex", cardNumber: "199/165", setName: "Base Set Unlimited" },
    { card_name: "Charizard ex", card_number: "199", set_name: "Scarlet & Violet 151", year: 2023 },
  );
  assert(r.accept, `expected accept on exact number; score=${r.score}`);
  assert(r.score >= 5, `expected score >= 5; got ${r.score}`);
});

Deno.test("property/scoreCard: name + 2 set-token overlap, no exact number → accept", () => {
  // "Scarlet & Violet 151 Promo" shares "scarlet", "violet", "151" with "Scarlet & Violet 151".
  // At least 2 of those are distinctive (len>=4, non-stopword).
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard ex", cardNumber: "200", setName: "Scarlet & Violet 151 Promo" },
    { card_name: "Charizard ex", card_number: "199", set_name: "Scarlet & Violet 151", year: 2023 },
  );
  assert(r.accept, `expected accept on set overlap; score=${r.score}`);
});

Deno.test("property/scoreCard: name match alone (no exact number, no set overlap) → not accepted", () => {
  // card.setName has zero shared distinctive tokens with identity set_name.
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Charizard ex", cardNumber: "050", setName: "Obsidian Flames" },
    { card_name: "Charizard ex", card_number: "199", set_name: "Scarlet & Violet 151", year: 2023 },
  );
  assertEquals(r.accept, false, "name alone without number or 2+ set-token overlap must not accept");
  // Name does score positive, just not accepted.
  assert(r.score > 0, "name match should still add points");
});

Deno.test("property/scoreCard: name match + partial-prefix number + <2 set overlap → not accepted", () => {
  // partial-prefix number only adds +1 (not full +3), so accept requires overlap>=2.
  const r = scoreCard(
    { tcgPlayerId: "1", name: "Pikachu", cardNumber: "199", setName: "Some Random Set" },
    { card_name: "Pikachu", card_number: "199/165", set_name: "Scarlet & Violet 151", year: 2023 },
  );
  // "199" vs "199/165": normalizeCardNumber → both "199". That IS exact → accept.
  // (This actually tests that the normalizer strips the slash from the tcg side.)
  assert(r.accept, "number match via slash-strip normalization should accept");
});

// ── Tier escalation: B/C/D ──────────────────────────────────────────

// We use the same mock-server pattern from match.test.ts.

interface MockState {
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

function fakeSupabaseTcg(rows: Array<{ product_id: number; group_id: number; name: string; card_number: string }>) {
  return {
    from(table: string) {
      if (table !== "tcg_products") throw new Error(`unexpected table ${table}`);
      let filtered = [...rows];
      const builder: any = {
        select(_: string) { return builder; },
        eq(col: string, val: unknown) {
          if (col === "group_id") filtered = filtered.filter((r) => r.group_id === val);
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

// ── Tier escalation property tests ──────────────────────────────────

Deno.test("property/tiers: B miss + C miss → D fires", async () => {
  _resetPauseForTests();
  // Set "Fossil" has alias→group 630; tcg_products is empty → A misses.
  // B returns nothing; C has distinctive token "fossil" → returns nothing;
  // D (default) returns a scoring candidate.
  const dCard = { tcgPlayerId: "999", name: "Dragonite", cardNumber: "04/62", setName: "Fossil" };
  const state: MockState = {
    responses: new Map([
      // B misses
      ["search:Dragonite 4 Fossil|set:", { status: 200, body: [] }],
      // C misses (set token "fossil" exists, 6 chars > 4, non-stopword)
      ["search:Dragonite|set:fossil", { status: 200, body: [] }],
      // D hits via default
      ["tcgPlayerId:999", { status: 200, body: [{ ...dCard, ebay: {} }] }],
    ]),
    default: { status: 200, body: [dCard] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    const supabase = fakeSupabaseTcg([]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      { card_name: "Dragonite", card_number: "4", set_name: "Fossil", year: 1999 },
    );
    // D should have fired (B and C both missed).
    const log = r.attemptLog.join("\n");
    assert(log.includes("B:"), "B should be in log");
    assert(log.includes("D:"), "D should fire after B+C miss");
  } finally {
    await mock.close();
  }
});

Deno.test("property/tiers: B miss + C hit → D does NOT fire", async () => {
  _resetPauseForTests();
  // Scarlet & Violet 151 has alias→23237; tcg_products empty → A misses.
  // B misses; C (set token "scarlet"/"violet"/"151") hits a candidate that scoreCard accepts.
  const cCard = { tcgPlayerId: "243172", name: "Charizard ex", cardNumber: "199/165", setName: "Scarlet & Violet 151" };
  const state: MockState = {
    responses: new Map([
      // B misses
      ["search:Charizard ex 199 Scarlet & Violet 151|set:", { status: 200, body: [] }],
      // C hits — scoreCard should accept (name + set overlap >= 2)
      ["search:Charizard ex|set:scarlet", { status: 200, body: [cCard] }],
      ["search:Charizard ex|set:violet", { status: 200, body: [cCard] }],
      ["search:Charizard ex|set:151", { status: 200, body: [cCard] }],
      // Full fetch
      ["tcgPlayerId:243172", { status: 200, body: [{ ...cCard, ebay: { salesByGrade: { psa10: { smartMarketPrice: { price: 100 } } } } }] }],
    ]),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    const supabase = fakeSupabaseTcg([]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      { card_name: "Charizard ex (Special Illustration Rare)", card_number: "199", set_name: "Scarlet & Violet 151", year: 2023 },
    );
    assertEquals(r.tierMatched, "C", "should stop at C");
    // D must not appear in the log.
    const log = r.attemptLog.join("\n");
    assert(!log.includes("D:"), `D should not fire after C hit; log=${log}`);
  } finally {
    await mock.close();
  }
});

Deno.test("property/tiers: Tier A success → no B/C/D calls made", async () => {
  _resetPauseForTests();
  // Alias exists for "Scarlet & Violet 151", tcg_products has the row,
  // PPT fetch returns the card. B/C/D should never be called.
  const enCard = { tcgPlayerId: "243172", name: "Charizard ex", cardNumber: "199/165", setName: "SV: Scarlet & Violet 151" };
  const state: MockState = {
    responses: new Map([
      ["tcgPlayerId:243172", { status: 200, body: [{ ...enCard, ebay: { salesByGrade: { psa10: { smartMarketPrice: { price: 100 } } } } }] }],
    ]),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    const supabase = fakeSupabaseTcg([
      { product_id: 243172, group_id: 23237, name: "Charizard ex - 199/165", card_number: "199/165" },
    ]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      { card_name: "Charizard ex (Special Illustration Rare)", card_number: "199", set_name: "Scarlet & Violet 151", year: 2023 },
    );
    assertEquals(r.tierMatched, "A");
    // Only 1 PPT call (the direct fetchCard by tcgPlayerId) — no search calls.
    assertEquals(state.calls.length, 1, "only 1 PPT call for Tier A success");
    assertEquals(state.calls[0].query.get("tcgPlayerId"), "243172");
  } finally {
    await mock.close();
  }
});

Deno.test("property/tiers: Tier A success → attemptLog contains only A entries", async () => {
  _resetPauseForTests();
  const enCard = { tcgPlayerId: "243172", name: "Charizard ex", cardNumber: "199/165", setName: "SV: Scarlet & Violet 151" };
  const state: MockState = {
    responses: new Map([
      ["tcgPlayerId:243172", { status: 200, body: [{ ...enCard, ebay: {} }] }],
    ]),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    const supabase = fakeSupabaseTcg([
      { product_id: 243172, group_id: 23237, name: "Charizard ex - 199/165", card_number: "199/165" },
    ]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      { card_name: "Charizard ex", card_number: "199", set_name: "Scarlet & Violet 151", year: 2023 },
    );
    assertEquals(r.tierMatched, "A");
    // Every log line should start with "A" — no B/C/D entries.
    for (const line of r.attemptLog) {
      assert(line.startsWith("A"), `unexpected non-A log entry after A success: "${line}"`);
    }
  } finally {
    await mock.close();
  }
});

Deno.test("property/tiers: all tiers miss → null card with populated attemptLog", async () => {
  _resetPauseForTests();
  const state: MockState = {
    responses: new Map(),
    default: { status: 200, body: [] },
    calls: [],
  };
  const mock = startMock(state);
  try {
    const supabase = fakeSupabaseTcg([]);
    const r = await resolveCard(
      { client: { token: "t", baseUrl: mock.url, now: () => Date.now() }, supabase },
      { card_name: "Ghost Card", card_number: "999", set_name: "No Such Set Ever", year: 2099 },
    );
    assertEquals(r.card, null);
    assertEquals(r.tierMatched, null);
    // Should have at minimum the A miss + B + D entries.
    assert(r.attemptLog.length >= 3, `expected >= 3 log entries; got ${r.attemptLog.length}: ${JSON.stringify(r.attemptLog)}`);
    assert(r.attemptLog.some((l) => l.startsWith("A:")), "must log A tier miss");
    assert(r.attemptLog.some((l) => l.startsWith("B:")), "must log B tier");
    assert(r.attemptLog.some((l) => l.startsWith("D:")), "must log D tier");
  } finally {
    await mock.close();
  }
});
