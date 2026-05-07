// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
// supabase/functions/price-comp/index.ts
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PriceCompRequest, PriceCompResponse, CacheState } from "./types.ts";
import { extractLadder, pickTier, productUrl, ladderHasAnyPrice, parsePriceHistory, priceHistoryForTier, type LadderPrices, type PriceHistoryPoint, type PPTCard } from "./ppt/parse.ts";
import { gradeKeyFor } from "./lib/grade-key.ts";
import { fetchCard } from "./ppt/cards.ts";
import { resolveCard } from "./ppt/match.ts";
import { upsertMarketLadder, readMarketLadder } from "./persistence/market.ts";
import { persistIdentityPPTId, clearIdentityPPTId } from "./persistence/identity-product-id.ts";
import { evaluateFreshness } from "./cache/freshness.ts";

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
  const cached = await readMarketLadder(supabase, body.graded_card_identity_id, body.grading_service, body.grade);
  const state: CacheState = evaluateFreshness({
    updatedAtMs: cached?.updatedAt ? Date.parse(cached.updatedAt) : null,
    nowMs: deps.now(),
    ttlSeconds: deps.ttlSeconds,
  });

  if (state === "hit" && cached) {
    return json(200, buildResponse({
      ladderCents: cached.ladderCents,
      headlineCents: cached.headlinePriceCents,
      service: body.grading_service,
      grade: body.grade,
      priceHistory: cached.priceHistory,
      tcgPlayerId: cached.pptTCGPlayerId ?? identity.ppt_tcgplayer_id ?? "",
      pptUrl: cached.pptUrl ?? identity.ppt_url ?? "",
      cacheHit: true,
      isStaleFallback: false,
    }));
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

  if (tcgPlayerId) {
    const result = await fetchCard(clientOpts, { tcgPlayerId });
    if (result.status === 401 || result.status === 403) {
      console.error("ppt.auth_invalid", { phase: "tcgPlayerId" });
      return json(502, { code: "AUTH_INVALID" });
    }
    if (result.status === 429 || result.status >= 500) {
      return await staleOrUpstreamDown(cached, body, `${result.status}`);
    }
    if (!result.card) {
      // Cached id refers to a deleted card. Clear it so the next scan re-runs search.
      try { await clearIdentityPPTId(supabase, body.graded_card_identity_id); } catch { /* swallow */ }
      return json(404, { code: "NO_MARKET_DATA" });
    }
    card = result.card;
    creditsConsumed = result.creditsConsumed;
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
    headline_present: headlineCents !== null,
    history_points: history.length,
    credits_consumed: creditsConsumed ?? null,
  });

  return json(200, buildResponse({
    ladderCents: ladder,
    headlineCents,
    service: body.grading_service,
    grade: body.grade,
    priceHistory: history,
    tcgPlayerId: resolvedTCGPlayerId,
    pptUrl: url,
    cacheHit: false,
    isStaleFallback: false,
  }));
}

async function staleOrUpstreamDown(
  cached: Awaited<ReturnType<typeof readMarketLadder>>,
  body: PriceCompRequest,
  marker: string,
): Promise<Response> {
  console.error("ppt.upstream_5xx", { marker });
  if (!cached) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  return json(200, buildResponse({
    ladderCents: cached.ladderCents,
    headlineCents: cached.headlinePriceCents,
    service: body.grading_service,
    grade: body.grade,
    priceHistory: cached.priceHistory,
    tcgPlayerId: cached.pptTCGPlayerId ?? "",
    pptUrl: cached.pptUrl ?? "",
    cacheHit: true,
    isStaleFallback: true,
  }));
}

Deno.serve(async (req) => {
  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  return await handle(req, {
    supabase,
    pptBaseUrl: "https://www.pokemonpricetracker.com",
    pptToken: env("POKEMONPRICETRACKER_API_TOKEN"),
    ttlSeconds: Number(env("POKEMONPRICETRACKER_FRESHNESS_TTL_SECONDS", "86400")),
    now: () => Date.now(),
  });
});
