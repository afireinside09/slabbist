// supabase/functions/price-comp/index.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  GradingService,
  PriceCompRequest,
  PriceCompResponse,
  CacheState,
  PoketraceBlock,
} from "./types.ts";
import { upsertMarketLadder, readMarketLadder } from "./persistence/market.ts";
import type { MarketReadResult } from "./persistence/market.ts";
import { upsertSoldListings } from "./persistence/sales.ts";
import { evaluateFreshness } from "./cache/freshness.ts";
import { resolvePoketraceCard } from "./poketrace/resolve.ts";
import { fetchPoketracePrices } from "./poketrace/prices.ts";
import { fetchPoketraceHistory } from "./poketrace/history.ts";
import { fetchPoketraceListings } from "./poketrace/listings.ts";
import { poketraceTierKey } from "./lib/poketrace-tier-key.ts";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function env(name: string, fallback?: string): string {
  const v = Deno.env.get(name);
  if (v !== undefined && v !== "") return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`missing env: ${name}`);
}

export interface HandleDeps {
  supabase: SupabaseClient | unknown;
  poketraceBaseUrl: string;
  poketraceApiKey: string | null;
  ttlSeconds: number;
  now: () => number;
  /**
   * Sold (eBay) listings are a Poketrace Scale-plan endpoint. Off Scale the
   * call 403s, so we skip it entirely unless this is true. Defaults to off.
   */
  soldListingsEnabled?: boolean;
  /** Optional fetch override for testing. Injected into the PoketraceClientOptions. */
  fetchImpl?: typeof fetch;
}

function blockToResponse(
  service: GradingService,
  grade: string,
  block: PoketraceBlock | null,
  soldListings: PriceCompResponse["sold_listings"],
  marketplaceUrl: string | null,
  cacheHit: boolean,
  tcgplayerProductId: string | null,
): PriceCompResponse {
  return {
    grading_service: service,
    grade,
    headline_price_cents: block?.avg_cents ?? null,
    poketrace: block,
    sold_listings: soldListings,
    marketplace_url: marketplaceUrl,
    tcgplayer_product_id: tcgplayerProductId,
    fetched_at: new Date().toISOString(),
    cache_hit: cacheHit,
  };
}

// Rebuild a PoketraceBlock from a cached MarketReadResult.
function toBlock(cached: MarketReadResult, service: GradingService, grade: string, cardId: string): PoketraceBlock {
  const p = cached.poketrace;
  return {
    card_id: cardId,
    tier: poketraceTierKey(service, grade),
    avg_cents: p.avgCents,
    low_cents: p.lowCents,
    high_cents: p.highCents,
    avg_1d_cents: p.avg1dCents,
    avg_7d_cents: p.avg7dCents,
    avg_30d_cents: p.avg30dCents,
    median_3d_cents: p.median3dCents,
    median_7d_cents: p.median7dCents,
    median_30d_cents: p.median30dCents,
    trend: p.trend,
    confidence: p.confidence,
    sale_count: p.saleCount,
    tier_prices_cents: p.tierPricesCents,
    price_history: cached.priceHistory,
    fetched_at: cached.updatedAt ?? new Date().toISOString(),
  };
}

// Read cached sold listings for the cache-hit path (no upstream call).
async function readSold(
  supabase: SupabaseClient,
  identityId: string,
  service: GradingService,
  grade: string,
): Promise<PriceCompResponse["sold_listings"]> {
  const { data } = await supabase
    .from("graded_market_sales")
    .select(
      "source_listing_id, title, sold_price, sold_at, grader, grade, condition, url, anomaly_flag",
    )
    .eq("identity_id", identityId)
    .eq("grading_service", service)
    .eq("grade", grade)
    .order("sold_at", { ascending: false })
    .limit(20);
  return (data ?? []).map((r) => ({
    source_listing_id: r.source_listing_id,
    title: r.title,
    price_cents:
      r.sold_price === null ? null : Math.round(Number(r.sold_price) * 100),
    sold_at:
      typeof r.sold_at === "string"
        ? r.sold_at
        : new Date(r.sold_at).toISOString(),
    grader: r.grader,
    grade: r.grade,
    condition: r.condition,
    url: r.url,
    anomaly_flag: r.anomaly_flag,
  }));
}

export async function handle(req: Request, deps: HandleDeps): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: PriceCompRequest;
  try {
    body = (await req.json()) as PriceCompRequest;
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (!body.graded_card_identity_id || !body.grading_service || !body.grade) {
    return json(400, { error: "missing_fields" });
  }

  const supabase = deps.supabase as SupabaseClient;

  // 1. Identity lookup.
  const { data: identity, error: idErr } = await supabase
    .from("graded_card_identities")
    .select("*")
    .eq("id", body.graded_card_identity_id)
    .single();
  if (idErr || !identity) return json(404, { code: "IDENTITY_NOT_FOUND" });

  // 2. Cache read + freshness.
  const cached = await readMarketLadder(
    supabase,
    body.graded_card_identity_id,
    body.grading_service,
    body.grade,
  );
  const state: CacheState = evaluateFreshness({
    updatedAtMs: cached?.updatedAt ? Date.parse(cached.updatedAt) : null,
    nowMs: deps.now(),
    ttlSeconds: deps.ttlSeconds,
  });

  if (state === "hit" && cached) {
    const block = toBlock(
      cached,
      body.grading_service,
      body.grade,
      identity.poketrace_card_id ?? "",
    );
    // Sold listings come from the table — no upstream call on cache hit.
    const sold = await readSold(
      supabase,
      body.graded_card_identity_id,
      body.grading_service,
      body.grade,
    );
    return json(
      200,
      blockToResponse(body.grading_service, body.grade, block, sold, null, true, identity.tcgplayer_product_id ?? null),
    );
  }

  if (!deps.poketraceApiKey) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  const client = {
    apiKey: deps.poketraceApiKey,
    baseUrl: deps.poketraceBaseUrl,
    ...(deps.fetchImpl ? { fetchImpl: deps.fetchImpl } : {}),
  };

  // 3. Resolve Poketrace card UUID.
  const cardId = await resolvePoketraceCard(
    { supabase, client, now: deps.now },
    {
      id: identity.id,
      card_name: identity.card_name,
      card_number: identity.card_number ?? null,
      set_name: identity.set_name,
      tcgplayer_product_id: identity.tcgplayer_product_id ?? null,
      poketrace_card_id: identity.poketrace_card_id ?? null,
      poketrace_card_id_resolved_at:
        identity.poketrace_card_id_resolved_at ?? null,
    },
  );
  if (!cardId) return json(404, { code: "PRODUCT_NOT_RESOLVED" });

  // 4. Parallel fetch: prices + history + listings.
  //    Skip listings for TAG — Poketrace's grader enum has no TAG entry.
  //    Skip entirely off the Scale plan (soldListingsEnabled) — the endpoint
  //    403s there, so calling it just adds a failing request per comp.
  const tierKey = poketraceTierKey(body.grading_service, body.grade);
  const grader = body.grading_service === "TAG" ? null : body.grading_service;

  const [pricesR, historyR, listingsR] = await Promise.allSettled([
    fetchPoketracePrices(client, cardId, tierKey),
    fetchPoketraceHistory(client, cardId, tierKey),
    grader && deps.soldListingsEnabled
      ? fetchPoketraceListings(client, cardId, grader, body.grade)
      : Promise.resolve({ status: 200, listings: [] }),
  ]);

  const prices = pricesR.status === "fulfilled" ? pricesR.value : null;
  const history = historyR.status === "fulfilled" ? historyR.value.history : [];
  const sold = listingsR.status === "fulfilled" ? listingsR.value.listings : [];

  // No graded tier aggregate AND no sold comps — nothing to surface.
  if ((!prices || !prices.fields) && sold.length === 0) {
    return json(404, { code: "NO_MARKET_DATA" });
  }

  // A slab may have sold listings but no computed graded-tier aggregate. In
  // that case `block` is null and we still return 200 with the listings so
  // iOS can render the sold-comps section (plan Task 2.7 / iOS Task 3.3).
  const block: PoketraceBlock | null = prices?.fields
    ? {
        card_id: cardId,
        tier: tierKey,
        ...prices.fields,
        tier_prices_cents: prices.ladderCents,
        price_history: history,
        fetched_at: new Date().toISOString(),
      }
    : null;

  // 5. Persist market (only when a tier aggregate exists) + sold listings.
  if (block) {
    try {
      await upsertMarketLadder(supabase, {
        identityId: body.graded_card_identity_id,
        gradingService: body.grading_service,
        grade: body.grade,
        headlinePriceCents: block.avg_cents,
        priceHistory: history,
        poketrace: {
          avgCents: block.avg_cents,
          lowCents: block.low_cents,
          highCents: block.high_cents,
          avg1dCents: block.avg_1d_cents,
          avg7dCents: block.avg_7d_cents,
          avg30dCents: block.avg_30d_cents,
          median3dCents: block.median_3d_cents,
          median7dCents: block.median_7d_cents,
          median30dCents: block.median_30d_cents,
          trend: block.trend,
          confidence: block.confidence,
          saleCount: block.sale_count,
          tierPricesCents: block.tier_prices_cents,
        },
      });
    } catch (e) {
      console.error("poketrace.persist_failed", { message: String(e) });
    }
  }
  if (sold.length) {
    try {
      await upsertSoldListings(
        supabase,
        body.graded_card_identity_id,
        body.grading_service,
        body.grade,
        sold,
      );
    } catch (e) {
      console.error("sales.persist_failed", { message: String(e) });
    }
  }

  return json(
    200,
    blockToResponse(body.grading_service, body.grade, block, sold, null, false, identity.tcgplayer_product_id ?? null),
  );
}

// Guard prevents the server from starting when this module is imported
// by tests (Deno.mainModule is only set to this file when run directly).
if (import.meta.main) Deno.serve(async (req) => {
  const supabase = createClient(
    env("SUPABASE_URL"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false } },
  );
  const poketraceApiKey = (() => {
    try {
      return env("POKETRACE_API_KEY");
    } catch {
      return null;
    }
  })();
  if (!poketraceApiKey) {
    console.warn("price-comp.poketrace_disabled", {
      reason: "POKETRACE_API_KEY not set",
    });
  }
  return await handle(req, {
    supabase,
    poketraceBaseUrl: "https://api.poketrace.com/v1",
    poketraceApiKey,
    ttlSeconds: Number(env("POKETRACE_FRESHNESS_TTL_SECONDS", "86400")),
    soldListingsEnabled: env("POKETRACE_SOLD_LISTINGS_ENABLED", "false") === "true",
    now: () => Date.now(),
  });
});
