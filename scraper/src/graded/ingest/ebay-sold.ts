// src/graded/ingest/ebay-sold.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradedSale, GradingService } from "@/graded/models.js";
import { findOrCreateIdentity } from "@/graded/identity.js";
import { computeMarketAggregate } from "@/graded/aggregates.js";
import { ebayFetchRecentSoldViaApi, ebayFetchRecentSoldViaScrape } from "@/graded/sources/ebay.js";
import { throwIfError } from "@/shared/db/supabase.js";
import { extractIdentityFromEbayTitle } from "@/graded/title-extractor.js";
import { fetchActiveWatchlistQueries } from "@/graded/watchlist.js";

export interface EbayIngestOptions {
  supabase: SupabaseClient;
  userAgent: string;
  queries: string[];
  marketplaceInsightsToken?: string;
}

export interface EbayIngestResult {
  runId: string;
  status: "completed" | "failed";
  stats: {
    salesInserted: number;
    aggregatesTouched: number;
    queriesRun: number;
    watchlistPromoted: number;
  };
  errorMessage?: string;
}

export async function runEbaySoldIngest(opts: EbayIngestOptions): Promise<EbayIngestResult> {
  const runId = crypto.randomUUID();
  await throwIfError(opts.supabase.from("graded_ingest_runs").insert({
    id: runId, source: "ebay", status: "running", started_at: new Date().toISOString(), stats: {},
  }));

  let salesInserted = 0;
  let watchlistPromoted = 0;
  const touchedKeys = new Set<string>();

  try {
    // Promote any (identity, grading_service, grade) with >=5 distinct
    // iOS scans in the trailing 7 days onto the watchlist before we pick queries.
    // Non-fatal: if the RPC is unavailable (e.g. test harness), we keep going.
    try {
      if (typeof opts.supabase.rpc === "function") {
        const { data: promotedData, error: promoteErr } = await opts.supabase.rpc(
          "promote_scanned_slabs_to_watchlist",
          { min_scans: 5, window_days: 7 },
        );
        if (!promoteErr && typeof promotedData === "number") {
          watchlistPromoted = promotedData;
        }
      }
    } catch {
      // best-effort; continue with whatever watchlist state exists
    }

    // Caller-supplied queries override the watchlist; otherwise drive from it.
    const queries = opts.queries.length > 0
      ? opts.queries
      : await fetchActiveWatchlistQueries(opts.supabase);

    const allSales: GradedSale[] = [];
    for (const q of queries) {
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

    const stats = {
      salesInserted,
      aggregatesTouched: touchedKeys.size,
      queriesRun: queries.length,
      watchlistPromoted,
    };
    await throwIfError(opts.supabase.from("graded_ingest_runs").update({
      status: "completed", finished_at: new Date().toISOString(), stats,
    }).eq("id", runId));

    return { runId, status: "completed", stats };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    const stats = {
      salesInserted,
      aggregatesTouched: touchedKeys.size,
      queriesRun: 0,
      watchlistPromoted,
    };
    await opts.supabase.from("graded_ingest_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg, stats,
    }).eq("id", runId);
    return { runId, status: "failed", stats, errorMessage: msg };
  }
}
