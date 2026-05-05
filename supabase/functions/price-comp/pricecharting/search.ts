// supabase/functions/price-comp/pricecharting/search.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { get, type ClientOptions, type ClientResponse } from "./client.ts";
import type { PCProductRow } from "./parse.ts";

export interface SearchResult {
  status: number;
  products: PCProductRow[];
}

export async function searchProducts(
  opts: ClientOptions,
  q: string,
): Promise<SearchResult> {
  const res: ClientResponse = await get(opts, "/api/products", { q });
  if (res.status !== 200) return { status: res.status, products: [] };
  const body = (res.body ?? {}) as { products?: PCProductRow[] };
  return { status: 200, products: Array.isArray(body.products) ? body.products : [] };
}
