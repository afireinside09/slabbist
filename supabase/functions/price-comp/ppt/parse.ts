// supabase/functions/price-comp/ppt/parse.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { GradingService } from "../types.ts";
import { gradeKeyFor, type TierKey } from "../lib/grade-key.ts";

export interface PPTSmartMarketPrice {
  price?: number | null;
  confidence?: string;
}

export interface PPTSalesByGradeEntry {
  count?: number;
  averagePrice?: number;
  smartMarketPrice?: PPTSmartMarketPrice;
}

export interface PPTEbay {
  salesByGrade?: Record<string, PPTSalesByGradeEntry | undefined>;
  // priceHistory is keyed by gradeKey ("psa10", "bgs10", "ungraded", …);
  // each value is a date-keyed dict of daily aggregates.
  priceHistory?: Record<string, Record<string, { average?: number; count?: number } | undefined> | undefined>;
}

export interface PPTCard {
  tcgPlayerId?: string;
  name?: string;
  setName?: string;
  cardNumber?: string;
  tcgPlayerUrl?: string;
  prices?: { market?: number };
  ebay?: PPTEbay;
}

export interface LadderPrices {
  loose:    number | null;
  psa_7:    number | null;
  psa_8:    number | null;
  psa_9:    number | null;
  psa_9_5:  number | null;
  psa_10:   number | null;
  bgs_10:   number | null;
  cgc_10:   number | null;
  sgc_10:   number | null;
}

export interface PriceHistoryPoint {
  ts: string;
  price_cents: number;
}

// Maps our internal TierKey → PPT's compact key in `salesByGrade` /
// `priceHistory`. PPT uses `psa10` not `psa_10`, `ungraded` not `raw`.
const TIER_TO_PPT_KEY: Record<Exclude<keyof LadderPrices, "loose">, string> = {
  psa_7:   "psa7",
  psa_8:   "psa8",
  psa_9:   "psa9",
  psa_9_5: "psa9_5",
  psa_10:  "psa10",
  bgs_10:  "bgs10",
  cgc_10:  "cgc10",
  sgc_10:  "sgc10",
};

function dollarsToCents(v: number | null | undefined): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v !== "number" || !Number.isFinite(v) || v <= 0) return null;
  return Math.round(v * 100);
}

function smartMarketCents(entry: PPTSalesByGradeEntry | undefined): number | null {
  if (!entry) return null;
  return dollarsToCents(entry.smartMarketPrice?.price);
}

export function extractLadder(card: PPTCard): LadderPrices {
  const sbg = card.ebay?.salesByGrade ?? {};
  const looseFromMarket   = dollarsToCents(card.prices?.market);
  const looseFromUngraded = smartMarketCents(sbg["ungraded"]);
  const out: LadderPrices = {
    loose:   looseFromMarket ?? looseFromUngraded,
    psa_7:   null, psa_8: null, psa_9: null, psa_9_5: null, psa_10: null,
    bgs_10:  null, cgc_10: null, sgc_10: null,
  };
  for (const [tier, key] of Object.entries(TIER_TO_PPT_KEY) as Array<[keyof LadderPrices, string]>) {
    out[tier] = smartMarketCents(sbg[key]);
  }
  return out;
}

export function pickTier(card: PPTCard, service: GradingService, grade: string): number | null {
  const key = gradeKeyFor(service, grade);
  if (!key) return null;
  const ladder = extractLadder(card);
  return ladder[key as keyof LadderPrices] ?? null;
}

export function ladderHasAnyPrice(ladder: LadderPrices): boolean {
  return Object.values(ladder).some((v) => v !== null);
}

/**
 * Converts a PPT `ebay.priceHistory.{gradeKey}` date-keyed dict
 * (e.g. `{ "2026-05-05": { average: 1190.0, count: 1 }, … }`) into a
 * chronologically-sorted array of `{ts, price_cents}`. Tolerates missing
 * keys, malformed entries, and wrong shapes by returning `[]`.
 */
export function parsePriceHistory(raw: unknown): PriceHistoryPoint[] {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return [];
  const out: PriceHistoryPoint[] = [];
  for (const [date, agg] of Object.entries(raw as Record<string, unknown>)) {
    if (!date) continue;
    const parsedDate = Date.parse(date);
    if (Number.isNaN(parsedDate)) continue;
    if (!agg || typeof agg !== "object") continue;
    const avg = (agg as { average?: unknown }).average;
    if (avg === null || avg === undefined) continue;
    const num = typeof avg === "number" ? avg : Number(avg);
    if (!Number.isFinite(num) || num <= 0) continue;
    out.push({ ts: date, price_cents: Math.round(num * 100) });
  }
  out.sort((a, b) => a.ts.localeCompare(b.ts));
  return out;
}

/**
 * Returns the raw `ebay.priceHistory.{gradeKey}` dict for the given
 * internal TierKey, or `null` if no series exists for that tier (or if
 * the tier is `loose` / `null`). Caller passes the result to
 * `parsePriceHistory()` to convert into the wire shape.
 */
export function priceHistoryForTier(card: PPTCard, tierKey: TierKey | null): unknown {
  if (!tierKey || tierKey === "loose") return null;
  const pptKey = TIER_TO_PPT_KEY[tierKey as Exclude<keyof LadderPrices, "loose">];
  if (!pptKey) return null;
  const series = card.ebay?.priceHistory?.[pptKey];
  return series ?? null;
}

/**
 * Canonical product page URL for the card. Currently the TCGPlayer URL —
 * PPT does not expose a PPT-native product page URL on the card object.
 * The `ppt_url` column name is kept for spec-name continuity even though
 * the URL points off-domain.
 */
export function productUrl(card: PPTCard): string {
  if (typeof card.tcgPlayerUrl === "string" && card.tcgPlayerUrl) return card.tcgPlayerUrl;
  if (card.tcgPlayerId) {
    return `https://www.tcgplayer.com/product/${encodeURIComponent(card.tcgPlayerId)}`;
  }
  return "https://www.tcgplayer.com";
}
