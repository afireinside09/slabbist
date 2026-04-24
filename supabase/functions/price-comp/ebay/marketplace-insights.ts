// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
// supabase/functions/price-comp/ebay/marketplace-insights.ts
import type { SoldListingRaw } from "../types.ts";

const MI_ENDPOINT = "https://api.ebay.com/buy/marketplace_insights/v1_beta/item_sales/search";

interface MIItemSale {
  itemId: string;
  title: string;
  lastSoldDate: string;
  lastSoldPrice: { value: string; currency: string };
  itemWebUrl: string;
}

interface MIResponse {
  itemSales?: MIItemSale[];
}

export interface MICallOpts {
  token: string;
  q: string;
  categoryId: string;
  limit: number;
  fetchFn?: typeof fetch;
}

export interface MICallResult {
  status: number;
  listings: SoldListingRaw[];
}

function toCents(priceStr: string): number | null {
  const n = Number(priceStr);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 100);
}

function listingIdFromItemId(itemId: string): string {
  const parts = itemId.split("|");
  return parts[1] ?? itemId;
}

export async function callMarketplaceInsights(opts: MICallOpts): Promise<MICallResult> {
  const { token, q, categoryId, limit, fetchFn = fetch } = opts;
  const url = new URL(MI_ENDPOINT);
  url.searchParams.set("q", q);
  url.searchParams.set("category_ids", categoryId);
  url.searchParams.set("limit", String(limit));
  const res = await fetchFn(url.toString(), {
    headers: {
      Authorization: `Bearer ${token}`,
      "X-EBAY-C-MARKETPLACE-ID": "EBAY_US",
    },
  });
  if (!res.ok) return { status: res.status, listings: [] };
  const data = await res.json() as MIResponse;
  const listings: SoldListingRaw[] = [];
  for (const s of data.itemSales ?? []) {
    const cents = toCents(s.lastSoldPrice.value);
    if (cents === null) continue;
    listings.push({
      sold_price_cents: cents,
      sold_at: s.lastSoldDate,
      title: s.title,
      url: s.itemWebUrl,
      source_listing_id: listingIdFromItemId(s.itemId),
    });
  }
  return { status: res.status, listings };
}
