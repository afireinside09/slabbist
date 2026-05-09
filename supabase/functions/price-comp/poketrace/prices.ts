// supabase/functions/price-comp/poketrace/prices.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import {
  extractTierPrice,
  extractPoketraceLadder,
  tierPriceToBlock,
  type RawTierPrice,
} from "./parse.ts";
import type { PoketraceTierFields, PoketraceLadderCents } from "../types.ts";

export interface FetchPoketracePricesOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

export interface PoketracePricesResult {
  status: number;
  fields: PoketraceTierFields | null; // null when scanned tier not present
  raw: RawTierPrice | null;
  /// iOS comp-card ladder for the toggle. Independent of `fields` — a
  /// card may have a populated ladder but no PSA_10 detail (or vice
  /// versa). Empty `{}` when the card has no graded data at all.
  ladderCents: PoketraceLadderCents;
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
    return { status: res.status, fields: null, raw: null, ladderCents: {} };
  }
  const ladderCents = extractPoketraceLadder(res.body);
  const raw = extractTierPrice(res.body, tierKey);
  if (!raw) return { status: 200, fields: null, raw: null, ladderCents };
  return { status: 200, fields: tierPriceToBlock(raw), raw, ladderCents };
}
