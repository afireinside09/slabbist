import { z } from "zod";
import { httpJson, httpText } from "@/shared/http/fetch.js";
import type { GradedSale } from "@/graded/models.js";
import { parseGradedTitle } from "@/graded/cert-parser.js";

const MARKETPLACE_INSIGHTS = "https://api.ebay.com/buy/marketplace_insights/v1_beta/item_sales/search";
const SOLD_SEARCH_BASE = "https://www.ebay.com/sch/i.html";

const ApiResponse = z.object({
  itemSales: z.array(z.object({
    itemId: z.string(),
    title: z.string(),
    lastSoldDate: z.string(),
    lastSoldPrice: z.object({ value: z.string(), currency: z.string() }),
    itemWebUrl: z.string(),
  })).optional().default([]),
});

export interface EbayApiOpts { token: string; userAgent: string; }
export interface EbayScrapeOpts { userAgent: string; }

function listingIdFromItemId(itemId: string): string {
  const parts = itemId.split("|");
  return parts[1] ?? itemId;
}

function toGradedSale(
  title: string,
  price: number,
  soldAt: string,
  url: string,
  listingId: string,
): GradedSale | null {
  const parsed = parseGradedTitle(title);
  if (!parsed) return null;
  return {
    gradingService: parsed.gradingService,
    grade: parsed.grade,
    certNumber: parsed.certNumber,
    source: "ebay",
    sourceListingId: listingId,
    soldPrice: price,
    soldAt,
    title,
    url,
    identity: {
      game: "pokemon",
      language: /日本|ポケモン|JP\b|Japanese/i.test(title) ? "jp" : "en",
      setName: title,
      cardName: title,
      cardNumber: null,
      variant: null,
    },
  };
}

export async function ebayFetchRecentSoldViaApi(query: string, opts: EbayApiOpts): Promise<GradedSale[]> {
  const url = `${MARKETPLACE_INSIGHTS}?q=${encodeURIComponent(query)}&limit=200`;
  const body = await httpJson(url, {
    userAgent: opts.userAgent,
    headers: { Authorization: `Bearer ${opts.token}`, "X-EBAY-C-MARKETPLACE-ID": "EBAY_US" },
  });
  const parsed = ApiResponse.parse(body);
  const sales: GradedSale[] = [];
  for (const it of parsed.itemSales) {
    const price = Number(it.lastSoldPrice.value);
    if (!Number.isFinite(price)) continue;
    const sale = toGradedSale(it.title, price, it.lastSoldDate, it.itemWebUrl, listingIdFromItemId(it.itemId));
    if (sale) sales.push(sale);
  }
  return sales;
}

export async function ebayFetchRecentSoldViaScrape(query: string, opts: EbayScrapeOpts): Promise<GradedSale[]> {
  const url = `${SOLD_SEARCH_BASE}?_nkw=${encodeURIComponent(query)}&LH_Sold=1&LH_Complete=1&_sop=13`;
  const html = await httpText(url, { userAgent: opts.userAgent });
  const itemRe = /<li class="s-item">([\s\S]*?)<\/li>/g;
  const titleRe = /class="s-item__title">([^<]+)</;
  const priceRe = /class="s-item__price">\$?([0-9,]+(?:\.[0-9]+)?)/;
  const linkRe = /class="s-item__link" href="([^"]+)"/;
  const dateRe = /class="s-item__ended-date">([^<]+)</;

  const sales: GradedSale[] = [];
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(html))) {
    const chunk = m[1]!;
    const title = chunk.match(titleRe)?.[1] ?? null;
    const priceStr = chunk.match(priceRe)?.[1] ?? null;
    const link = chunk.match(linkRe)?.[1] ?? null;
    const dateStr = chunk.match(dateRe)?.[1] ?? null;
    if (!title || !priceStr || !link) continue;
    const price = Number(priceStr.replace(/,/g, ""));
    if (!Number.isFinite(price)) continue;
    const soldAt = dateStr ? new Date(dateStr).toISOString() : new Date().toISOString();
    const listingId = link.match(/\/itm\/(?:[^/]+\/)?(\d+)/)?.[1] ?? link;
    const sale = toGradedSale(title, price, soldAt, link, listingId);
    if (sale) sales.push(sale);
  }
  return sales;
}
