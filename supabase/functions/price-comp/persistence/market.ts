// supabase/functions/price-comp/persistence/market.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService } from "../types.ts";
import type { LadderPrices, PriceHistoryPoint } from "../ppt/parse.ts";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  priceHistory: PriceHistoryPoint[];
  pptTCGPlayerId: string;
  pptUrl: string;
}

function centsToDecimal(cents: number | null): number | null {
  if (cents === null) return null;
  return Math.round(cents) / 100;
}

export async function upsertMarketLadder(
  supabase: SupabaseClient,
  input: MarketUpsertInput,
): Promise<void> {
  const { error } = await supabase
    .from("graded_market")
    .upsert({
      identity_id: input.identityId,
      grading_service: input.gradingService,
      grade: input.grade,
      source: "pokemonpricetracker",
      ppt_tcgplayer_id: input.pptTCGPlayerId,
      ppt_url: input.pptUrl,
      headline_price: centsToDecimal(input.headlinePriceCents),
      loose_price:    centsToDecimal(input.ladderCents.loose),
      psa_7_price:    centsToDecimal(input.ladderCents.psa_7),
      psa_8_price:    centsToDecimal(input.ladderCents.psa_8),
      psa_9_price:    centsToDecimal(input.ladderCents.psa_9),
      psa_9_5_price:  centsToDecimal(input.ladderCents.psa_9_5),
      psa_10_price:   centsToDecimal(input.ladderCents.psa_10),
      bgs_10_price:   centsToDecimal(input.ladderCents.bgs_10),
      cgc_10_price:   centsToDecimal(input.ladderCents.cgc_10),
      sgc_10_price:   centsToDecimal(input.ladderCents.sgc_10),
      price_history:  input.priceHistory,
      updated_at: new Date().toISOString(),
    }, { onConflict: "identity_id,grading_service,grade" });
  if (error) throw new Error(`graded_market upsert: ${error.message}`);
}

export interface MarketReadResult {
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  priceHistory: PriceHistoryPoint[];
  pptTCGPlayerId: string | null;
  pptUrl: string | null;
  updatedAt: string | null;
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
): Promise<MarketReadResult | null> {
  const { data } = await supabase
    .from("graded_market")
    .select(
      "headline_price, loose_price, " +
      "psa_7_price, psa_8_price, psa_9_price, psa_9_5_price, psa_10_price, " +
      "bgs_10_price, cgc_10_price, sgc_10_price, " +
      "price_history, ppt_tcgplayer_id, ppt_url, updated_at",
    )
    .eq("identity_id", identityId)
    .eq("grading_service", gradingService)
    .eq("grade", grade)
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
  };
}
