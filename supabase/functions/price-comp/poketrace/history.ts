// supabase/functions/price-comp/poketrace/history.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { fetchJson, type FetchResult, type PoketraceClientOptions } from "./client.ts";
import { parseHistoryResponse } from "./parse.ts";
import type { PriceHistoryPoint } from "../ppt/parse.ts";

export interface FetchPoketraceHistoryOverrides {
  fetchJsonImpl?: <T>(opts: PoketraceClientOptions, path: string) => Promise<FetchResult<T>>;
}

export interface PoketraceHistoryResult {
  status: number;
  history: PriceHistoryPoint[];
}

export async function fetchPoketraceHistory(
  client: PoketraceClientOptions,
  cardId: string,
  tierKey: string,
  overrides: FetchPoketraceHistoryOverrides = {},
): Promise<PoketraceHistoryResult> {
  const fetchImpl = overrides.fetchJsonImpl ?? fetchJson;
  const path = `/cards/${encodeURIComponent(cardId)}/prices/${encodeURIComponent(tierKey)}/history?period=30d&limit=50`;
  const res = await fetchImpl<{ data?: unknown }>(client, path);
  if (res.status !== 200 || !res.body) {
    return { status: res.status, history: [] };
  }
  return { status: 200, history: parseHistoryResponse(res.body) };
}
