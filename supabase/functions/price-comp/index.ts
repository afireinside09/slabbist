// @ts-nocheck — runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports.
// supabase/functions/price-comp/index.ts

import { createClient } from "@supabase/supabase-js";
import type {
  CacheState, GradingService, OutlierReason, PriceCompRequest, PriceCompResponse, SoldListing,
} from "./types.ts";
import { getOAuthToken } from "./ebay/oauth.ts";
import { callMarketplaceInsights } from "./ebay/marketplace-insights.ts";
import { runCascade } from "./ebay/cascade.ts";
import { high, low, mean, median } from "./stats/aggregates.ts";
import { detectOutliers, trimmedMean } from "./stats/outliers.ts";
import { confidence } from "./stats/confidence.ts";
import { evaluateFreshness } from "./cache/freshness.ts";
import { upsertMarket } from "./persistence/market.ts";
import { recordScanEvent } from "./persistence/scan-event.ts";

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

interface EnrichedListing {
  sold_price_cents: number;
  sold_at: string;
  title: string;
  url: string;
  source: "ebay";
  is_outlier: boolean;
  outlier_reason: OutlierReason;
  source_listing_id?: string;
}

interface BuildResponseArgs {
  listings: EnrichedListing[];
  sampleWindowDays: 90 | 365;
  cacheHit: boolean;
  isStaleFallback: boolean;
}

function enrichWithOutlierFlags(
  raw: Array<{ sold_price_cents: number; sold_at: string; title: string; url: string; source_listing_id?: string }>,
): EnrichedListing[] {
  if (raw.length === 0) return [];
  const prices = raw.map(l => l.sold_price_cents);
  const flags = detectOutliers(prices);
  const med = median(prices);
  return raw.map((l, i) => ({
    sold_price_cents: l.sold_price_cents,
    sold_at: l.sold_at,
    title: l.title,
    url: l.url,
    source: "ebay" as const,
    is_outlier: flags[i]!,
    outlier_reason: !flags[i] ? null : (l.sold_price_cents >= med ? "price_high" : "price_low"),
    source_listing_id: l.source_listing_id,
  }));
}

function velocityAt(listings: EnrichedListing[], cutoffMs: number): number {
  return listings.filter(l => Date.parse(l.sold_at) >= cutoffMs).length;
}

function buildResponse(args: BuildResponseArgs): PriceCompResponse {
  const { listings, sampleWindowDays, cacheHit, isStaleFallback } = args;
  const prices = listings.map(l => l.sold_price_cents);
  const flags = listings.map(l => l.is_outlier);
  const meanCents = prices.length ? mean(prices) : 0;
  const trimmedCents = prices.length ? trimmedMean(prices, flags) : 0;
  const medianCents = prices.length ? median(prices) : 0;
  const lowCents = prices.length ? low(prices) : 0;
  const highCents = prices.length ? high(prices) : 0;
  const now = new Date();
  const n = now.getTime();
  const sevenDaysAgo = n - 7 * 86400_000;
  const thirtyDaysAgo = n - 30 * 86400_000;
  const ninetyDaysAgo = n - 90 * 86400_000;
  return {
    blended_price_cents: trimmedCents,
    mean_price_cents: meanCents,
    trimmed_mean_price_cents: trimmedCents,
    median_price_cents: medianCents,
    low_price_cents: lowCents,
    high_price_cents: highCents,
    confidence: confidence(prices.length, sampleWindowDays),
    sample_count: prices.length,
    sample_window_days: sampleWindowDays,
    velocity_7d: velocityAt(listings, sevenDaysAgo),
    velocity_30d: velocityAt(listings, thirtyDaysAgo),
    velocity_90d: velocityAt(listings, ninetyDaysAgo),
    sold_listings: listings.map(({ source_listing_id: _sid, ...rest }) => rest as SoldListing),
    fetched_at: now.toISOString(),
    cache_hit: cacheHit,
    is_stale_fallback: isStaleFallback,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: PriceCompRequest;
  try { body = await req.json() as PriceCompRequest; } catch { return json(400, { error: "invalid_json" }); }
  if (!body.graded_card_identity_id || !body.grading_service || !body.grade) {
    return json(400, { error: "missing_fields" });
  }

  const serviceRole = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  const ttlSeconds = Number(env("EBAY_FRESHNESS_TTL_SECONDS", "21600"));
  const minResults = Number(env("EBAY_MIN_RESULTS_HEADLINE", "10"));

  // 1. Identity lookup (needed for query builder on miss/stale; also validates existence)
  const { data: identity, error: idErr } = await serviceRole
    .from("graded_card_identities").select("*")
    .eq("id", body.graded_card_identity_id).single();
  if (idErr || !identity) return json(404, { code: "IDENTITY_NOT_FOUND" });

  // 2. Cache read
  const { data: marketRow } = await serviceRole
    .from("graded_market")
    .select("updated_at, sample_window_days")
    .eq("identity_id", body.graded_card_identity_id)
    .eq("grading_service", body.grading_service)
    .eq("grade", body.grade)
    .maybeSingle();

  const state: CacheState = evaluateFreshness({
    updatedAtMs: marketRow?.updated_at ? Date.parse(marketRow.updated_at) : null,
    nowMs: Date.now(),
    ttlSeconds,
  });

  // 3. Cache hit — read sales and return
  if (state === "hit") {
    const { data: sales } = await serviceRole
      .from("graded_market_sales")
      .select("sold_price,sold_at,title,url,source_listing_id")
      .eq("identity_id", body.graded_card_identity_id)
      .eq("grading_service", body.grading_service)
      .eq("grade", body.grade)
      .order("sold_at", { ascending: false })
      .limit(10);
    const raw = (sales ?? []).map((s: { sold_price: string | number; sold_at: string; title: string | null; url: string | null; source_listing_id: string | null }) => ({
      sold_price_cents: Math.round(Number(s.sold_price) * 100),
      sold_at: s.sold_at,
      title: s.title ?? "",
      url: s.url ?? "",
      source_listing_id: s.source_listing_id ?? undefined,
    }));
    const enriched = enrichWithOutlierFlags(raw);
    const sampleWindowDays = (marketRow?.sample_window_days ?? 90) as 90 | 365;
    const response = buildResponse({
      listings: enriched, sampleWindowDays, cacheHit: true, isStaleFallback: false,
    });
    await recordScanEvent(serviceRole, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service as GradingService,
      grade: body.grade,
      storeId: null,
      cacheState: "hit",
    });
    return json(200, response);
  }

  // 4. Miss or stale — live fetch, with stale-fallback on upstream failure
  let token: string;
  try {
    token = await getOAuthToken({
      appId: env("EBAY_APP_ID"),
      certId: env("EBAY_CERT_ID"),
      scope: env("EBAY_OAUTH_SCOPE", "https://api.ebay.com/oauth/api_scope/buy.marketplace.insights"),
    });
  } catch (e) {
    console.error("price-comp.oauth.failed", { message: (e as Error).message });
    return await serveStaleOrUpstreamDown(serviceRole, body, state === "stale", marketRow?.sample_window_days);
  }

  let cascade;
  try {
    cascade = await runCascade(identity as never, body.grading_service as GradingService, body.grade, {
      minResults,
      fetchBucket: (q) => callMarketplaceInsights({
        token, q: q.q, categoryId: q.categoryId, limit: 50,
      }),
    });
  } catch (e) {
    console.error("price-comp.cascade.failed", { message: (e as Error).message });
    return await serveStaleOrUpstreamDown(serviceRole, body, state === "stale", marketRow?.sample_window_days);
  }

  if (cascade.listings.length === 0) {
    await recordScanEvent(serviceRole, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service as GradingService,
      grade: body.grade,
      storeId: null,
      cacheState: state === "miss" ? "miss" : "stale",
    });
    return json(404, { code: "NO_MARKET_DATA" });
  }

  const enriched = enrichWithOutlierFlags(cascade.listings.map(l => ({
    sold_price_cents: l.sold_price_cents,
    sold_at: l.sold_at,
    title: l.title,
    url: l.url,
    source_listing_id: l.source_listing_id,
  })));
  const prices = enriched.map(l => l.sold_price_cents);
  const flags = enriched.map(l => l.is_outlier);
  const meanCents = mean(prices);
  const trimmedCents = trimmedMean(prices, flags);
  const medianCents = median(prices);
  const lowCents = low(prices);
  const highCents = high(prices);

  try {
    await upsertMarket(serviceRole, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service as GradingService,
      grade: body.grade,
      listings: enriched,
      aggregates: {
        low_cents: lowCents,
        high_cents: highCents,
        mean_cents: meanCents,
        trimmed_mean_cents: trimmedCents,
        median_cents: medianCents,
        confidence: confidence(prices.length, cascade.sampleWindowDays),
        sample_window_days: cascade.sampleWindowDays,
        velocity_7d: velocityAt(enriched, Date.now() - 7 * 86400_000),
        velocity_30d: velocityAt(enriched, Date.now() - 30 * 86400_000),
        velocity_90d: velocityAt(enriched, Date.now() - 90 * 86400_000),
      },
    });
  } catch (e) {
    console.error("price-comp.persist.failed", { message: (e as Error).message });
  }

  const response = buildResponse({
    listings: enriched,
    sampleWindowDays: cascade.sampleWindowDays,
    cacheHit: false,
    isStaleFallback: false,
  });

  await recordScanEvent(serviceRole, {
    identityId: body.graded_card_identity_id,
    gradingService: body.grading_service as GradingService,
    grade: body.grade,
    storeId: null,
    cacheState: state === "miss" ? "miss" : "stale",
  });

  console.log("price-comp.live", {
    identity_id: body.graded_card_identity_id,
    bucket_hit: cascade.bucketHit,
    result_count: cascade.listings.length,
    cache_state: state,
  });

  return json(200, response);
});

async function serveStaleOrUpstreamDown(
  supabase: ReturnType<typeof createClient>,
  body: PriceCompRequest,
  hasStale: boolean,
  sampleWindowDaysHint: number | null | undefined,
): Promise<Response> {
  if (!hasStale) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  const { data: sales } = await supabase
    .from("graded_market_sales")
    .select("sold_price,sold_at,title,url,source_listing_id")
    .eq("identity_id", body.graded_card_identity_id)
    .eq("grading_service", body.grading_service)
    .eq("grade", body.grade)
    .order("sold_at", { ascending: false })
    .limit(10);
  const raw = (sales ?? []).map((s) => ({
    sold_price_cents: Math.round(Number(s.sold_price) * 100),
    sold_at: s.sold_at,
    title: s.title ?? "",
    url: s.url ?? "",
    source_listing_id: s.source_listing_id ?? undefined,
  }));
  const enriched = enrichWithOutlierFlags(raw);
  const response = buildResponse({
    listings: enriched,
    sampleWindowDays: (sampleWindowDaysHint ?? 90) as 90 | 365,
    cacheHit: true,
    isStaleFallback: true,
  });
  return json(200, response);
}
