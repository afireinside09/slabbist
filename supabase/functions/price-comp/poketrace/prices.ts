// supabase/functions/price-comp/poketrace/prices.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import { extractTierPrice, tierPriceToBlock, type RawTierPrice } from "./parse.ts";
import type { PoketraceTierFields } from "../types.ts";

export interface FetchPoketracePricesOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

export interface PoketracePricesResult {
  status: number;
  fields: PoketraceTierFields | null; // null when tier not present
  raw: RawTierPrice | null;
}

export async function fetchPoketracePrices(
  client: PoketraceClientOptions,
  cardId: string,
  tierKey: string,
  overrides: FetchPoketracePricesOverrides = {},
): Promise<PoketracePricesResult> {
  const fetchImpl = overrides.fetchJsonImpl ?? fetchJson;
  const res = await fetchImpl<{ data?: { prices?: Record<string, Record<string, RawTierPrice>> } }>(
    client, `/cards/${encodeURIComponent(cardId)}`,
  );
  if (res.status !== 200 || !res.body) {
    return { status: res.status, fields: null, raw: null };
  }
  const raw = extractTierPrice(res.body, tierKey);
  if (!raw) return { status: 200, fields: null, raw: null };
  return { status: 200, fields: tierPriceToBlock(raw), raw };
}
