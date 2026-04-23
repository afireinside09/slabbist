// src/graded/ingest/ebay-sold.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradedSale, GradingService } from "@/graded/models.js";
import { findOrCreateIdentity } from "@/graded/identity.js";
import { computeMarketAggregate } from "@/graded/aggregates.js";
import { ebayFetchRecentSoldViaApi, ebayFetchRecentSoldViaScrape } from "@/graded/sources/ebay.js";
import { throwIfError } from "@/shared/db/supabase.js";
import { extractIdentityFromEbayTitle } from "@/graded/title-extractor.js";

export interface EbayIngestOptions {
  supabase: SupabaseClient;
  userAgent: string;
  queries: string[];
  marketplaceInsightsToken?: string;
}

export interface EbayIngestResult {
  runId: string;
  status: "completed" | "failed";
  stats: { salesInserted: number; aggregatesTouched: number };
  errorMessage?: string;
}

export async function runEbaySoldIngest(opts: EbayIngestOptions): Promise<EbayIngestResult> {
  const runId = crypto.randomUUID();
  await throwIfError(opts.supabase.from("graded_ingest_runs").insert({
    id: runId, source: "ebay", status: "running", started_at: new Date().toISOString(), stats: {},
  }));

  let salesInserted = 0;
  const touchedKeys = new Set<string>();

  try {
    const allSales: GradedSale[] = [];
    for (const q of opts.queries) {
      const batch = opts.marketplaceInsightsToken
        ? await ebayFetchRecentSoldViaApi(q, { token: opts.marketplaceInsightsToken, userAgent: opts.userAgent })
        : await ebayFetchRecentSoldViaScrape(q, { userAgent: opts.userAgent });
      allSales.push(...batch);
    }

    for (const s of allSales) {
      const identity = extractIdentityFromEbayTitle(s.title, s.gradingService as GradingService, s.grade);
      const identityId = await findOrCreateIdentity(opts.supabase, identity);
      await throwIfError(opts.supabase.from("graded_market_sales").upsert(
        [{
          identity_id: identityId,
          grading_service: s.gradingService, grade: s.grade,
          source: s.source, source_listing_id: s.sourceListingId,
          sold_price: s.soldPrice, sold_at: s.soldAt,
          title: s.title, url: s.url, captured_at: new Date().toISOString(),
        }],
        { onConflict: "source,source_listing_id" },
      ));
      salesInserted += 1;
      touchedKeys.add(`${identityId}|${s.gradingService}|${s.grade}`);

      if (s.certNumber) {
        await throwIfError(opts.supabase.from("graded_cards").upsert(
          [{
            identity_id: identityId, grading_service: s.gradingService,
            cert_number: s.certNumber, grade: s.grade,
          }],
          { onConflict: "grading_service,cert_number" },
        ));
      }
    }

    for (const key of touchedKeys) {
      const [identityId, service, grade] = key.split("|");
      const { data } = await opts.supabase
        .from("graded_market_sales")
        .select("sold_price, sold_at, identity_id, grading_service, grade")
        .eq("identity_id", identityId!);
      const sales = ((data ?? []) as Array<Record<string, unknown>>).filter(
        (r) => r.grading_service === service && r.grade === grade,
      );
      const agg = computeMarketAggregate(sales.map((r) => ({
        sold_price: Number(r.sold_price), sold_at: String(r.sold_at),
      })));
      await throwIfError(opts.supabase.from("graded_market").upsert(
        [{
          identity_id: identityId, grading_service: service, grade,
          low_price: agg.lowPrice, median_price: agg.medianPrice, high_price: agg.highPrice,
          last_sale_price: agg.lastSalePrice, last_sale_at: agg.lastSaleAt,
          sample_count_30d: agg.sampleCount30d, sample_count_90d: agg.sampleCount90d,
          updated_at: new Date().toISOString(),
        }],
        { onConflict: "identity_id,grading_service,grade" },
      ));
    }

    await throwIfError(opts.supabase.from("graded_ingest_runs").update({
      status: "completed", finished_at: new Date().toISOString(),
      stats: { salesInserted, aggregatesTouched: touchedKeys.size },
    }).eq("id", runId));

    return { runId, status: "completed", stats: { salesInserted, aggregatesTouched: touchedKeys.size } };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    await opts.supabase.from("graded_ingest_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg,
      stats: { salesInserted, aggregatesTouched: touchedKeys.size },
    }).eq("id", runId);
    return { runId, status: "failed", stats: { salesInserted, aggregatesTouched: touchedKeys.size }, errorMessage: msg };
  }
}
