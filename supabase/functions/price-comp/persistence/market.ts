// supabase/functions/price-comp/persistence/market.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Poketrace-only market persistence. PPT ladder + dual-source branching removed.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PriceHistoryWirePoint } from "../types.ts";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  headlinePriceCents: number | null;
  priceHistory: PriceHistoryWirePoint[];
  poketrace: {
    avgCents: number | null;
    lowCents: number | null;
    highCents: number | null;
    avg1dCents: number | null;
    avg7dCents: number | null;
    avg30dCents: number | null;
    median3dCents: number | null;
    median7dCents: number | null;
    median30dCents: number | null;
    trend: "up" | "down" | "stable" | null;
    confidence: "high" | "medium" | "low" | null;
    saleCount: number | null;
    tierPricesCents: Record<string, number>;
  };
}

const c2d = (c: number | null): number | null =>
  c === null ? null : Math.round(c) / 100;

const d2c = (d: string | number | null | undefined): number | null => {
  if (d === null || d === undefined) return null;
  const n = typeof d === "string" ? Number(d) : d;
  return Number.isFinite(n) ? Math.round(n * 100) : null;
};

export async function upsertMarketLadder(
  supabase: SupabaseClient,
  input: MarketUpsertInput,
): Promise<void> {
  const row = {
    identity_id: input.identityId,
    grading_service: input.gradingService,
    grade: input.grade,
    source: "poketrace",
    headline_price: c2d(input.headlinePriceCents),
    price_history: input.priceHistory,
    pt_avg: c2d(input.poketrace.avgCents),
    pt_low: c2d(input.poketrace.lowCents),
    pt_high: c2d(input.poketrace.highCents),
    pt_avg_1d: c2d(input.poketrace.avg1dCents),
    pt_avg_7d: c2d(input.poketrace.avg7dCents),
    pt_avg_30d: c2d(input.poketrace.avg30dCents),
    pt_median_3d: c2d(input.poketrace.median3dCents),
    pt_median_7d: c2d(input.poketrace.median7dCents),
    pt_median_30d: c2d(input.poketrace.median30dCents),
    pt_trend: input.poketrace.trend,
    pt_confidence: input.poketrace.confidence,
    pt_sale_count: input.poketrace.saleCount,
    pt_tier_prices_cents: input.poketrace.tierPricesCents,
    updated_at: new Date().toISOString(),
  };
  const { error } = await supabase
    .from("graded_market")
    .upsert(row, { onConflict: "identity_id,grading_service,grade,source" });
  if (error) throw new Error(`graded_market upsert: ${error.message}`);
}

export interface MarketReadResult {
  headlinePriceCents: number | null;
  priceHistory: PriceHistoryWirePoint[];
  updatedAt: string | null;
  poketrace: {
    avgCents: number | null;
    lowCents: number | null;
    highCents: number | null;
    avg1dCents: number | null;
    avg7dCents: number | null;
    avg30dCents: number | null;
    median3dCents: number | null;
    median7dCents: number | null;
    median30dCents: number | null;
    trend: "up" | "down" | "stable" | null;
    confidence: "high" | "medium" | "low" | null;
    saleCount: number | null;
    tierPricesCents: Record<string, number>;
  };
}

export async function readMarketLadder(
  supabase: SupabaseClient,
  identityId: string,
  gradingService: GradingService,
  grade: string,
): Promise<MarketReadResult | null> {
  const { data } = await supabase
    .from("graded_market")
    .select(
      "headline_price, price_history, updated_at, pt_avg, pt_low, pt_high, " +
      "pt_avg_1d, pt_avg_7d, pt_avg_30d, pt_median_3d, pt_median_7d, pt_median_30d, " +
      "pt_trend, pt_confidence, pt_sale_count, pt_tier_prices_cents",
    )
    .eq("identity_id", identityId)
    .eq("grading_service", gradingService)
    .eq("grade", grade)
    .eq("source", "poketrace")
    .maybeSingle();
  if (!data) return null;
  const history = Array.isArray(data.price_history)
    ? (data.price_history as Array<{ ts?: unknown; price_cents?: unknown }>)
        .filter((p) => typeof p.ts === "string" && typeof p.price_cents === "number")
        .map((p) => ({ ts: p.ts as string, price_cents: p.price_cents as number }))
    : [];
  return {
    headlinePriceCents: d2c(data.headline_price),
    priceHistory: history,
    updatedAt: data.updated_at ?? null,
    poketrace: {
      avgCents: d2c(data.pt_avg),
      lowCents: d2c(data.pt_low),
      highCents: d2c(data.pt_high),
      avg1dCents: d2c(data.pt_avg_1d),
      avg7dCents: d2c(data.pt_avg_7d),
      avg30dCents: d2c(data.pt_avg_30d),
      median3dCents: d2c(data.pt_median_3d),
      median7dCents: d2c(data.pt_median_7d),
      median30dCents: d2c(data.pt_median_30d),
      trend: (data.pt_trend ?? null) as ("up" | "down" | "stable" | null),
      confidence: (data.pt_confidence ?? null) as ("high" | "medium" | "low" | null),
      saleCount: typeof data.pt_sale_count === "number" ? data.pt_sale_count : null,
      tierPricesCents: parseTierPricesCents(data.pt_tier_prices_cents),
    },
  };
}

/**
 * Defensive decoder for the JSONB `pt_tier_prices_cents` column.
 * Throws away keys whose values aren't finite numbers; returns `{}` when
 * the column is null or malformed.
 */
function parseTierPricesCents(value: unknown): Record<string, number> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const out: Record<string, number> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (typeof v === "number" && Number.isFinite(v)) out[k] = Math.round(v);
  }
  return out;
}
