// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
// supabase/functions/price-comp/index.ts
import { createClient } from "@supabase/supabase-js";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PriceCompRequest, PriceCompResponse, CacheState } from "./types.ts";
import type { LadderPrices, PCProductRow } from "./pricecharting/parse.ts";
import { extractLadder, pickTier, productUrl, ladderHasAnyPrice } from "./pricecharting/parse.ts";
import { searchProducts } from "./pricecharting/search.ts";
import { getProduct } from "./pricecharting/product.ts";
import { upsertMarketLadder, readMarketLadder } from "./persistence/market.ts";
import { persistIdentityProductId, clearIdentityProductId } from "./persistence/identity-product-id.ts";
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

function ladderToCents(ladder: LadderPrices): LadderPrices {
  // ladder is already in pennies (PriceCharting native unit) — pass through.
  // The function name is for clarity at the call site; no transform needed.
  return ladder;
}

function buildSearchQuery(identity: {
  card_name: string;
  card_number: string | null;
  set_name: string;
  year: number | null;
}): string {
  const parts: string[] = [];
  parts.push(`"${identity.card_name}"`);
  if (identity.card_number) parts.push(`"${identity.card_number}"`);
  parts.push(identity.set_name);
  if (identity.year !== null) parts.push(String(identity.year));
  return parts.join(" ");
}

function buildResponse(args: {
  ladderCents: LadderPrices;
  headlineCents: number | null;
  service: GradingService;
  grade: string;
  productId: string;
  productUrl: string;
  cacheHit: boolean;
  isStaleFallback: boolean;
}): PriceCompResponse {
  return {
    headline_price_cents: args.headlineCents,
    grading_service: args.service,
    grade: args.grade,
    loose_price_cents:     args.ladderCents.loose,
    grade_7_price_cents:   args.ladderCents.grade_7,
    grade_8_price_cents:   args.ladderCents.grade_8,
    grade_9_price_cents:   args.ladderCents.grade_9,
    grade_9_5_price_cents: args.ladderCents.grade_9_5,
    psa_10_price_cents:    args.ladderCents.psa_10,
    bgs_10_price_cents:    args.ladderCents.bgs_10,
    cgc_10_price_cents:    args.ladderCents.cgc_10,
    sgc_10_price_cents:    args.ladderCents.sgc_10,
    pricecharting_product_id: args.productId,
    pricecharting_url: args.productUrl,
    fetched_at: new Date().toISOString(),
    cache_hit: args.cacheHit,
    is_stale_fallback: args.isStaleFallback,
  };
}

export interface HandleDeps {
  supabase: SupabaseClient | unknown;
  pricechartingBaseUrl: string;
  pricechartingToken: string;
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
      ladderCents: ladderToCents(cached.ladderCents),
      headlineCents: cached.headlinePriceCents,
      service: body.grading_service,
      grade: body.grade,
      productId: cached.pricechartingProductId ?? identity.pricecharting_product_id ?? "",
      productUrl: cached.pricechartingUrl ?? identity.pricecharting_url ?? "",
      cacheHit: true,
      isStaleFallback: false,
    }));
  }

  // 3. Resolve PriceCharting product id (hybrid)
  const clientOpts = {
    token: deps.pricechartingToken,
    baseUrl: deps.pricechartingBaseUrl,
    now: deps.now,
  };

  let productId = identity.pricecharting_product_id as string | null;
  if (!productId) {
    const q = buildSearchQuery(identity);
    const search = await searchProducts(clientOpts, q);
    if (search.status >= 500) {
      return await staleOrUpstreamDown(cached, body, "5xx_search");
    }
    if (search.status === 401 || search.status === 403) {
      console.error("pc.auth_invalid", { phase: "search" });
      return json(502, { code: "AUTH_INVALID" });
    }
    if (search.products.length === 0) {
      console.log("pc.match.zero_hits", { q });
      return json(404, { code: "PRODUCT_NOT_RESOLVED" });
    }
    const top = search.products[0];
    productId = String(top.id ?? "");
    if (!productId) return json(404, { code: "PRODUCT_NOT_RESOLVED" });
    const url = productUrl(top);
    try {
      await persistIdentityProductId(supabase, body.graded_card_identity_id, productId, url);
      console.log("pc.match.first_resolved", { identity_id: body.graded_card_identity_id, product_id: productId });
    } catch (e) {
      console.error("pc.persist.identity_failed", { message: (e as Error).message });
    }
  }

  // 4. Live fetch product
  const product = await getProduct(clientOpts, productId);
  if (product.status === 401 || product.status === 403) {
    console.error("pc.auth_invalid", { phase: "product" });
    return json(502, { code: "AUTH_INVALID" });
  }
  if (product.status === 404) {
    // Cached id pointing at a deleted product. Clear it so the next scan
    // re-runs search.
    if (identity.pricecharting_product_id) {
      try { await clearIdentityProductId(supabase, body.graded_card_identity_id); } catch { /* swallow */ }
    }
    return json(404, { code: "NO_MARKET_DATA" });
  }
  if (product.status === 429 || product.status >= 500) {
    return await staleOrUpstreamDown(cached, body, `${product.status}_product`);
  }
  if (!product.product) {
    return json(404, { code: "NO_MARKET_DATA" });
  }

  const row: PCProductRow = product.product;
  const ladder = extractLadder(row);
  if (!ladderHasAnyPrice(ladder)) {
    console.log("pc.product.no_prices", { product_id: productId });
    return json(404, { code: "NO_MARKET_DATA" });
  }
  const headlineCents = pickTier(row, body.grading_service, body.grade);
  const url = identity.pricecharting_url ?? productUrl(row);

  try {
    await upsertMarketLadder(supabase, {
      identityId: body.graded_card_identity_id,
      gradingService: body.grading_service,
      grade: body.grade,
      headlinePriceCents: headlineCents,
      ladderCents: ladder,
      pricechartingProductId: productId,
      pricechartingUrl: url,
    });
  } catch (e) {
    console.error("pc.persist.market_failed", { message: (e as Error).message });
  }

  console.log("price-comp.live", {
    identity_id: body.graded_card_identity_id,
    product_id: productId,
    cache_state: state,
    headline_present: headlineCents !== null,
  });

  return json(200, buildResponse({
    ladderCents: ladder,
    headlineCents,
    service: body.grading_service,
    grade: body.grade,
    productId,
    productUrl: url,
    cacheHit: false,
    isStaleFallback: false,
  }));
}

async function staleOrUpstreamDown(
  cached: Awaited<ReturnType<typeof readMarketLadder>>,
  body: PriceCompRequest,
  marker: string,
): Promise<Response> {
  console.error("pc.upstream_5xx", { marker });
  if (!cached) return json(503, { code: "UPSTREAM_UNAVAILABLE" });
  return json(200, buildResponse({
    ladderCents: cached.ladderCents,
    headlineCents: cached.headlinePriceCents,
    service: body.grading_service,
    grade: body.grade,
    productId: cached.pricechartingProductId ?? "",
    productUrl: cached.pricechartingUrl ?? "",
    cacheHit: true,
    isStaleFallback: true,
  }));
}

// Production entrypoint. Tests import `handle` directly with injected deps.
Deno.serve(async (req) => {
  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
  return await handle(req, {
    supabase,
    pricechartingBaseUrl: "https://www.pricecharting.com",
    pricechartingToken: env("PRICECHARTING_API_TOKEN"),
    ttlSeconds: Number(env("PRICECHARTING_FRESHNESS_TTL_SECONDS", "86400")),
    now: () => Date.now(),
  });
});
