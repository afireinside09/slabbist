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
  // freshTCGPlayerId: the ID that Phase 1 just resolved and persisted
  // (cold path) or confirmed still valid (warm path). Falls back to whatever
  // was on the identity at request time if Phase 1 failed. Poketrace's own
  // resolvePoketraceCardId uses it for the cross-walk when
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

  // Build PPT response shell. When pptData is null (Poketrace-only path),
  // all PPT ladder fields are null and reconciled carries the headline.
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
