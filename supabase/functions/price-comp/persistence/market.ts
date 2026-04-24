// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
// supabase/functions/price-comp/persistence/market.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, SoldListing } from "../types.ts";

export interface MarketUpsertInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  listings: (SoldListing & { source_listing_id?: string })[];
  aggregates: {
    low_cents: number;
    high_cents: number;
    mean_cents: number;
    trimmed_mean_cents: number;
    median_cents: number;
    confidence: number;
    sample_window_days: 90 | 365;
    velocity_7d: number;
    velocity_30d: number;
    velocity_90d: number;
  };
}

// graded_market prices are numeric(12,2). Convert cents <-> dollars at the boundary.
function centsToDecimal(cents: number): number {
  return Math.round(cents) / 100;
}

export async function upsertMarket(
  supabase: SupabaseClient,
  input: MarketUpsertInput,
): Promise<void> {
  const { identityId, gradingService, grade, listings, aggregates } = input;

  if (listings.length > 0) {
    const rows = listings.map(l => ({
      identity_id: identityId,
      grading_service: gradingService,
      grade,
      sold_price: centsToDecimal(l.sold_price_cents),
      sold_at: l.sold_at,
      source: "ebay",
      source_listing_id: l.source_listing_id ?? l.url,
      title: l.title,
      url: l.url,
    }));
    const { error } = await supabase
      .from("graded_market_sales")
      .upsert(rows, { onConflict: "source,source_listing_id" });
    if (error) throw new Error(`graded_market_sales upsert: ${error.message}`);
  }

  const { error: aggError } = await supabase
    .from("graded_market")
    .upsert({
      identity_id: identityId,
      grading_service: gradingService,
      grade,
      low_price: centsToDecimal(aggregates.low_cents),
      high_price: centsToDecimal(aggregates.high_cents),
      mean_price: centsToDecimal(aggregates.mean_cents),
      trimmed_mean_price: centsToDecimal(aggregates.trimmed_mean_cents),
      median_price: centsToDecimal(aggregates.median_cents),
      confidence: aggregates.confidence,
      sample_window_days: aggregates.sample_window_days,
      sample_count_30d: aggregates.velocity_30d,
      sample_count_90d: aggregates.velocity_90d,
      last_sale_price: centsToDecimal(listings[0]?.sold_price_cents ?? 0),
      last_sale_at: listings[0]?.sold_at ?? null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "identity_id,grading_service,grade" });
  if (aggError) throw new Error(`graded_market upsert: ${aggError.message}`);
}
