// supabase/functions/price-comp/pricecharting/product.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { get, type ClientOptions, type ClientResponse } from "./client.ts";
import type { PCProductRow } from "./parse.ts";

export interface GetProductResult {
  status: number;
  product: PCProductRow | null;
}

export async function getProduct(
  opts: ClientOptions,
  id: string,
): Promise<GetProductResult> {
  const res: ClientResponse = await get(opts, "/api/product", { id });
  if (res.status !== 200) return { status: res.status, product: null };
  return { status: 200, product: (res.body ?? null) as PCProductRow | null };
}
