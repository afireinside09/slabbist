// supabase/functions/price-comp/persistence/market.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService } from "../types.ts";
import type { LadderPrices, PriceHistoryPoint } from "../ppt/parse.ts";

export type MarketSource = "pokemonpricetracker" | "poketrace";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  source: MarketSource;
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  priceHistory: PriceHistoryPoint[];
  pptTCGPlayerId: string;
  pptUrl: string;
  poketrace?: {
    avgCents:        number | null;
    lowCents:        number | null;
    highCents:       number | null;
    avg1dCents:      number | null;
    avg7dCents:      number | null;
    avg30dCents:     number | null;
    median3dCents:   number | null;
    median7dCents:   number | null;
    median30dCents:  number | null;
    trend:           "up" | "down" | "stable" | null;
    confidence:      "high" | "medium" | "low" | null;
    saleCount:       number | null;
  };
}

function centsToDecimal(cents: number | null): number | null {
  if (cents === null) return null;
  return Math.round(cents) / 100;
}

export async function upsertMarketLadder(
  supabase: SupabaseClient,
  input: MarketUpsertInput,
): Promise<void> {
  const isPpt = input.source === "pokemonpricetracker";
  const row: Record<string, unknown> = {
    identity_id: input.identityId,
    grading_service: input.gradingService,
    grade: input.grade,
    source: input.source,
    price_history: input.priceHistory,
    headline_price: centsToDecimal(input.headlinePriceCents),
    updated_at: new Date().toISOString(),
  };

  if (isPpt) {
    Object.assign(row, {
      ppt_tcgplayer_id: input.pptTCGPlayerId,
      ppt_url: input.pptUrl,
      loose_price:    centsToDecimal(input.ladderCents.loose),
      psa_7_price:    centsToDecimal(input.ladderCents.psa_7),
      psa_8_price:    centsToDecimal(input.ladderCents.psa_8),
      psa_9_price:    centsToDecimal(input.ladderCents.psa_9),
      psa_9_5_price:  centsToDecimal(input.ladderCents.psa_9_5),
      psa_10_price:   centsToDecimal(input.ladderCents.psa_10),
      bgs_10_price:   centsToDecimal(input.ladderCents.bgs_10),
      cgc_10_price:   centsToDecimal(input.ladderCents.cgc_10),
      sgc_10_price:   centsToDecimal(input.ladderCents.sgc_10),
    });
  } else if (input.poketrace) {
    Object.assign(row, {
      pt_avg:        centsToDecimal(input.poketrace.avgCents),
      pt_low:        centsToDecimal(input.poketrace.lowCents),
      pt_high:       centsToDecimal(input.poketrace.highCents),
      pt_avg_1d:     centsToDecimal(input.poketrace.avg1dCents),
      pt_avg_7d:     centsToDecimal(input.poketrace.avg7dCents),
      pt_avg_30d:    centsToDecimal(input.poketrace.avg30dCents),
      pt_median_3d:  centsToDecimal(input.poketrace.median3dCents),
      pt_median_7d:  centsToDecimal(input.poketrace.median7dCents),
      pt_median_30d: centsToDecimal(input.poketrace.median30dCents),
      pt_trend:      input.poketrace.trend,
      pt_confidence: input.poketrace.confidence,
      pt_sale_count: input.poketrace.saleCount,
    });
  }

  const { error } = await supabase
    .from("graded_market")
    .upsert(row, { onConflict: "identity_id,grading_service,grade,source" });
  if (error) throw new Error(`graded_market upsert: ${error.message}`);
}

export interface MarketReadResult {
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  priceHistory: PriceHistoryPoint[];
  pptTCGPlayerId: string | null;
  pptUrl: string | null;
  updatedAt: string | null;
  // Poketrace fields. Populated only when reading source='poketrace'.
  poketrace: {
    avgCents:        number | null;
    lowCents:        number | null;
    highCents:       number | null;
    avg1dCents:      number | null;
    avg7dCents:      number | null;
    avg30dCents:     number | null;
    median3dCents:   number | null;
    median7dCents:   number | null;
    median30dCents:  number | null;
    trend:           "up" | "down" | "stable" | null;
    confidence:      "high" | "medium" | "low" | null;
    saleCount:       number | null;
  } | null;
}

function decimalToCents(d: string | number | null): number | null {
  if (d === null || d === undefined) return null;
  const n = typeof d === "string" ? Number(d) : d;
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100);
}

export async function readMarketLadder(
  supabase: SupabaseClient,
  identityId: string,
  gradingService: GradingService,
  grade: string,
  source: MarketSource = "pokemonpricetracker",
): Promise<MarketReadResult | null> {
  const { data } = await supabase
    .from("graded_market")
    .select(
      "headline_price, loose_price, " +
      "psa_7_price, psa_8_price, psa_9_price, psa_9_5_price, psa_10_price, " +
      "bgs_10_price, cgc_10_price, sgc_10_price, " +
      "price_history, ppt_tcgplayer_id, ppt_url, updated_at, " +
      "pt_avg, pt_low, pt_high, pt_avg_1d, pt_avg_7d, pt_avg_30d, " +
      "pt_median_3d, pt_median_7d, pt_median_30d, " +
      "pt_trend, pt_confidence, pt_sale_count",
    )
    .eq("identity_id", identityId)
    .eq("grading_service", gradingService)
    .eq("grade", grade)
    .eq("source", source)
    .maybeSingle();
  if (!data) return null;
  const history = Array.isArray(data.price_history)
    ? (data.price_history as Array<{ ts?: unknown; price_cents?: unknown }>)
        .filter((p) => typeof p.ts === "string" && typeof p.price_cents === "number")
        .map((p) => ({ ts: p.ts as string, price_cents: p.price_cents as number }))
    : [];
  return {
    headlinePriceCents: decimalToCents(data.headline_price),
    ladderCents: {
      loose:    decimalToCents(data.loose_price),
      psa_7:    decimalToCents(data.psa_7_price),
      psa_8:    decimalToCents(data.psa_8_price),
      psa_9:    decimalToCents(data.psa_9_price),
      psa_9_5:  decimalToCents(data.psa_9_5_price),
      psa_10:   decimalToCents(data.psa_10_price),
      bgs_10:   decimalToCents(data.bgs_10_price),
      cgc_10:   decimalToCents(data.cgc_10_price),
      sgc_10:   decimalToCents(data.sgc_10_price),
    },
    priceHistory: history,
    pptTCGPlayerId: data.ppt_tcgplayer_id ?? null,
    pptUrl: data.ppt_url ?? null,
    updatedAt: data.updated_at ?? null,
    poketrace: source === "poketrace"
      ? {
          avgCents:       decimalToCents(data.pt_avg),
          lowCents:       decimalToCents(data.pt_low),
          highCents:      decimalToCents(data.pt_high),
          avg1dCents:     decimalToCents(data.pt_avg_1d),
          avg7dCents:     decimalToCents(data.pt_avg_7d),
          avg30dCents:    decimalToCents(data.pt_avg_30d),
          median3dCents:  decimalToCents(data.pt_median_3d),
          median7dCents:  decimalToCents(data.pt_median_7d),
          median30dCents: decimalToCents(data.pt_median_30d),
          trend:          (data.pt_trend ?? null) as ("up" | "down" | "stable" | null),
          confidence:     (data.pt_confidence ?? null) as ("high" | "medium" | "low" | null),
          saleCount:      typeof data.pt_sale_count === "number" ? data.pt_sale_count : null,
        }
      : null,
  };
}
