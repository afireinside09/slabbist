// src/graded/ingest/mover-listings.ts
// One-shot ingest that hydrates `public.mover_ebay_listings` with
// the freshest active eBay listings for every card variant present
// in `public.movers`. The table is replaced wholesale per run — no
// listing history is retained, only "what eBay had during the most
// recent ingest."
//
// Pipeline per card variant:
//   1. Build a tight search query (product name + card number + set).
//   2. Fetch via Browse API (if EBAY_OAUTH_TOKEN is set) or HTML
//      scrape fallback.
//   3. Hand each candidate to the listing-matcher; only listings the
//      matcher says are positively this card are kept.
//   4. Insert into public.mover_ebay_listings with ON CONFLICT
//      DO UPDATE so duplicate listings (same itemId returned across
//      runs of overlapping queries) update in place rather than
//      blowing up.
import type { SupabaseClient } from "@supabase/supabase-js";
import { throwIfError } from "@/shared/db/supabase.js";
import type { Logger } from "@/shared/logger.js";
import { mapConcurrent } from "@/shared/concurrency.js";
import {
  fetchActiveViaBrowseApi,
  fetchActiveViaScrape,
  type ActiveListing,
} from "@/graded/sources/ebay-active.js";
import { acceptListing } from "@/graded/match/listing-matcher.js";

export interface MoverListingsOptions {
  supabase: SupabaseClient;
  userAgent: string;
  /** OAuth Bearer token for the eBay Browse API. If absent, we fall back to HTML scrape. */
  ebayToken?: string;
  /** Cap on cards processed per run; nil/0 = process all. Useful for smoke tests. */
  cardLimit?: number;
  /** How many listings to keep per card after filtering. */
  perCardLimit?: number;
  /** How many cards to process in parallel. Default 4 to be polite. */
  concurrency?: number;
  log?: Logger;
}

export interface MoverListingsResult {
  status: "completed" | "failed";
  stats: {
    cardsProcessed: number;
    cardsSkipped: number;
    listingsFetched: number;
    listingsAccepted: number;
    listingsInserted: number;
  };
  errorMessage?: string;
}

interface CardRow {
  product_id: number;
  sub_type_name: string;
  product_name: string;
  group_name: string | null;
  card_number: string | null;
}

export async function runMoverListingsIngest(
  opts: MoverListingsOptions,
): Promise<MoverListingsResult> {
  const log = opts.log;
  const concurrency = Math.max(1, opts.concurrency ?? 4);
  const perCardLimit = Math.max(1, opts.perCardLimit ?? 24);

  const stats = {
    cardsProcessed: 0,
    cardsSkipped: 0,
    listingsFetched: 0,
    listingsAccepted: 0,
    listingsInserted: 0,
  };

  try {
    log?.info("mover-listings starting", {
      hasEbayToken: Boolean(opts.ebayToken),
      cardLimit: opts.cardLimit ?? null,
      concurrency,
    });

    // Pull every distinct (product_id, sub_type_name) currently in
    // movers, joined to tcg_products + tcg_groups for the search
    // query. View executed as one round-trip.
    const cards = await fetchMoversCards(opts.supabase, opts.cardLimit);
    log?.info("cards loaded", { count: cards.length });

    // Wholesale replace — the user asked for "only the most recent
    // movers" with no historical retention.
    await throwIfError(
      opts.supabase.from("mover_ebay_listings").delete().neq("id", -1),
    );
    log?.info("table cleared");

    await mapConcurrent(cards, concurrency, async (card: CardRow) => {
      try {
        const query = buildSearchQuery(card);
        const fetched = await fetchListings(query, opts);
        stats.listingsFetched += fetched.length;

        const accepted: Array<{ listing: ActiveListing; service: string; grade: string }> = [];
        for (const listing of fetched) {
          const verdict = acceptListing(listing.title, {
            productName: card.product_name,
            cardNumber: card.card_number,
            subTypeName: card.sub_type_name,
          });
          if (!verdict.ok) continue;
          accepted.push({
            listing,
            service: verdict.gradingService,
            grade: verdict.grade,
          });
          if (accepted.length >= perCardLimit) break;
        }
        stats.listingsAccepted += accepted.length;

        if (accepted.length === 0) {
          stats.cardsSkipped += 1;
          stats.cardsProcessed += 1;
          return;
        }

        const rows = accepted.map(({ listing, service, grade }) => ({
          product_id: card.product_id,
          sub_type_name: card.sub_type_name,
          ebay_item_id: listing.ebayItemId,
          title: listing.title,
          price: listing.price,
          currency: listing.currency,
          url: listing.url,
          image_url: listing.imageUrl,
          grading_service: service,
          grade,
          buying_options: listing.buyingOptions,
          end_at: listing.endAt,
          refreshed_at: new Date().toISOString(),
        }));

        await throwIfError(
          opts.supabase
            .from("mover_ebay_listings")
            .upsert(rows, { onConflict: "product_id,sub_type_name,ebay_item_id" }),
        );
        stats.listingsInserted += rows.length;
        stats.cardsProcessed += 1;
      } catch (e) {
        // Per-card failures shouldn't sink the whole run — log and
        // move on. The card just won't have listings until the next
        // ingest.
        log?.warn("card failed", {
          productId: card.product_id,
          subType: card.sub_type_name,
          error: String((e as Error).message ?? e),
        });
        stats.cardsProcessed += 1;
        stats.cardsSkipped += 1;
      }
    });

    log?.info("mover-listings completed", { ...stats });
    return { status: "completed", stats };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    log?.error("mover-listings failed", { error: msg, ...stats });
    return { status: "failed", stats, errorMessage: msg };
  }
}

// ---------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------

async function fetchMoversCards(
  supabase: SupabaseClient,
  cardLimit?: number,
): Promise<CardRow[]> {
  // Postgres-side DISTINCT keeps the round-trip small. Join to
  // tcg_products for card_number (used by the matcher) and
  // tcg_groups for the set name (used in the eBay query).
  const { data, error } = await supabase.rpc("get_distinct_movers_for_listings", {
    p_limit: cardLimit ?? 0,
  });

  if (error) {
    // RPC not deployed yet (older DB) — fall back to a client-side
    // query. Slightly bigger payload but still tractable at ~10k
    // distinct variants.
    const { data: rows, error: queryError } = await supabase
      .from("movers")
      .select(`
        product_id,
        sub_type_name,
        product_name,
        group_name,
        tcg_products!inner ( card_number )
      `)
      .order("product_id", { ascending: true });
    if (queryError) throw queryError;
    const seen = new Set<string>();
    const out: CardRow[] = [];
    for (const row of (rows ?? []) as Array<Record<string, unknown>>) {
      const productId = row.product_id as number;
      const subType = row.sub_type_name as string;
      const key = `${productId}|${subType}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const products = row.tcg_products as Record<string, unknown> | undefined;
      out.push({
        product_id: productId,
        sub_type_name: subType,
        product_name: row.product_name as string,
        group_name: (row.group_name as string | null) ?? null,
        card_number: (products?.card_number as string | null) ?? null,
      });
      if (cardLimit && out.length >= cardLimit) break;
    }
    return out;
  }

  return (data ?? []) as CardRow[];
}

export function buildSearchQuery(card: CardRow): string {
  // Card name *without* the trailing " - <num>/<denom>" suffix so we
  // don't repeat the card number twice — eBay's relevance scoring
  // doesn't like duplication.
  const cleanName = card.product_name
    .replace(/\s*-\s*\S+\/\S+\s*$/, "")
    .replace(/\s*\(\s*[^)]*\)\s*$/, "")
    .trim();

  const parts: string[] = [];
  if (cleanName) parts.push(`"${cleanName}"`);
  if (card.card_number) parts.push(`"${card.card_number}"`);
  if (card.group_name) {
    // Strip parens from set names like "Base Set (Shadowless)" — they
    // collide with eBay's parenthesized OR-group syntax.
    const cleanSet = card.group_name.replace(/[()]/g, "").trim();
    if (cleanSet) parts.push(`"${cleanSet}"`);
  }
  // OR-group of grading-service tokens. Forces the search to graded
  // listings server-side too, not just our post-filter.
  parts.push("(PSA,BGS,CGC,SGC,graded)");
  return parts.join(" ");
}

async function fetchListings(
  query: string,
  opts: MoverListingsOptions,
): Promise<ActiveListing[]> {
  if (opts.ebayToken) {
    return fetchActiveViaBrowseApi(query, {
      token: opts.ebayToken,
      userAgent: opts.userAgent,
      limit: 50,
    });
  }
  return fetchActiveViaScrape(query, {
    userAgent: opts.userAgent,
    limit: 50,
  });
}
