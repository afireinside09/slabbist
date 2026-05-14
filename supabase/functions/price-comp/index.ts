// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
// supabase/functions/price-comp/index.ts
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PriceCompRequest, PriceCompResponse, CacheState } from "./types.ts";
import type { PoketraceBlock, ReconciledBlock, PriceCompResponseV2 } from "./types.ts";
import { extractLadder, pickTier, productUrl, ladderHasAnyPrice, parsePriceHistory, priceHistoryForTier, type LadderPrices, type PriceHistoryPoint, type PPTCard } from "./ppt/parse.ts";
import { gradeKeyFor } from "./lib/grade-key.ts";
import { fetchCard } from "./ppt/cards.ts";
import { resolveCard } from "./ppt/match.ts";
import { upsertMarketLadder, readMarketLadder } from "./persistence/market.ts";
import { persistIdentityPPTId, clearIdentityPPTId } from "./persistence/identity-product-id.ts";
import { evaluateFreshness } from "./cache/freshness.ts";
import { resolvePoketraceCardId } from "./poketrace/match.ts";
import { fetchPoketracePrices } from "./poketrace/prices.ts";
import { fetchPoketraceHistory } from "./poketrace/history.ts";
import { poketraceTierKey } from "./lib/poketrace-tier-key.ts";

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

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json" },
  });
}

function env(name: string, fallback?: string): string {
  const v = Deno.env.get(name);
  if (v !== undefined && v !== "") return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`missing env: ${name}`);
}

function buildResponse(args: {
  ladderCents: LadderPrices;
  headlineCents: number | null;
  service: GradingService;
  grade: string;
  priceHistory: PriceHistoryPoint[];
  tcgPlayerId: string;
  pptUrl: string;
  cacheHit: boolean;
  isStaleFallback: boolean;
}): PriceCompResponse {
  return {
    headline_price_cents: args.headlineCents,
    grading_service: args.service,
    grade: args.grade,
    loose_price_cents:    args.ladderCents.loose,
    psa_7_price_cents:    args.ladderCents.psa_7,
    psa_8_price_cents:    args.ladderCents.psa_8,
    psa_9_price_cents:    args.ladderCents.psa_9,
    psa_9_5_price_cents:  args.ladderCents.psa_9_5,
    psa_10_price_cents:   args.ladderCents.psa_10,
    bgs_10_price_cents:   args.ladderCents.bgs_10,
    cgc_10_price_cents:   args.ladderCents.cgc_10,
    sgc_10_price_cents:   args.ladderCents.sgc_10,
    price_history: args.priceHistory,
    ppt_tcgplayer_id: args.tcgPlayerId,
    ppt_url: args.pptUrl,
    fetched_at: new Date().toISOString(),
    cache_hit: args.cacheHit,
    is_stale_fallback: args.isStaleFallback,
  };
}

export interface HandleDeps {
  supabase: SupabaseClient | unknown;
  pptBaseUrl: string;
  pptToken: string;
  ttlSeconds: number;
  poketraceBaseUrl: string;
  poketraceApiKey: string | null; // null disables the branch
  now: () => number;
}

export async function handle(req: Request, deps: HandleDeps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: PriceCompRequest;
  try { body = (await req.json()) as PriceCompRequest; }
  catch { return json(400, { error: "invalid_json" }); }
  if (!body.graded_card_identity_id || !body.grading_service || !body.grade) {
    return json(400, { error: "missing_fields" });
  }

  const supabase = deps.supabase as SupabaseClient;

  // 1. Identity lookup
  const { data: identity, error: idErr } = await supabase
    .from("graded_card_identities").select("*")
    .eq("id", body.graded_card_identity_id).single();
  if (idErr || !identity) {
    console.error("price-comp.identity_not_found", {
      identity_id: body.graded_card_identity_id,
      pg_error: idErr?.message ?? null,
    });
    return json(404, { code: "IDENTITY_NOT_FOUND" });
  }

  // 2. Cache read
  const cached = await readMarketLadder(
    supabase,
    body.graded_card_identity_id,
    body.grading_service,
    body.grade,
    "pokemonpricetracker",
  );
  const state: CacheState = evaluateFreshness({
    updatedAtMs: cached?.updatedAt ? Date.parse(cached.updatedAt) : null,
    nowMs: deps.now(),
    ttlSeconds: deps.ttlSeconds,
  });

  if (state === "hit" && cached) {
    const pptResponse = buildResponse({
      ladderCents: cached.ladderCents,
      headlineCents: cached.headlinePriceCents,
      service: body.grading_service,
      grade: body.grade,
      priceHistory: cached.priceHistory,
      tcgPlayerId: cached.pptTCGPlayerId ?? identity.ppt_tcgplayer_id ?? "",
      pptUrl: cached.pptUrl ?? identity.ppt_url ?? "",
      cacheHit: true,
      isStaleFallback: false,
    });

    // Read cached Poketrace row separately; if fresh enough, return it
    // alongside the PPT cache hit. No upstream HTTP call here.
    const cachedPt = await readMarketLadder(
      supabase, body.graded_card_identity_id, body.grading_service, body.grade, "poketrace",
    );
    let poketraceBlock: PoketraceBlock | null = null;
    const ptState: CacheState = evaluateFreshness({
      updatedAtMs: cachedPt?.updatedAt ? Date.parse(cachedPt.updatedAt) : null,
      nowMs: deps.now(),
      ttlSeconds: deps.ttlSeconds,
    });
    // Guard: empty-string is the negative-cache sentinel ("looked, no match").
    const ptCardId = identity.poketrace_card_id ?? "";
    if (cachedPt && cachedPt.poketrace && ptState === "hit" && ptCardId !== "") {
      const tierKey = poketraceTierKey(body.grading_service, body.grade);
      poketraceBlock = {
        card_id: ptCardId,
        tier: tierKey,
        avg_cents:        cachedPt.poketrace.avgCents,
        low_cents:        cachedPt.poketrace.lowCents,
        high_cents:       cachedPt.poketrace.highCents,
        avg_1d_cents:     cachedPt.poketrace.avg1dCents,
        avg_7d_cents:     cachedPt.poketrace.avg7dCents,
        avg_30d_cents:    cachedPt.poketrace.avg30dCents,
        median_3d_cents:  cachedPt.poketrace.median3dCents,
        median_7d_cents:  cachedPt.poketrace.median7dCents,
        median_30d_cents: cachedPt.poketrace.median30dCents,
        trend:            cachedPt.poketrace.trend,
        confidence:       cachedPt.poketrace.confidence,
        sale_count:       cachedPt.poketrace.saleCount,
        tier_prices_cents: cachedPt.poketrace.tierPricesCents,
        price_history:    cachedPt.priceHistory,
        fetched_at:       cachedPt.updatedAt ?? new Date().toISOString(),
      };
    }

    // Cache-hit backfill: if PPT is fresh but Poketrace was never resolved
    // for this slab (typical of scans whose comp was fetched while the
    // Poketrace API key was unset, or while the user was on a Poketrace
    // plan tier that didn't expose graded data), run a live Poketrace
    // fetch on the cache-hit path. Persist the result so subsequent
    // cache hits read it from the DB. Failures are logged and swallowed
    // so they never poison the PPT happy path.
    if (poketraceBlock === null && deps.poketraceApiKey) {
      try {
        poketraceBlock = await fetchPoketraceBranch(
          deps,
          {
            id: identity.id,
            ppt_tcgplayer_id: identity.ppt_tcgplayer_id ?? null,
            poketrace_card_id: identity.poketrace_card_id ?? null,
            poketrace_card_id_resolved_at: identity.poketrace_card_id_resolved_at ?? null,
          },
          body.grading_service,
          body.grade,
        );
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
            console.error("poketrace.cache_hit_persist_failed", { message: (e as Error).message });
          }
        }
      } catch (e) {
        console.error("poketrace.cache_hit_backfill_failed", { message: (e as Error).message });
      }
    }

    const reconciledBlock = reconcile(pptResponse.headline_price_cents, poketraceBlock);
    const v2: PriceCompResponseV2 = { ...pptResponse, poketrace: poketraceBlock, reconciled: reconciledBlock };
    return json(200, v2);
  }

  // 3. Live fetch
  //   Warm path  (tcgPlayerId cached on identity): single fetchCard.
  //   Cold path  (no tcgPlayerId yet): multi-tier resolver runs cheap
  //     searchCards() candidates, scores them, then fetchCards the
  //     winner. See ppt/match.ts.
  const clientOpts = { token: deps.pptToken, baseUrl: deps.pptBaseUrl, now: deps.now };
  const tcgPlayerId = identity.ppt_tcgplayer_id as string | null;

  let card: PPTCard;
  let creditsConsumed: number | undefined;
  let resolverTier: string | null = null;
  let resolvedLanguage: "english" | "japanese" = "english";

  let warmPathLanguage: "english" | "japanese" | undefined;
  if (tcgPlayerId) {
    let result = await fetchCard(clientOpts, { tcgPlayerId, language: "english" });
    if (result.status === 401 || result.status === 403) {
      console.error("ppt.auth_invalid", { phase: "tcgPlayerId" });
      return json(502, { code: "AUTH_INVALID" });
    }
    if (result.status === 429 || result.status >= 500) {
      return await staleOrUpstreamDown(cached, body, `${result.status}`);
    }
    if (result.status === 200 && !result.card) {
      // English returned no card — try japanese before clearing the cached id.
      const jpResult = await fetchCard(clientOpts, { tcgPlayerId, language: "japanese" });
      if (jpResult.status === 429 || jpResult.status >= 500) {
        return await staleOrUpstreamDown(cached, body, `${jpResult.status}`);
      }
      if (jpResult.status === 200 && jpResult.card) {
        result = jpResult;
        warmPathLanguage = "japanese";
      } else {
        // Both languages null — cached id refers to a deleted/missing card.
        try { await clearIdentityPPTId(supabase, body.graded_card_identity_id); } catch { /* swallow */ }
        return json(404, { code: "NO_MARKET_DATA" });
      }
    } else {
      warmPathLanguage = "english";
    }
    if (!result.card) {
      // Non-200 status from english fetch that wasn't 429/5xx (e.g. 404).
      try { await clearIdentityPPTId(supabase, body.graded_card_identity_id); } catch { /* swallow */ }
      return json(404, { code: "NO_MARKET_DATA" });
    }
    card = result.card;
    creditsConsumed = result.creditsConsumed;
    resolvedLanguage = warmPathLanguage ?? "english";
  } else {
    const resolved = await resolveCard(
      { client: clientOpts, supabase },
      {
        card_name: identity.card_name,
        card_number: identity.card_number ?? null,
        set_name: identity.set_name,
        year: identity.year ?? null,
      },
    );
    console.log("ppt.match.resolve", {
      identity_id: body.graded_card_identity_id,
      attempts: resolved.attemptLog,
      tier: resolved.tierMatched,
    });
    if (!resolved.card) {
      // Surface attemptLog in 404 body — cheap (~1KB) and worth its
      // weight: lets the iOS / smoke harness diagnose tier misses
      // without round-tripping through edge logs. We only emit this on
      // failure paths, so it's never on the happy-path payload.
      return json(404, { code: "PRODUCT_NOT_RESOLVED", attempt_log: resolved.attemptLog });
    }
    card = resolved.card;
    resolverTier = resolved.tierMatched;
    resolvedLanguage = resolved.resolvedLanguage ?? "english";
  }
  const ladder = extractLadder(card);
  // Sparkline tracks the requested tier's history (e.g., the PSA 10 series
  // when the user scanned a PSA 10). Falls back to PSA 10 history when the
  // requested grader is unsupported (TAG, sub-PSA-7) so the card still
  // shows a meaningful trend line. Empty / missing → empty array.
  const requestedTierKey = gradeKeyFor(body.grading_service, body.grade);
  const historyTierKey = requestedTierKey ?? "psa_10";
  const history = parsePriceHistory(priceHistoryForTier(card, historyTierKey));
  if (!ladderHasAnyPrice(ladder)) {
    console.log("ppt.product.no_prices", { tcgPlayerId: card.tcgPlayerId });
    return json(404, { code: "NO_MARKET_DATA" });
  }
  const headlineCents = pickTier(card, body.grading_service, body.grade);
  const resolvedTCGPlayerId = String(card.tcgPlayerId ?? tcgPlayerId ?? "");
  const url = identity.ppt_url ?? productUrl(card);

  // First-time match — persist tcgPlayerId on identity
  if (!tcgPlayerId && resolvedTCGPlayerId) {
    try {
      await persistIdentityPPTId(supabase, body.graded_card_identity_id, resolvedTCGPlayerId, url);
      console.log("ppt.match.first_resolved", { identity_id: body.graded_card_identity_id, tcgPlayerId: resolvedTCGPlayerId });
    } catch (e) {
      console.error("ppt.persist.identity_failed", { message: (e as Error).message });
    }
  }

  try {
    await upsertMarketLadder(supabase, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service,
      grade: body.grade,
      source: "pokemonpricetracker",
      headlinePriceCents: headlineCents,
      ladderCents: ladder,
      priceHistory: history,
      pptTCGPlayerId: resolvedTCGPlayerId,
      pptUrl: url,
    });
  } catch (e) {
    console.error("ppt.persist.market_failed", { message: (e as Error).message });
  }

  console.log("price-comp.live", {
    identity_id: body.graded_card_identity_id,
    tcgPlayerId: resolvedTCGPlayerId,
    cache_state: state,
    matched: tcgPlayerId ? "cached_id" : (resolverTier ? `resolved_${resolverTier}` : "searched"),
    resolved_language: resolvedLanguage,
    headline_present: headlineCents !== null,
    history_points: history.length,
    credits_consumed: creditsConsumed ?? null,
  });

  const pptResponse = buildResponse({
    ladderCents: ladder,
    headlineCents,
    service: body.grading_service,
    grade: body.grade,
    priceHistory: history,
    tcgPlayerId: resolvedTCGPlayerId,
    pptUrl: url,
    cacheHit: false,
    isStaleFallback: false,
  });

  // V1 LIMITATION (intentional for shipping speed): the Poketrace branch
  // runs sequentially AFTER the PPT happy path completes. This means PPT
  // failures (404 NO_MARKET_DATA, AUTH_INVALID, etc.) short-circuit the
  // request before Poketrace gets a chance, so the spec's
  // 'poketrace-only' reconciliation source path is unreachable in v1.
  // Refactoring index.ts to fan out PPT into a helper and run both
  // providers via Promise.allSettled is tracked as a follow-up — see
  // spec section "V1 limitations".
  //
  // The Poketrace call has its own 8s per-fetch timeout in client.ts.
  let poketraceBlock: PoketraceBlock | null = null;
  try {
    poketraceBlock = await fetchPoketraceBranch(
      deps,
      {
        id: identity.id,
        ppt_tcgplayer_id: identity.ppt_tcgplayer_id ?? null,
        poketrace_card_id: identity.poketrace_card_id ?? null,
        poketrace_card_id_resolved_at: identity.poketrace_card_id_resolved_at ?? null,
      },
      body.grading_service,
      body.grade,
    );
  } catch (e) {
    console.error("poketrace.branch_failed", { message: (e as Error).message });
  }

  // Persist Poketrace row (fire-and-log; persistence failure does not fail the request)
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

  const reconciledBlock = reconcile(pptResponse.headline_price_cents, poketraceBlock);

  const v2: PriceCompResponseV2 = {
    ...pptResponse,
    poketrace: poketraceBlock,
    reconciled: reconciledBlock,
  };
  return json(200, v2);
}

async function staleOrUpstreamDown(
  cached: Awaited<ReturnType<typeof readMarketLadder>>,
  body: PriceCompRequest,
  marker: string,
): Promise<Response> {
  console.error("ppt.upstream_5xx", { marker });
  if (!cached) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  const pptResponse = buildResponse({
    ladderCents: cached.ladderCents,
    headlineCents: cached.headlinePriceCents,
    service: body.grading_service,
    grade: body.grade,
    priceHistory: cached.priceHistory,
    tcgPlayerId: cached.pptTCGPlayerId ?? "",
    pptUrl: cached.pptUrl ?? "",
    cacheHit: true,
    isStaleFallback: true,
  });
  const v2: PriceCompResponseV2 = {
    ...pptResponse,
    poketrace: null,
    reconciled: { headline_price_cents: cached.headlinePriceCents, source: "ppt-only" },
  };
  return json(200, v2);
}

async function fetchPoketraceBranch(
  deps: HandleDeps,
  identity: { id: string; ppt_tcgplayer_id: string | null; poketrace_card_id: string | null; poketrace_card_id_resolved_at: string | null },
  service: GradingService,
  grade: string,
): Promise<PoketraceBlock | null> {
  if (!deps.poketraceApiKey) return null;
  const client = { apiKey: deps.poketraceApiKey, baseUrl: deps.poketraceBaseUrl };
  const cardId = await resolvePoketraceCardId(
    { supabase: deps.supabase as SupabaseClient, client, now: deps.now },
    identity,
  );
  if (!cardId) return null;

  const tierKey = poketraceTierKey(service, grade);
  const [pricesRes, historyRes] = await Promise.allSettled([
    fetchPoketracePrices(client, cardId, tierKey),
    fetchPoketraceHistory(client, cardId, tierKey),
  ]);
  if (pricesRes.status === "rejected") {
    console.error("poketrace.prices_failed", { message: String(pricesRes.reason) });
  }
  if (historyRes.status === "rejected") {
    console.error("poketrace.history_failed", { message: String(historyRes.reason) });
  }

  const prices = pricesRes.status === "fulfilled" ? pricesRes.value : null;
  const history = historyRes.status === "fulfilled" ? historyRes.value.history : [];

  if (!prices || !prices.fields) return null;

  return {
    card_id: cardId,
    tier: tierKey,
    ...prices.fields,
    tier_prices_cents: prices.ladderCents,
    price_history: history,
    fetched_at: new Date().toISOString(),
  };
}

// Confidence rule for preferring Poketrace over a simple average.
// PPT's headline doesn't carry a sale-count, so we can't truly weight by
// volume — but Poketrace's saleCount is a strong signal that its number
// reflects real recent sales. When PPT and Poketrace disagree by more
// than the divergence threshold AND Poketrace has at least
// MIN_PT_SALES_FOR_PREFERENCE recent sales, treat Poketrace as the
// authoritative number.
//
// Concrete case driving these defaults: Charizard CP6 #011 (Japanese
// 20th Anniversary holo) where PPT reported $500 with no sales metadata
// and Poketrace reported $1,236 across 57 sales — averaging produced
// $868, which is closer to PPT's wrong number than to truth.
const MIN_PT_SALES_FOR_PREFERENCE = 5;
const DIVERGENCE_THRESHOLD = 0.20;

function reconcile(
  pptHeadlineCents: number | null,
  poketrace: PoketraceBlock | null,
): ReconciledBlock {
  const ptAvg = poketrace?.avg_cents ?? null;
  const ptSaleCount = poketrace?.sale_count ?? 0;

  if (pptHeadlineCents !== null && ptAvg !== null) {
    const divergence = pptHeadlineCents > 0
      ? Math.abs(ptAvg - pptHeadlineCents) / pptHeadlineCents
      : 0;
    if (ptSaleCount >= MIN_PT_SALES_FOR_PREFERENCE && divergence > DIVERGENCE_THRESHOLD) {
      return { headline_price_cents: ptAvg, source: "poketrace-preferred" };
    }
    return {
      headline_price_cents: Math.round((pptHeadlineCents + ptAvg) / 2),
      source: "avg",
    };
  }
  if (pptHeadlineCents !== null) {
    return { headline_price_cents: pptHeadlineCents, source: "ppt-only" };
  }
  if (ptAvg !== null) {
    return { headline_price_cents: ptAvg, source: "poketrace-only" };
  }
  return { headline_price_cents: null, source: "ppt-only" };
}

Deno.serve(async (req) => {
  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  const poketraceApiKey = (() => {
    try { return env("POKETRACE_API_KEY"); }
    catch { return null; }
  })();
  if (!poketraceApiKey) {
    console.warn("price-comp.poketrace_disabled", { reason: "POKETRACE_API_KEY not set" });
  }
  return await handle(req, {
    supabase,
    pptBaseUrl: "https://www.pokemonpricetracker.com",
    pptToken: env("POKEMONPRICETRACKER_API_TOKEN"),
    ttlSeconds: Number(env("POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS", "86400")),
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey,
    now: () => Date.now(),
  });
});
