// supabase/functions/price-comp/ppt/cards.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { get, type ClientOptions, _resetPause } from "./client.ts";
import type { PPTCard } from "./parse.ts";

export interface FetchCardArgs {
  search?: string;
  tcgPlayerId?: string;
}

export interface FetchCardResult {
  status: number;
  card: PPTCard | null;
  creditsConsumed?: number;
}

export function _resetPauseForTests(): void { _resetPause(); }

export async function fetchCard(opts: ClientOptions, args: FetchCardArgs): Promise<FetchCardResult> {
  const params: Record<string, string> = {
    includeEbay: "true",
    includeHistory: "true",
    days: "180",
    maxDataPoints: "30",
  };
  if (args.tcgPlayerId) {
    params.tcgPlayerId = args.tcgPlayerId;
  } else if (args.search) {
    params.search = args.search;
    params.limit = "1";
  } else {
    return { status: 400, card: null };
  }
  const res = await get(opts, "/api/v2/cards", params);
  if (res.status !== 200) return { status: res.status, card: null, creditsConsumed: res.creditsConsumed };
  const body = res.body;
  let arr: unknown;
  if (Array.isArray(body)) arr = body;
  else if (body && typeof body === "object" && Array.isArray((body as { data?: unknown }).data)) arr = (body as { data: unknown[] }).data;
  else arr = [];
  const list = arr as unknown[];
  const card = (list.length > 0 ? list[0] : null) as PPTCard | null;
  return { status: 200, card, creditsConsumed: res.creditsConsumed };
}
