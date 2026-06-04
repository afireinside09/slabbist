// supabase/functions/price-comp/persistence/sales.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, SoldListingWire } from "../types.ts";

export async function upsertSoldListings(
  supabase: SupabaseClient,
  identityId: string,
  gradingService: GradingService,
  grade: string,
  listings: SoldListingWire[],
): Promise<void> {
  if (listings.length === 0) return;
  const rows = listings.map((l) => ({
    identity_id: identityId,
    grading_service: gradingService,
    grade,
    source: "ebay",
    source_listing_id: l.source_listing_id,
    // parseListings drops any listing with a null/non-finite price, so
    // price_cents is always a finite number here.
    sold_price: Math.round(l.price_cents as number) / 100,
    sold_at: l.sold_at,
    title: l.title,
    url: l.url,
    grader: l.grader,
    condition: l.condition,
    anomaly_flag: l.anomaly_flag,
    captured_at: new Date().toISOString(),
  }));
  const { error } = await supabase
    .from("graded_market_sales")
    .upsert(rows, { onConflict: "source,source_listing_id" });
  if (error) throw new Error(`graded_market_sales upsert: ${error.message}`);
}
