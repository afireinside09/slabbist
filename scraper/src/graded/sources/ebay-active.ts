// src/graded/sources/ebay-active.ts
// Active eBay listings (BIN + Auction) for the movers carousel.
// Mirrors the structure of `ebay.ts` (sold-listings source) but
// against the Browse API endpoint (or HTML search page) and returns
// a different shape — these are listings, not sales.
//
// Two fetch paths:
//   - `fetchActiveViaBrowseApi`: official eBay Browse API. Requires
//     an OAuth Bearer token (client-credentials grant against the
//     production app keys). Cleanest data — gives us itemId, price,
//     image, buyingOptions, endTime, all in one JSON response.
//   - `fetchActiveViaScrape`: HTML scrape of ebay.com search. Used
//     when no token is configured. Brittle but good enough as a
//     fallback for development.
import { z } from "zod";
import { httpJson, httpText } from "@/shared/http/fetch.js";

export interface EbayActiveOpts {
  userAgent: string;
  /** Marketplace ID; defaults to EBAY_US. */
  marketplace?: string;
  /** Page size cap. eBay Browse caps at 200; HTML scrape returns ~60. */
  limit?: number;
  /**
   * eBay leaf category to scope the search to. Defaults to 183454
   * ("Pokémon Individual Cards"), which is what every movers card maps
   * to today. Required for `aspect_filter` to work — eBay only honors
   * aspect filters when a single category is specified.
   */
  categoryId?: string;
}

export interface EbayActiveApiOpts extends EbayActiveOpts {
  token: string;
}

/// Minimal shape returned by both paths. The ingest layer applies
/// strict post-filtering (title/card-number match, graded regex,
/// blocklist) before mapping to the DB schema.
export interface ActiveListing {
  ebayItemId: string;
  title: string;
  price: number;
  currency: string;
  url: string;
  imageUrl: string | null;
  buyingOptions: string | null;
  endAt: string | null;
}

const BROWSE_SEARCH = "https://api.ebay.com/buy/browse/v1/item_summary/search";
const ACTIVE_SEARCH = "https://www.ebay.com/sch/i.html";
const DEFAULT_CATEGORY_ID = "183454"; // Pokémon Individual Cards

const BrowseResponse = z.object({
  itemSummaries: z
    .array(
      z.object({
        itemId: z.string(),
        title: z.string(),
        price: z.object({ value: z.string(), currency: z.string() }).optional(),
        itemWebUrl: z.string(),
        image: z.object({ imageUrl: z.string() }).optional(),
        buyingOptions: z.array(z.string()).optional(),
        itemEndDate: z.string().optional(),
      }),
    )
    .optional()
    .default([]),
});

function listingIdFromItemId(itemId: string): string {
  // Browse-API itemIds look like "v1|123456789012|0"; the middle
  // segment is the eBay item number that the HTML page exposes too.
  const parts = itemId.split("|");
  return parts[1] ?? itemId;
}

export async function fetchActiveViaBrowseApi(
  query: string,
  opts: EbayActiveApiOpts,
): Promise<ActiveListing[]> {
  const limit = Math.min(Math.max(opts.limit ?? 50, 1), 200);
  const categoryId = opts.categoryId ?? DEFAULT_CATEGORY_ID;
  // Server-side gating to *graded* slabs only via eBay's structured
  // "Graded" aspect on the trading-card categories. We pair it with
  // category_ids so the aspect filter is honored — it's a no-op when
  // the search isn't scoped to a single category.
  const aspectFilter = `categoryId:${categoryId},Graded:{Yes}`;
  const params = new URLSearchParams({
    q: query,
    limit: String(limit),
    category_ids: categoryId,
    aspect_filter: aspectFilter,
  });
  const url = `${BROWSE_SEARCH}?${params.toString()}`;
  const body = await httpJson(url, {
    userAgent: opts.userAgent,
    headers: {
      Authorization: `Bearer ${opts.token}`,
      "X-EBAY-C-MARKETPLACE-ID": opts.marketplace ?? "EBAY_US",
    },
  });
  const parsed = BrowseResponse.parse(body);
  const out: ActiveListing[] = [];
  for (const it of parsed.itemSummaries) {
    const priceStr = it.price?.value;
    const price = priceStr === undefined ? NaN : Number(priceStr);
    if (!Number.isFinite(price)) continue;
    out.push({
      ebayItemId: listingIdFromItemId(it.itemId),
      title: it.title,
      price,
      currency: it.price?.currency ?? "USD",
      url: it.itemWebUrl,
      imageUrl: it.image?.imageUrl ?? null,
      buyingOptions: it.buyingOptions?.join(",") ?? null,
      endAt: it.itemEndDate ?? null,
    });
  }
  return out;
}

export async function fetchActiveViaScrape(
  query: string,
  opts: EbayActiveOpts,
): Promise<ActiveListing[]> {
  // _sop=12 = best match; _ipg=60 = 60 results/page (eBay's max for
  // unauthenticated search). _sacat scopes the search to a single
  // category (default Pokémon Individual Cards). LH_PrefLoc is
  // intentionally omitted — we want global supply. LH_Graded=1 is
  // eBay's structured "Graded" filter; pairing it with the category
  // mirrors the Browse API's aspect_filter behaviour so titles no
  // longer have to mention PSA/BGS/etc. for a slab to be returned.
  const categoryId = opts.categoryId ?? DEFAULT_CATEGORY_ID;
  const params = new URLSearchParams({
    _nkw: query,
    _sop: "12",
    _ipg: "60",
    _sacat: categoryId,
    LH_Graded: "1",
  });
  const url = `${ACTIVE_SEARCH}?${params.toString()}`;
  const html = await httpText(url, { userAgent: opts.userAgent });

  // eBay's search HTML changes occasionally but the per-item block
  // shape has been stable: <li class="s-item ...">…</li>. Each block
  // contains a title link, a price span, and (often) an image tag.
  const itemRe = /<li[^>]*class="[^"]*s-item[^"]*"[^>]*>([\s\S]*?)<\/li>/g;
  const titleRe = /class="s-item__title"[^>]*>(?:<span[^>]*>)?([^<]+)/;
  const priceRe = /class="s-item__price"[^>]*>\$?([0-9,]+(?:\.[0-9]+)?)/;
  const linkRe = /class="s-item__link"\s+href="([^"]+)"/;
  const imgRe = /<img[^>]+class="[^"]*s-item__image-img[^"]*"[^>]+src="([^"]+)"/;

  const out: ActiveListing[] = [];
  const seen = new Set<string>();
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(html))) {
    const chunk = m[1] ?? "";
    const title = chunk.match(titleRe)?.[1]?.trim() ?? null;
    const priceStr = chunk.match(priceRe)?.[1] ?? null;
    const link = chunk.match(linkRe)?.[1] ?? null;
    const image = chunk.match(imgRe)?.[1] ?? null;
    if (!title || !priceStr || !link) continue;
    // The first <li> is sometimes a placeholder labeled "Shop on eBay".
    if (/^shop on ebay$/i.test(title)) continue;

    const price = Number(priceStr.replace(/,/g, ""));
    if (!Number.isFinite(price)) continue;

    const idMatch = link.match(/\/itm\/(?:[^/]+\/)?(\d+)/);
    const ebayItemId = idMatch?.[1] ?? link;
    if (seen.has(ebayItemId)) continue;
    seen.add(ebayItemId);

    out.push({
      ebayItemId,
      title,
      price,
      currency: "USD",
      url: link,
      imageUrl: image,
      buyingOptions: null,
      endAt: null,
    });
    if (opts.limit && out.length >= opts.limit) break;
  }
  return out;
}
