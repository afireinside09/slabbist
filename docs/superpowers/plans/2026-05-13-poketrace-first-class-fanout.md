# Poketrace First-Class Fan-out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `price-comp/index.ts` so Poketrace runs as a first-class parallel source alongside PPT — PPT failures no longer block Poketrace, and first-scan cold-path cards get both sources in one request.

**Architecture:** Phase 1 runs PPT identity resolution (all PPT HTTP); Phase 2 runs PPT persistence and Poketrace HTTP in parallel via `Promise.allSettled`; Phase 3 assembles the response. Only `index.ts` changes. All other modules (`match.ts`, `prices.ts`, `history.ts`, `client.ts`, `parse.ts`, `persistence/market.ts`) stay untouched.

**Tech Stack:** Deno 2, TypeScript (`@ts-nocheck`), Supabase Edge Functions, Deno.test

---

## File Map

| File | Change |
|---|---|
| `supabase/functions/price-comp/index.ts` | Sole file modified — extract helpers, rewrite live-fetch section |
| `supabase/functions/price-comp/__tests__/index-fanout.test.ts` | Add 4 new test cases covering the new response paths |

---

### Task 1: Write failing tests for the three new response paths

Add these four tests to `supabase/functions/price-comp/__tests__/index-fanout.test.ts` **before** changing any implementation. They should fail (or not even run with expected results) with the current code.

The test file already has `makeSupabase`, `IDENTITY`, `PPT_CARD_BODY`, `POKETRACE_CARD_BODY`, `POKETRACE_HISTORY_BODY`, `POKETRACE_CARD_ID`, `makeRequest`, `withStubFetch`, and `HandleDeps` — use them as-is.

**Files:**
- Modify: `supabase/functions/price-comp/__tests__/index-fanout.test.ts`

- [ ] **Step 1: Add test — PPT cold resolver fails, Poketrace has cached UUID → 200 poketrace-only**

Append after the last existing test in the file:

```ts
Deno.test("PPT cold resolver fails, Poketrace cached UUID → 200 poketrace-only", async () => {
  _resetPauseForTests();
  // Identity: no ppt_tcgplayer_id (never resolved), but poketrace_card_id already cached.
  const identity = {
    ...IDENTITY,
    ppt_tcgplayer_id: null,
    ppt_url: null,
    poketrace_card_id: POKETRACE_CARD_ID,
    poketrace_card_id_resolved_at: "2026-05-01T00:00:00Z",
  };
  const supabase = makeSupabase({ identity: { ...identity } });

  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);
    // PPT search returns empty — resolver fails
    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(JSON.stringify([]), { status: 200, headers: { "content-type": "application/json" } }));
    }
    // Poketrace skips cross-walk (UUID already cached); card detail and history succeed
    if (url.includes("api.poketrace.com") && url.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_HISTORY_BODY), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/cards/")) {
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

  assertEquals(body.reconciled.source, "poketrace-only");
  assertEquals(body.reconciled.headline_price_cents, 19500);
  assert(body.poketrace !== null, "poketrace block must be present");
  assertEquals(body.poketrace.avg_cents, 19500);
  // PPT fields absent
  assertEquals(body.headline_price_cents, null, "no PPT headline when PPT failed");
  assertEquals(body.psa_10_price_cents, null);
});
```

- [ ] **Step 2: Add test — first cold scan: PPT resolves new ID, Poketrace cross-walks same request → 200 avg**

```ts
Deno.test("first cold scan: PPT resolves new ID, Poketrace cross-walks same request → 200 avg", async () => {
  _resetPauseForTests();
  // Brand new card — neither ID cached on identity.
  const identity = {
    ...IDENTITY,
    ppt_tcgplayer_id: null,
    ppt_url: null,
    poketrace_card_id: null,
    poketrace_card_id_resolved_at: null,
  };
  const supabase = makeSupabase({ identity: { ...identity } });

  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);
    // PPT cold: T1 search returns a match; full fetchCard follows
    if (url.includes("pokemonpricetracker.com") && url.includes("search=")) {
      return Promise.resolve(new Response(
        JSON.stringify([{ tcgPlayerId: "243172", name: "Charizard", cardNumber: "4/102", setName: "Base Set" }]),
        { status: 200, headers: { "content-type": "application/json" } },
      ));
    }
    if (url.includes("pokemonpricetracker.com") && url.includes("tcgPlayerId=243172")) {
      return Promise.resolve(new Response(JSON.stringify([PPT_CARD_BODY]), { status: 200, headers: { "content-type": "application/json" } }));
    }
    // Poketrace cross-walk: uses freshly resolved 243172
    if (url.includes("api.poketrace.com") && url.includes("tcgplayer_ids=243172")) {
      return Promise.resolve(new Response(JSON.stringify({ data: [{ id: POKETRACE_CARD_ID }] }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_HISTORY_BODY), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/cards/")) {
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

  assertEquals(body.reconciled.source, "avg");
  assert(body.poketrace !== null, "Poketrace must succeed on first cold scan using freshly resolved ID");
  assertEquals(body.poketrace.avg_cents, 19500);
  assertEquals(body.headline_price_cents, 18500, "PPT psa_10 headline");
  // Average: (18500 + 19500) / 2 = 19000
  assertEquals(body.reconciled.headline_price_cents, 19000);
});
```

- [ ] **Step 3: Add test — both fail → 404 PRODUCT_NOT_RESOLVED**

```ts
Deno.test("PPT and Poketrace both fail → 404 PRODUCT_NOT_RESOLVED", async () => {
  _resetPauseForTests();
  const identity = {
    ...IDENTITY,
    ppt_tcgplayer_id: null,
    ppt_url: null,
    poketrace_card_id: null,
    poketrace_card_id_resolved_at: null,
  };
  const supabase = makeSupabase({ identity: { ...identity } });

  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);
    // PPT resolver: all tiers return empty
    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response(JSON.stringify([]), { status: 200, headers: { "content-type": "application/json" } }));
    }
    // Poketrace cross-walk: no card found
    if (url.includes("api.poketrace.com")) {
      return Promise.resolve(new Response(JSON.stringify({ data: [] }), { status: 200, headers: { "content-type": "application/json" } }));
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
    now: () => Date.now(),
  }));
  assertEquals(resp.status, 404);
  const body = await resp.json();
  assertEquals(body.code, "PRODUCT_NOT_RESOLVED");
});
```

- [ ] **Step 4: Add test — PPT 5xx with stale cache, Poketrace succeeds → stale PPT + fresh Poketrace → avg**

```ts
Deno.test("PPT 5xx with stale cache, Poketrace succeeds → stale PPT + fresh Poketrace in response", async () => {
  _resetPauseForTests();
  const STALE_PPT_ROW = {
    identity_id: IDENTITY.id,
    grading_service: "PSA",
    grade: "10",
    source: "pokemonpricetracker",
    headline_price: 180.0,
    psa_10_price: 180.0,
    loose_price: null,
    psa_7_price: null, psa_8_price: null, psa_9_price: null, psa_9_5_price: null,
    bgs_10_price: null, cgc_10_price: null, sgc_10_price: null,
    ppt_tcgplayer_id: "243172",
    ppt_url: "https://www.pokemonpricetracker.com/card/charizard",
    price_history: [],
    updated_at: new Date(Date.now() - 2 * 86400_000).toISOString(), // stale: 2d old
  };
  const supabase = makeSupabase({ identity: { ...IDENTITY }, market: STALE_PPT_ROW });

  const stubFetch: typeof fetch = (input) => {
    const url = typeof input === "string" ? input : String((input as Request).url ?? input);
    // PPT upstream is down
    if (url.includes("pokemonpricetracker.com")) {
      return Promise.resolve(new Response("upstream down", { status: 503 }));
    }
    // Poketrace succeeds normally
    if (url.includes("api.poketrace.com") && url.includes("tcgplayer_ids=")) {
      return Promise.resolve(new Response(JSON.stringify({ data: [{ id: POKETRACE_CARD_ID }] }), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/history")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_HISTORY_BODY), { status: 200, headers: { "content-type": "application/json" } }));
    }
    if (url.includes("api.poketrace.com") && url.includes("/cards/")) {
      return Promise.resolve(new Response(JSON.stringify(POKETRACE_CARD_BODY), { status: 200, headers: { "content-type": "application/json" } }));
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
  assertEquals(body.is_stale_fallback, true, "PPT stale flag must be set");
  assertEquals(body.headline_price_cents, 18000, "stale PPT headline = $180");
  assert(body.poketrace !== null, "Poketrace must succeed despite PPT being down");
  assertEquals(body.poketrace.avg_cents, 19500);
  // Reconciled: avg of stale PPT ($180 = 18000¢) + fresh Poketrace ($195 = 19500¢)
  // (18000 + 19500) / 2 = 18750
  assertEquals(body.reconciled.source, "avg");
  assertEquals(body.reconciled.headline_price_cents, 18750);
});
```

- [ ] **Step 5: Run the new tests to confirm they currently fail**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read __tests__/index-fanout.test.ts 2>&1 | tail -30
```

Expected: the 4 new tests fail (or produce wrong results). Existing tests pass. The important thing is to see failure before implementing.

- [ ] **Step 6: Commit the failing tests**

```bash
git add supabase/functions/price-comp/__tests__/index-fanout.test.ts
git commit -m "test(price-comp): add failing tests for parallel fan-out response paths"
```

---

### Task 2: Add Phase1Result type, Phase1ShortCircuit, and PPTData to index.ts

**Files:**
- Modify: `supabase/functions/price-comp/index.ts`

These are internal types only used within `index.ts`. Add them immediately after the existing imports (around line 18, before the `json()` helper).

- [ ] **Step 1: Add the types block**

Insert after line 17 (`import { poketraceTierKey } from "./lib/poketrace-tier-key.ts";`) and before line 19 (`function json`):

```ts
// ─── Phase-split types ───────────────────────────────────────────────────────

interface PPTData {
  ladderCents: LadderPrices;
  headlineCents: number | null;
  priceHistory: PriceHistoryPoint[];
  resolvedTCGPlayerId: string;
  url: string;
  cacheHit: boolean;
  isStaleFallback: boolean;
  resolverTier: string | null;
  resolvedLanguage: "english" | "japanese";
  creditsConsumed: number | undefined;
}

interface Phase1Result {
  pptData: PPTData | null;
  freshTCGPlayerId: string | null;
  pptFailureCode: string | null;
  pptAttemptLog: string[] | null;
}

// Thrown by resolvePPTIdentity when the failure is hard (e.g. AUTH_INVALID)
// and the request must short-circuit before Phase 2.
class Phase1ShortCircuit extends Error {
  constructor(public readonly response: Response) { super("short-circuit"); }
}
```

- [ ] **Step 2: Run the test suite to verify no regressions from the type additions**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read __tests__/ 2>&1 | tail -20
```

Expected: all pre-existing tests still pass. (New tests still fail — that's correct.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/index.ts
git commit -m "feat(price-comp): add PPTData/Phase1Result/Phase1ShortCircuit types"
```

---

### Task 3: Extract resolvePPTIdentity()

This function contains all the PPT HTTP logic currently inlined in `handle()` — the warm path, cold path, language fallback, stale-fallback, and identity-persist. The logic is unchanged; it is moved into a named function and its return value is a `Phase1Result` instead of early returns from `handle()`.

**Files:**
- Modify: `supabase/functions/price-comp/index.ts`

- [ ] **Step 1: Add resolvePPTIdentity() before the handle() function**

Insert the following function immediately before the `export async function handle(` line. The function receives `supabase` explicitly (extracted from `deps`) to avoid threading all of `HandleDeps` — but `deps` is also needed for `pptBaseUrl`, `pptToken`, and `now`. Pass `deps` directly.

The `identity` parameter is typed loosely as `Record<string, unknown>` matching the DB row shape. The `cached` parameter is the PPT-source cache row (already read earlier in `handle()`).

```ts
async function resolvePPTIdentity(
  identity: Record<string, unknown>,
  body: PriceCompRequest,
  deps: HandleDeps,
  cached: Awaited<ReturnType<typeof readMarketLadder>>,
): Promise<Phase1Result> {
  const supabase = deps.supabase as SupabaseClient;
  const clientOpts = { token: deps.pptToken, baseUrl: deps.pptBaseUrl, now: deps.now };
  const tcgPlayerId = identity.ppt_tcgplayer_id as string | null;

  // ── Warm path ──────────────────────────────────────────────────────────────
  if (tcgPlayerId) {
    let result = await fetchCard(clientOpts, { tcgPlayerId, language: "english" });

    if (result.status === 401 || result.status === 403) {
      console.error("ppt.auth_invalid", { phase: "warm" });
      throw new Phase1ShortCircuit(json(502, { code: "AUTH_INVALID" }));
    }

    if (result.status === 429 || result.status >= 500) {
      console.error("ppt.upstream_5xx", { marker: String(result.status) });
      if (!cached) {
        return { pptData: null, freshTCGPlayerId: tcgPlayerId, pptFailureCode: "UPSTREAM_UNAVAILABLE", pptAttemptLog: null };
      }
      return {
        pptData: {
          ladderCents: cached.ladderCents,
          headlineCents: cached.headlinePriceCents,
          priceHistory: cached.priceHistory,
          resolvedTCGPlayerId: cached.pptTCGPlayerId ?? tcgPlayerId,
          url: cached.pptUrl ?? (identity.ppt_url as string) ?? "",
          cacheHit: true,
          isStaleFallback: true,
          resolverTier: null,
          resolvedLanguage: "english",
          creditsConsumed: undefined,
        },
        freshTCGPlayerId: tcgPlayerId,
        pptFailureCode: null,
        pptAttemptLog: null,
      };
    }

    let resolvedLanguage: "english" | "japanese" = "english";

    if (result.status === 200 && !result.card) {
      // English returned no card — try Japanese.
      const jpResult = await fetchCard(clientOpts, { tcgPlayerId, language: "japanese" });
      if (jpResult.status === 429 || jpResult.status >= 500) {
        console.error("ppt.upstream_5xx", { marker: String(jpResult.status), phase: "jp-retry" });
        if (!cached) {
          return { pptData: null, freshTCGPlayerId: tcgPlayerId, pptFailureCode: "UPSTREAM_UNAVAILABLE", pptAttemptLog: null };
        }
        return {
          pptData: {
            ladderCents: cached.ladderCents,
            headlineCents: cached.headlinePriceCents,
            priceHistory: cached.priceHistory,
            resolvedTCGPlayerId: cached.pptTCGPlayerId ?? tcgPlayerId,
            url: cached.pptUrl ?? (identity.ppt_url as string) ?? "",
            cacheHit: true,
            isStaleFallback: true,
            resolverTier: null,
            resolvedLanguage: "english",
            creditsConsumed: undefined,
          },
          freshTCGPlayerId: tcgPlayerId,
          pptFailureCode: null,
          pptAttemptLog: null,
        };
      }
      if (jpResult.status === 200 && jpResult.card) {
        result = jpResult;
        resolvedLanguage = "japanese";
      } else {
        try { await clearIdentityPPTId(supabase, body.graded_card_identity_id); } catch { /* swallow */ }
        return { pptData: null, freshTCGPlayerId: null, pptFailureCode: "NO_MARKET_DATA", pptAttemptLog: null };
      }
    } else if (!result.card) {
      try { await clearIdentityPPTId(supabase, body.graded_card_identity_id); } catch { /* swallow */ }
      return { pptData: null, freshTCGPlayerId: null, pptFailureCode: "NO_MARKET_DATA", pptAttemptLog: null };
    }

    const card = result.card!;
    const resolvedTCGPlayerId = String(card.tcgPlayerId ?? tcgPlayerId);
    return buildPPTData(card, resolvedTCGPlayerId, resolvedLanguage, null, result.creditsConsumed, identity, body);
  }

  // ── Cold path ──────────────────────────────────────────────────────────────
  const resolved = await resolveCard(
    { client: clientOpts, supabase },
    {
      card_name: identity.card_name as string,
      card_number: (identity.card_number as string | null) ?? null,
      set_name: identity.set_name as string,
      year: (identity.year as number | null) ?? null,
    },
  );
  console.log("ppt.match.resolve", {
    identity_id: body.graded_card_identity_id,
    attempts: resolved.attemptLog,
    tier: resolved.tierMatched,
  });
  if (!resolved.card) {
    return { pptData: null, freshTCGPlayerId: null, pptFailureCode: "PRODUCT_NOT_RESOLVED", pptAttemptLog: resolved.attemptLog };
  }

  const card = resolved.card;
  const resolvedTCGPlayerId = String(card.tcgPlayerId ?? "");
  const url = (identity.ppt_url as string | null) ?? productUrl(card);

  // Persist new ID immediately — Poketrace needs it in Phase 2.
  if (resolvedTCGPlayerId) {
    try {
      await persistIdentityPPTId(supabase, body.graded_card_identity_id, resolvedTCGPlayerId, url);
      console.log("ppt.match.first_resolved", { identity_id: body.graded_card_identity_id, tcgPlayerId: resolvedTCGPlayerId });
    } catch (e) {
      console.error("ppt.persist.identity_failed", { message: (e as Error).message });
    }
  }

  return buildPPTData(card, resolvedTCGPlayerId, resolved.resolvedLanguage ?? "english", resolved.tierMatched, undefined, identity, body);
}

// Pure synchronous transform: PPTCard → PPTData.
// Called from both warm and cold paths inside resolvePPTIdentity.
function buildPPTData(
  card: PPTCard,
  resolvedTCGPlayerId: string,
  resolvedLanguage: "english" | "japanese",
  resolverTier: string | null,
  creditsConsumed: number | undefined,
  identity: Record<string, unknown>,
  body: PriceCompRequest,
): Phase1Result {
  const ladder = extractLadder(card);
  const requestedTierKey = gradeKeyFor(body.grading_service, body.grade);
  const history = parsePriceHistory(priceHistoryForTier(card, requestedTierKey ?? "psa_10"));
  const url = (identity.ppt_url as string | null) ?? productUrl(card);

  if (!ladderHasAnyPrice(ladder)) {
    console.log("ppt.product.no_prices", { tcgPlayerId: resolvedTCGPlayerId });
    return { pptData: null, freshTCGPlayerId: resolvedTCGPlayerId, pptFailureCode: "NO_MARKET_DATA", pptAttemptLog: null };
  }

  const headlineCents = pickTier(card, body.grading_service, body.grade);

  console.log("price-comp.ppt.resolved", {
    identity_id: body.graded_card_identity_id,
    tcgPlayerId: resolvedTCGPlayerId,
    resolved_language: resolvedLanguage,
    resolver_tier: resolverTier,
    headline_present: headlineCents !== null,
    history_points: history.length,
    credits_consumed: creditsConsumed ?? null,
  });

  return {
    pptData: {
      ladderCents: ladder,
      headlineCents,
      priceHistory: history,
      resolvedTCGPlayerId,
      url,
      cacheHit: false,
      isStaleFallback: false,
      resolverTier,
      resolvedLanguage,
      creditsConsumed,
    },
    freshTCGPlayerId: resolvedTCGPlayerId,
    pptFailureCode: null,
    pptAttemptLog: null,
  };
}
```

- [ ] **Step 2: Run existing tests to verify the extracted function doesn't break anything yet (handle() not wired yet)**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read __tests__/ 2>&1 | tail -20
```

Expected: all pre-existing tests still pass. (New tests still fail.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/price-comp/index.ts
git commit -m "feat(price-comp): extract resolvePPTIdentity and buildPPTData helpers"
```

---

### Task 4: Rewrite handle() live-fetch section — Phase 2 + Phase 3

Replace the live-fetch section of `handle()` (currently lines ~223–431 in the original `index.ts`) with the phase-split orchestration. The cache-hit section (steps 1–2 in the current code) stays completely unchanged.

**Files:**
- Modify: `supabase/functions/price-comp/index.ts`

- [ ] **Step 1: Remove the old staleOrUpstreamDown() function**

The function currently exists as a standalone helper (lines 434–458). It is replaced by inline logic inside `resolvePPTIdentity`. Delete the entire `staleOrUpstreamDown` function block.

- [ ] **Step 2: Remove the old live-fetch section from handle() and replace with Phase 1–3**

Find the comment `// 3. Live fetch` inside `handle()` (currently around line 224). Delete everything from that comment through the final `return json(200, v2);` of the live-fetch path (just before the `staleOrUpstreamDown` function). Replace it with:

```ts
  // 3. Phase 1 — PPT identity resolution (all PPT HTTP happens here)
  let phase1: Phase1Result;
  try {
    phase1 = await resolvePPTIdentity(identity, body, deps, cached);
  } catch (e) {
    if (e instanceof Phase1ShortCircuit) return e.response;
    throw e;
  }

  // 4. Phase 2 — parallel fan-out: PPT persistence + Poketrace HTTP
  //
  // freshTCGPlayerId: use the ID that Phase 1 just resolved and persisted
  // (cold path) or confirmed still valid (warm path). Falls back to whatever
  // was on the identity at request time if Phase 1 failed. Poketrace's own
  // resolvePoketraceCardId will use it for the cross-walk when
  // poketrace_card_id is not yet cached — enabling first-scan Poketrace hits.
  const freshTCGPlayerId =
    phase1.freshTCGPlayerId ?? (identity.ppt_tcgplayer_id as string | null) ?? null;

  const [pptPersistResult, poketraceResult] = await Promise.allSettled([
    phase1.pptData && !phase1.pptData.cacheHit
      ? upsertMarketLadder(supabase, {
          identityId: body.graded_card_identity_id,
          gradingService: body.grading_service,
          grade: body.grade,
          source: "pokemonpricetracker",
          headlinePriceCents: phase1.pptData.headlineCents,
          ladderCents: phase1.pptData.ladderCents,
          priceHistory: phase1.pptData.priceHistory,
          pptTCGPlayerId: phase1.pptData.resolvedTCGPlayerId,
          pptUrl: phase1.pptData.url,
        })
      : Promise.resolve(),
    fetchPoketraceBranch(deps, {
      id: identity.id as string,
      ppt_tcgplayer_id: freshTCGPlayerId,
      poketrace_card_id: (identity.poketrace_card_id as string | null) ?? null,
      poketrace_card_id_resolved_at: (identity.poketrace_card_id_resolved_at as string | null) ?? null,
    }, body.grading_service, body.grade),
  ]);

  if (pptPersistResult.status === "rejected") {
    console.error("ppt.persist.market_failed", { message: String(pptPersistResult.reason) });
  }

  const poketraceBlock =
    poketraceResult.status === "fulfilled" ? poketraceResult.value : null;
  if (poketraceResult.status === "rejected") {
    console.error("poketrace.branch_failed", { message: String(poketraceResult.reason) });
  }

  // 5. Phase 3 — persist Poketrace, assemble response
  if (poketraceBlock) {
    try {
      await upsertMarketLadder(supabase, {
        identityId: body.graded_card_identity_id,
        gradingService: body.grading_service,
        grade: body.grade,
        source: "poketrace",
        headlinePriceCents: poketraceBlock.avg_cents,
        ladderCents: { loose: null, psa_7: null, psa_8: null, psa_9: null, psa_9_5: null, psa_10: null, bgs_10: null, cgc_10: null, sgc_10: null },
        priceHistory: poketraceBlock.price_history,
        pptTCGPlayerId: "",
        pptUrl: "",
        poketrace: {
          avgCents:       poketraceBlock.avg_cents,
          lowCents:       poketraceBlock.low_cents,
          highCents:      poketraceBlock.high_cents,
          avg1dCents:     poketraceBlock.avg_1d_cents,
          avg7dCents:     poketraceBlock.avg_7d_cents,
          avg30dCents:    poketraceBlock.avg_30d_cents,
          median3dCents:  poketraceBlock.median_3d_cents,
          median7dCents:  poketraceBlock.median_7d_cents,
          median30dCents: poketraceBlock.median_30d_cents,
          trend:          poketraceBlock.trend,
          confidence:     poketraceBlock.confidence,
          saleCount:      poketraceBlock.sale_count,
          tierPricesCents: poketraceBlock.tier_prices_cents,
        },
      });
    } catch (e) {
      console.error("poketrace.persist.market_failed", { message: (e as Error).message });
    }
  }

  // Both providers have no data — surface the most informative failure code.
  if (!phase1.pptData && !poketraceBlock) {
    return json(404, {
      code: phase1.pptFailureCode ?? "PRODUCT_NOT_RESOLVED",
      ...(phase1.pptAttemptLog ? { attempt_log: phase1.pptAttemptLog } : {}),
    });
  }

  // Build PPT response shell. When pptData is null (Poketrace-only), all PPT
  // ladder fields are null and the reconciled block carries the headline.
  const pptResponse: PriceCompResponse = phase1.pptData
    ? buildResponse({
        ladderCents: phase1.pptData.ladderCents,
        headlineCents: phase1.pptData.headlineCents,
        service: body.grading_service,
        grade: body.grade,
        priceHistory: phase1.pptData.priceHistory,
        tcgPlayerId: phase1.pptData.resolvedTCGPlayerId,
        pptUrl: phase1.pptData.url,
        cacheHit: phase1.pptData.cacheHit,
        isStaleFallback: phase1.pptData.isStaleFallback,
      })
    : {
        headline_price_cents: null,
        grading_service: body.grading_service,
        grade: body.grade,
        loose_price_cents: null, psa_7_price_cents: null, psa_8_price_cents: null,
        psa_9_price_cents: null, psa_9_5_price_cents: null, psa_10_price_cents: null,
        bgs_10_price_cents: null, cgc_10_price_cents: null, sgc_10_price_cents: null,
        price_history: poketraceBlock?.price_history ?? [],
        ppt_tcgplayer_id: "",
        ppt_url: "",
        fetched_at: new Date().toISOString(),
        cache_hit: false,
        is_stale_fallback: false,
      };

  const reconciledBlock = reconcile(pptResponse.headline_price_cents, poketraceBlock);
  const v2: PriceCompResponseV2 = { ...pptResponse, poketrace: poketraceBlock, reconciled: reconciledBlock };
  return json(200, v2);
```

- [ ] **Step 3: Run the full test suite**

```bash
cd supabase/functions/price-comp && deno test --allow-net --allow-read __tests__/ 2>&1 | tail -40
```

Expected: **all tests pass**, including the 4 new ones from Task 1 and all pre-existing tests.

If any pre-existing test fails, investigate before proceeding. Common issues:
- The `"cached id + 404 from PPT — clears the cached id, returns NO_MARKET_DATA"` test in `index.test.ts` — this has `poketraceApiKey: null`, so Poketrace is skipped, PPT warm path returns `NO_MARKET_DATA`, Phase 3 with both null returns `404 NO_MARKET_DATA`. Should pass.
- The `"upstream 5xx with cached row — returns is_stale_fallback"` test — PPT 5xx, stale cache exists, `poketraceApiKey: null`. `resolvePPTIdentity` returns stale `pptData`, Poketrace skipped. Phase 3 builds stale PPT response. Should pass.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/price-comp/index.ts
git commit -m "feat(price-comp): phase-split fan-out — Poketrace is now first-class parallel source

PPT failures (NO_MARKET_DATA, PRODUCT_NOT_RESOLVED, 5xx) no longer
short-circuit the request before Poketrace runs. First cold scan of a
new card passes the freshly resolved ppt_tcgplayer_id to Poketrace on
the same request, enabling same-scan cross-walk success."
```

---

### Task 5: Deploy and smoke test

- [ ] **Step 1: Deploy the edge function**

```bash
supabase functions deploy price-comp --project-ref ksildxueezkvrwryybln
```

Expected output ends with: `Deployed Function price-comp`

- [ ] **Step 2: Smoke test — scan a card that is known to resolve on Poketrace**

Run a request against the deployed function. Substitute `<IDENTITY_ID>` with a real `graded_card_identity_id` from your DB for a PSA 10 card that previously showed "no Poketrace data":

```bash
curl -s -X POST \
  "$(supabase functions url price-comp --project-ref ksildxueezkvrwryybln)" \
  -H "Authorization: Bearer $(supabase secrets list --project-ref ksildxueezkvrwryybln | grep SUPABASE_ANON_KEY | awk '{print $2}')" \
  -H "Content-Type: application/json" \
  -d '{"graded_card_identity_id":"<IDENTITY_ID>","grading_service":"PSA","grade":"10"}' \
  | jq '{reconciled, poketrace_null: (.poketrace == null), poketrace_avg: .poketrace.avg_cents}'
```

Expected: `poketrace_null: false` and `reconciled.source` is `"avg"` or `"poketrace-preferred"`.

- [ ] **Step 3: Verify logs for a first-cold-scan case**

If you have an identity whose `ppt_tcgplayer_id` is null (never resolved), scan it and check edge function logs:

```bash
supabase functions logs price-comp --project-ref ksildxueezkvrwryybln | grep -E "ppt.match.first_resolved|poketrace" | tail -20
```

Expected: `ppt.match.first_resolved` log line appears, followed by a Poketrace prices fetch — confirming the fresh ID was used for the cross-walk on the same scan.
