// supabase/functions/price-comp/poketrace/listings.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import { parseListings } from "./parse.ts";
import type { SoldListingWire } from "../types.ts";

export interface FetchListingsOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

export interface PoketraceListingsResult {
  status: number;
  listings: SoldListingWire[];
}

// Scale-plan endpoint. Graceful-degrades to [] on any non-200 (incl. 403
// UPGRADE_REQUIRED off lower plans) so it never blocks the price happy path.
export async function fetchPoketraceListings(
  client: PoketraceClientOptions,
  cardId: string,
  grader: string,
  grade: string,
  overrides: FetchListingsOverrides = {},
): Promise<PoketraceListingsResult> {
  const fetchImpl = overrides.fetchJsonImpl ?? fetchJson;
  const path =
    `/cards/${encodeURIComponent(cardId)}/listings` +
    `?grader=${encodeURIComponent(grader)}&grade=${encodeURIComponent(grade)}` +
    `&sort=sold_at_desc&limit=20`;
  const res = await fetchImpl<{ data?: unknown }>(client, path);
  if (res.status !== 200 || !res.body) return { status: res.status, listings: [] };
  return { status: 200, listings: parseListings(res.body) };
}
