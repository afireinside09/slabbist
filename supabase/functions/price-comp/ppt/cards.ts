// supabase/functions/price-comp/ppt/cards.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { get, type ClientOptions, _resetPause } from "./client.ts";
import type { PPTCard } from "./parse.ts";

/**
 * PPT returns a few different envelope shapes depending on endpoint:
 *   - Bare array:                  [card, card, …]
 *   - Wrapped array:               { data: [card, card, …] }
 *   - Single-object wrapped:       { data: card }   ← used by tcgPlayerId-by-id
 *   - Empty:                       [] / { data: [] } / { data: null }
 *
 * Normalize all of those down to a card[] so callers don't have to care.
 * Anything else returns [] (defensive — matches the previous behavior
 * for unknown shapes).
 */
function unwrapCardList(body: unknown): unknown[] {
  if (Array.isArray(body)) return body;
  if (body && typeof body === "object") {
    const data = (body as { data?: unknown }).data;
    if (Array.isArray(data)) return data;
    // Single object under data (tcgPlayerId-by-id) → wrap to 1-array.
    if (data && typeof data === "object") return [data];
  }
  return [];
}

export interface FetchCardArgs {
  search?: string;
  tcgPlayerId?: string;
  language?: "english" | "japanese";
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
  if (args.language) {
    params.language = args.language;
  }
  const res = await get(opts, "/api/v2/cards", params);
  if (res.status !== 200) return { status: res.status, card: null, creditsConsumed: res.creditsConsumed };
  const list = unwrapCardList(res.body);
  const card = (list.length > 0 ? list[0] : null) as PPTCard | null;
  return { status: 200, card, creditsConsumed: res.creditsConsumed };
}

export interface SearchCardsArgs {
  search?: string;
  set?: string;
  limit?: number;
  language?: "english" | "japanese";
}

export interface SearchCardsResult {
  status: number;
  cards: PPTCard[];
  creditsConsumed?: number;
}

/**
 * Cheap multi-result search against PPT — does NOT request includeEbay or
 * includeHistory, so it consumes 1 credit per call instead of 3. Used by
 * the multi-tier resolver to enumerate candidates before paying for the
 * full ladder fetch on a chosen card.
 */
export async function searchCards(opts: ClientOptions, args: SearchCardsArgs): Promise<SearchCardsResult> {
  if (!args.search && !args.set) {
    return { status: 400, cards: [] };
  }
  const params: Record<string, string> = {
    limit: String(args.limit ?? 10),
  };
  if (args.search) params.search = args.search;
  if (args.set) params.set = args.set;
  if (args.language) params.language = args.language;
  const res = await get(opts, "/api/v2/cards", params);
  if (res.status !== 200) return { status: res.status, cards: [], creditsConsumed: res.creditsConsumed };
  const cards = unwrapCardList(res.body).filter((x) => x && typeof x === "object") as PPTCard[];
  return { status: 200, cards, creditsConsumed: res.creditsConsumed };
}
