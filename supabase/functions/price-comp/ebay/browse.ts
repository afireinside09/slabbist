// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
// supabase/functions/price-comp/ebay/browse.ts
//
// eBay Browse API client — `GET /buy/browse/v1/item_summary/search`.
// Replaces the Finding API (`findCompletedItems`), which eBay
// decommissioned on 2025-02-05.
//
// IMPORTANT — Browse returns ACTIVE listings only. eBay's only public
// surface for realized sold prices is the Marketplace Insights API, a
// Limited-Release product that requires per-application approval and
// has not been granted to this project. Until MI access is obtained,
// price-comp's "sold listings" surface is in fact a current-ask
// surface. The downstream `SoldListingRaw` shape is preserved so the
// cascade + stats pipeline keeps working; `sold_at` here is the
// listing's scheduled `itemEndDate` (when the active listing will end).
//
// Auth: requires an OAuth client-credentials token. We mint it via
// `oauth.ts` with scope `https://api.ebay.com/oauth/api_scope` (the
// public scope, no eBay approval needed).

import type { SoldListingRaw } from "../types.ts";
import { getOAuthToken } from "./oauth.ts";

const BROWSE_ENDPOINT =
  "https://api.ebay.com/buy/browse/v1/item_summary/search";
const PUBLIC_SCOPE = "https://api.ebay.com/oauth/api_scope";

interface BrowsePrice {
  value?: string;
  currency?: string;
}

interface BrowseItemSummary {
  itemId?: string;
  legacyItemId?: string;
  title?: string;
  price?: BrowsePrice;
  itemWebUrl?: string;
  itemEndDate?: string;
  buyingOptions?: string[];
}

interface BrowseSearchResponse {
  total?: number;
  itemSummaries?: BrowseItemSummary[];
  warnings?: unknown;
}

export interface BrowseCallOpts {
  appId: string;
  certId: string;
  q: string;
  categoryId: string;
  limit: number;
  /// Lookback window. Browse cannot retrieve past listings, so this
  /// drops to a no-op for active comps; we keep the parameter so the
  /// cascade signature stays unchanged. (Future: when MI access lands,
  /// this becomes the `lastSoldDate` filter window again.)
  windowDays: 90 | 365;
  fetchFn?: typeof fetch;
  now?: () => number;
}

export interface BrowseCallResult {
  status: number;
  listings: SoldListingRaw[];
}

function toCents(priceStr: string): number | null {
  const n = Number(priceStr);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 100);
}

function buildUrl(opts: Pick<BrowseCallOpts, "q" | "categoryId" | "limit">): URL {
  const url = new URL(BROWSE_ENDPOINT);
  url.searchParams.set("q", opts.q);
  url.searchParams.set("category_ids", opts.categoryId);
  // Filter to fixed-price + auction listings priced in USD; excludes
  // classified ads (which often have placeholder prices that skew the
  // distribution). Comma joins multiple filter expressions per the
  // Browse filter grammar.
  url.searchParams.set(
    "filter",
    "buyingOptions:{FIXED_PRICE|AUCTION},priceCurrency:USD",
  );
  url.searchParams.set("limit", String(Math.min(opts.limit, 200)));
  return url;
}

export async function callBrowseApi(opts: BrowseCallOpts): Promise<BrowseCallResult> {
  const { fetchFn = fetch, q, windowDays } = opts;
  const token = await getOAuthToken({
    appId: opts.appId,
    certId: opts.certId,
    scope: PUBLIC_SCOPE,
    fetchFn,
    now: opts.now,
  });
  const url = buildUrl(opts);
  const res = await fetchFn(url.toString(), {
    headers: {
      Authorization: `Bearer ${token}`,
      "X-EBAY-C-MARKETPLACE-ID": "EBAY_US",
      Accept: "application/json",
    },
  });
  if (!res.ok) {
    console.error("price-comp.browse.http_error", {
      q, windowDays, status: res.status,
    });
    return { status: res.status, listings: [] };
  }
  const data = await res.json() as BrowseSearchResponse;
  const items = data.itemSummaries ?? [];
  const listings: SoldListingRaw[] = [];
  for (const it of items) {
    const priceStr = it.price?.value;
    if (!priceStr) continue;
    if (it.price?.currency && it.price.currency !== "USD") continue;
    const cents = toCents(priceStr);
    if (cents === null) continue;
    // Browse returns *active* listings, so we don't have a sold-at
    // timestamp. `itemEndDate` is the scheduled end of the listing —
    // close enough to a recency signal for the cascade's sort + slice.
    // When the field is missing, fall back to "now" so the listing
    // still ranks but at the bottom of any tie-breaker.
    const endTime = it.itemEndDate ?? new Date(opts.now?.() ?? Date.now()).toISOString();
    listings.push({
      sold_price_cents: cents,
      sold_at: endTime,
      title: it.title ?? "",
      url: it.itemWebUrl ?? "",
      source_listing_id: it.legacyItemId ?? it.itemId ?? "",
    });
  }
  console.log("price-comp.browse.ok", {
    q, windowDays,
    raw_count: items.length,
    kept_count: listings.length,
    sample_titles: listings.slice(0, 3).map(l => l.title),
  });
  return { status: res.status, listings };
}
