// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
// supabase/functions/price-comp/persistence/market.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService } from "../types.ts";
import type { LadderPrices } from "../pricecharting/parse.ts";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  pricechartingProductId: string;
  pricechartingUrl: string;
}

// graded_market columns are numeric(12,2). Convert cents <-> dollars at the
// boundary; null cents passes through as null.
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
      source: "pricecharting",
      pricecharting_product_id: input.pricechartingProductId,
      pricecharting_url: input.pricechartingUrl,
      headline_price:  centsToDecimal(input.headlinePriceCents),
      loose_price:     centsToDecimal(input.ladderCents.loose),
      grade_7_price:   centsToDecimal(input.ladderCents.grade_7),
      grade_8_price:   centsToDecimal(input.ladderCents.grade_8),
      grade_9_price:   centsToDecimal(input.ladderCents.grade_9),
      grade_9_5_price: centsToDecimal(input.ladderCents.grade_9_5),
      psa_10_price:    centsToDecimal(input.ladderCents.psa_10),
      bgs_10_price:    centsToDecimal(input.ladderCents.bgs_10),
      cgc_10_price:    centsToDecimal(input.ladderCents.cgc_10),
      sgc_10_price:    centsToDecimal(input.ladderCents.sgc_10),
      updated_at: new Date().toISOString(),
    }, { onConflict: "identity_id,grading_service,grade" });
  if (error) throw new Error(`graded_market upsert: ${error.message}`);
}

export interface MarketReadResult {
  headlinePriceCents: number | null;
  ladderCents: LadderPrices;
  pricechartingProductId: string | null;
  pricechartingUrl: string | null;
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
      "headline_price, loose_price, grade_7_price, grade_8_price, grade_9_price, " +
      "grade_9_5_price, psa_10_price, bgs_10_price, cgc_10_price, sgc_10_price, " +
      "pricecharting_product_id, pricecharting_url, updated_at",
    )
    .eq("identity_id", identityId)
    .eq("grading_service", gradingService)
    .eq("grade", grade)
    .maybeSingle();
  if (!data) return null;
  return {
    headlinePriceCents: decimalToCents(data.headline_price),
    ladderCents: {
      loose:     decimalToCents(data.loose_price),
      grade_7:   decimalToCents(data.grade_7_price),
      grade_8:   decimalToCents(data.grade_8_price),
      grade_9:   decimalToCents(data.grade_9_price),
      grade_9_5: decimalToCents(data.grade_9_5_price),
      psa_10:    decimalToCents(data.psa_10_price),
      bgs_10:    decimalToCents(data.bgs_10_price),
      cgc_10:    decimalToCents(data.cgc_10_price),
      sgc_10:    decimalToCents(data.sgc_10_price),
    },
    pricechartingProductId: data.pricecharting_product_id ?? null,
    pricechartingUrl: data.pricecharting_url ?? null,
    updatedAt: data.updated_at ?? null,
  };
}
