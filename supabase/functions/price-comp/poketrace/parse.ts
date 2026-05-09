// supabase/functions/price-comp/poketrace/parse.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Pure transforms. No I/O.
//   * extractTierPrice: walk Poketrace card detail to find a tier under
//     any of the top-level price source keys (e.g. ebay, tcgplayer).
//   * tierPriceToBlock: TierPrice (decimal dollars) → wire-shaped block
//     (integer cents).
//   * parseHistoryResponse: PriceHistoryResponse → app-shaped
//     [{ ts, price_cents }].

import type { PoketraceTierFields } from "../types.ts";
import type { PriceHistoryPoint } from "../ppt/parse.ts";

export interface RawTierPrice {
  avg?: number | null;
  low?: number | null;
  high?: number | null;
  avg1d?: number | null;
  avg7d?: number | null;
  avg30d?: number | null;
  median3d?: number | null;
  median7d?: number | null;
  median30d?: number | null;
  trend?: "up" | "down" | "stable" | null;
  confidence?: "high" | "medium" | "low" | null;
  saleCount?: number | null;
}

interface CardDetailEnvelope {
  data?: {
    id?: string;
    prices?: Record<string, Record<string, RawTierPrice>>;
  };
}

const TREND_VALUES = new Set(["up", "down", "stable"]);
const CONFIDENCE_VALUES = new Set(["high", "medium", "low"]);

function dollarsToCents(v: unknown): number | null {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  return Math.round(v * 100);
}

export function extractTierPrice(
  card: CardDetailEnvelope,
  tierKey: string,
): RawTierPrice | null {
  const prices = card.data?.prices;
  if (!prices || typeof prices !== "object") return null;
  for (const sourceKey of Object.keys(prices)) {
    const sourceMap = prices[sourceKey];
    if (sourceMap && typeof sourceMap === "object" && tierKey in sourceMap) {
      return sourceMap[tierKey] ?? null;
    }
  }
  return null;
}

/**
 * iOS comp-card ladder ids → Poketrace tier keys. Mirrors the PPT ladder
 * shape (Raw + PSA 7–10 + BGS/CGC/SGC 10) so the source toggle has the
 * same set of cells regardless of provider. NEAR_MINT stands in for
 * "Raw" — Poketrace doesn't expose a graded "loose" tier, but ungraded
 * NEAR_MINT is the closest analogue an operator references for raw.
 */
const LADDER_KEY_MAP: Record<string, string> = {
  loose:   "NEAR_MINT",
  psa_7:   "PSA_7",
  psa_8:   "PSA_8",
  psa_9:   "PSA_9",
  psa_9_5: "PSA_9_5",
  psa_10:  "PSA_10",
  bgs_10:  "BGS_10",
  cgc_10:  "CGC_10",
  sgc_10:  "SGC_10",
};

/**
 * Walks the Poketrace card-detail response and extracts a price for
 * every iOS ladder slot we have a Poketrace tier for. Returns an
 * iOS-friendly map keyed by ladder id with integer-cent values.
 * Missing tiers are absent from the map (iOS treats absence as "no
 * data" for that cell).
 */
export function extractPoketraceLadder(
  card: CardDetailEnvelope,
): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [iosId, ptKey] of Object.entries(LADDER_KEY_MAP)) {
    const tp = extractTierPrice(card, ptKey);
    const cents = dollarsToCents(tp?.avg);
    if (cents !== null) out[iosId] = cents;
  }
  return out;
}

export function tierPriceToBlock(tp: RawTierPrice): PoketraceTierFields {
  const trend: PoketraceTierFields["trend"] =
    typeof tp.trend === "string" && TREND_VALUES.has(tp.trend)
      ? (tp.trend as PoketraceTierFields["trend"])
      : null;
  const confidence: PoketraceTierFields["confidence"] =
    typeof tp.confidence === "string" && CONFIDENCE_VALUES.has(tp.confidence)
      ? (tp.confidence as PoketraceTierFields["confidence"])
      : null;
  return {
    avg_cents:        dollarsToCents(tp.avg),
    low_cents:        dollarsToCents(tp.low),
    high_cents:       dollarsToCents(tp.high),
    avg_1d_cents:     dollarsToCents(tp.avg1d),
    avg_7d_cents:     dollarsToCents(tp.avg7d),
    avg_30d_cents:    dollarsToCents(tp.avg30d),
    median_3d_cents:  dollarsToCents(tp.median3d),
    median_7d_cents:  dollarsToCents(tp.median7d),
    median_30d_cents: dollarsToCents(tp.median30d),
    trend,
    confidence,
    sale_count: typeof tp.saleCount === "number" && Number.isFinite(tp.saleCount) ? tp.saleCount : null,
  };
}

interface HistoryEntry {
  date?: string;
  avg?: number | null;
}

interface HistoryEnvelope {
  data?: HistoryEntry[] | unknown;
}

export function parseHistoryResponse(resp: HistoryEnvelope | Record<string, unknown>): PriceHistoryPoint[] {
  const data = (resp as HistoryEnvelope).data;
  if (!Array.isArray(data)) return [];
  const out: PriceHistoryPoint[] = [];
  for (const entry of data) {
    if (!entry || typeof entry.date !== "string") continue;
    const cents = dollarsToCents(entry.avg);
    if (cents === null) continue;
    // Poketrace returns dates as YYYY-MM-DD; promote to midnight UTC ISO.
    const ts = `${entry.date}T00:00:00Z`;
    out.push({ ts, price_cents: cents });
  }
  return out;
}
