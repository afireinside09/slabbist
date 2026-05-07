// supabase/functions/price-comp/ppt/match.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Multi-tier card resolver for the PPT-backed /price-comp Edge Function.
//
// PSA cert set names ("M-P Promo", "SVP Black Star Promo") and card
// numbers ("050") often disagree with TCGPlayer/PPT canonical strings
// ("McDonald's Promos 2024", "079"). A single-shot fuzzy search misses
// almost all of these. This resolver runs up to three cheap (1-credit)
// candidate searches in fallback order, scores each candidate against
// the PSA identity, and only pays for the heavy 3-credit full fetch on
// the chosen card.
//
// Cost per cold-path resolve:
//   T1 hit: 1 + 3 = 4 credits
//   T2 hit: 2 + 3 = 5 credits
//   T3 hit: 3 + 3 = 6 credits
//   miss:   3 credits

import type { ClientOptions } from "./client.ts";
import type { PPTCard } from "./parse.ts";
import { fetchCard, searchCards, type SearchCardsArgs } from "./cards.ts";

export interface IdentityForMatch {
  card_name: string;
  card_number: string | null;
  set_name: string;
  year: number | null;
}

const SET_STOPWORDS = new Set([
  "promo", "promos", "set", "cards", "series", "pokemon", "tcg",
  "championship", "championships",
]);

function cleanName(name: string): string {
  return name.replace(/\s*\([^)]*\)\s*/g, " ").trim().replace(/\s+/g, " ");
}

/**
 * Tokenize a free-form set name into normalized lowercase word tokens.
 * Strips punctuation, splits on whitespace. Numeric-only tokens are
 * preserved (e.g. "151" survives) but later filters may drop short
 * tokens depending on caller need.
 *
 * Possessive `'s` is stripped to the bare stem ("Champion's" →
 * "champion", "McDonald's" → "mcdonald") because PPT's `&set=` filter
 * is substring-based, NOT stem-aware: `set=mcdonald` finds "McDonald's
 * Promos 2024" but `set=mcdonalds` returns 0 hits (verified live
 * 2026-05-07).
 */
function tokenize(s: string): string[] {
  return s
    .toLowerCase()
    .replace(/['’]s\b/g, "")
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9\s]+/g, " ")
    .split(/\s+/)
    .filter((t) => t.length > 0);
}

function distinctiveSetTokens(setName: string): string[] {
  return tokenize(setName).filter((t) => t.length >= 4 && !SET_STOPWORDS.has(t));
}

function pickDistinctiveSetToken(setName: string): string | null {
  const candidates = distinctiveSetTokens(setName);
  if (candidates.length === 0) return null;
  // Pick the longest (ties broken by first occurrence).
  let best = candidates[0];
  for (const c of candidates) if (c.length > best.length) best = c;
  return best;
}

export function buildSearchTiers(identity: IdentityForMatch): Array<{ tier: string; args: SearchCardsArgs }> {
  const name = cleanName(identity.card_name);
  const tiers: Array<{ tier: string; args: SearchCardsArgs }> = [];

  // T1: name + number + set (PSA-cert verbatim concat; works when PPT's
  // fuzzy index agrees with PSA tokens — the historical happy path).
  const t1Parts: string[] = [name];
  if (identity.card_number) t1Parts.push(identity.card_number);
  t1Parts.push(identity.set_name);
  const t1Search = t1Parts.join(" ").replace(/\s+/g, " ").trim();
  tiers.push({ tier: "T1", args: { search: t1Search, limit: 10 } });

  // T2: name + PPT &set= filter, only if a distinctive set token exists.
  const setToken = pickDistinctiveSetToken(identity.set_name);
  if (setToken) {
    tiers.push({ tier: "T2", args: { search: name, set: setToken, limit: 10 } });
  }

  // T3: bare name, broader limit (reranked by scoreCard).
  tiers.push({ tier: "T3", args: { search: name, limit: 20 } });

  return tiers;
}

/**
 * Normalize a card number for comparison: strip leading zeros, drop the
 * "/<denominator>" suffix that TCGPlayer attaches ("199/165" → "199"),
 * lowercase, drop non-alphanumerics.
 *
 * Returns null for empty / whitespace-only inputs so callers can short
 * out without false-positive matches on "" === "".
 */
function normalizeCardNumber(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const trimmed = String(raw).trim();
  if (!trimmed) return null;
  const beforeSlash = trimmed.split("/")[0];
  const lower = beforeSlash.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (!lower) return null;
  // Strip leading zeros, but preserve a "0" if the whole thing was zeros.
  const stripped = lower.replace(/^0+/, "");
  return stripped.length > 0 ? stripped : "0";
}

export function scoreCard(
  card: PPTCard,
  identity: IdentityForMatch,
): { score: number; accept: boolean } {
  const idName = cleanName(identity.card_name).toLowerCase();
  const cardName = (card.name ?? "").toLowerCase().trim();
  if (!idName || !cardName) return { score: 0, accept: false };
  const nameSubstring = idName.includes(cardName) || cardName.includes(idName);
  if (!nameSubstring) return { score: 0, accept: false };

  let score = 2; // name hit

  // Number scoring.
  let numberExact = false;
  const idNum = normalizeCardNumber(identity.card_number);
  const cardNum = normalizeCardNumber(card.cardNumber);
  if (idNum && cardNum) {
    if (idNum === cardNum) {
      score += 3;
      numberExact = true;
    } else if (idNum.startsWith(cardNum) || cardNum.startsWith(idNum)) {
      score += 1;
    }
  }

  // Set token overlap.
  const idSetTokens = new Set(distinctiveSetTokens(identity.set_name));
  const cardSetTokens = new Set(distinctiveSetTokens(card.setName ?? ""));
  let overlap = 0;
  for (const t of idSetTokens) if (cardSetTokens.has(t)) overlap += 1;
  score += overlap;

  const accept = numberExact || overlap >= 2;
  return { score, accept };
}

export interface ResolveResult {
  card: PPTCard | null;
  attemptLog: string[];
  tierMatched: string | null;
}

/**
 * Walk the search tiers in order. For each tier:
 *   - Run the cheap searchCards() (1 credit).
 *   - For T1: if there's exactly one result, score it and accept on
 *     non-rejection. Otherwise rank+filter like T2/T3.
 *   - For T2/T3: rank all results by scoreCard, pick the highest accepted.
 *   - Once a candidate is chosen, do the heavy fetchCard() by
 *     tcgPlayerId (3 credits) to grab ebay + history.
 * Returns null+attemptLog if nothing across all tiers passes acceptance.
 */
export async function resolveCard(
  opts: ClientOptions,
  identity: IdentityForMatch,
): Promise<ResolveResult> {
  const tiers = buildSearchTiers(identity);
  const attemptLog: string[] = [];

  for (const { tier, args } of tiers) {
    const res = await searchCards(opts, args);
    const got = res.cards.length;
    if (res.status !== 200) {
      attemptLog.push(`${tier}: search='${args.search ?? ""}' set='${args.set ?? ""}' status=${res.status}`);
      // Hard upstream failure on a tier — keep walking; later tiers may
      // succeed on a fresh request, but a 5xx will likely keep failing.
      continue;
    }
    let chosen: PPTCard | null = null;
    let chosenScore = -1;
    let topScore = 0;
    let topAccept = false;

    if (tier === "T1") {
      // T1 is high-precision: if PPT returned anything, the first card is
      // usually the canonical match. Score the top hit and accept if it
      // passes scoreCard.accept.
      const first = res.cards[0];
      if (first) {
        const sc = scoreCard(first, identity);
        topScore = sc.score;
        topAccept = sc.accept;
        if (sc.accept) {
          chosen = first;
          chosenScore = sc.score;
        }
      }
    } else {
      // T2/T3: re-rank, take the highest-scoring acceptable card.
      for (const c of res.cards) {
        const sc = scoreCard(c, identity);
        if (sc.score > topScore) topScore = sc.score;
        if (sc.accept && sc.score > chosenScore) {
          chosen = c;
          chosenScore = sc.score;
          topAccept = true;
        }
      }
    }

    attemptLog.push(`${tier}: search='${args.search ?? ""}' set='${args.set ?? ""}' got ${got} hits, top score ${topScore} accept=${topAccept}`);

    if (chosen && chosen.tcgPlayerId) {
      const full = await fetchCard(opts, { tcgPlayerId: String(chosen.tcgPlayerId) });
      if (full.status === 200 && full.card) {
        return { card: full.card, attemptLog, tierMatched: tier };
      }
      attemptLog.push(`${tier}: full fetchCard status=${full.status}, treating as miss`);
    }
  }

  return { card: null, attemptLog, tierMatched: null };
}
