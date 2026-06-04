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
//   * scoreSearchCard: score a Poketrace /cards search result against an identity.
//   * parseListings: map Poketrace /listings response → SoldListingWire[].
//
// PriceHistoryPoint lives here (was ppt/parse.ts) so the poketrace layer
// is self-contained once the ppt/ directory is deleted in Edge-B.

import type { PoketraceTierFields, SoldListingWire } from "../types.ts";

// ── PriceHistoryPoint (moved from ppt/parse.ts) ───────────────────────────
export interface PriceHistoryPoint {
  ts: string;
  price_cents: number;
}

// ── Existing tier-price types + helpers ──────────────────────────────────

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

// ── Card-search scoring (Task 2.2) ────────────────────────────────────────
//
// Pure normalizers ported from ppt/match.ts (deleted in Edge-B) so the
// poketrace layer has no runtime dependency on the ppt/ directory.

export interface SearchCardLite {
  id: string;
  name?: string | null;
  cardNumber?: string | null;
  set?: { name?: string | null; slug?: string | null } | null;
}

export interface IdentityForSearch {
  card_name: string;
  card_number: string | null;
  set_name: string;
}

const SET_STOPWORDS = new Set([
  "promo", "promos", "set", "cards", "series", "pokemon", "tcg",
  "championship", "championships",
]);

function cleanName(n: string): string {
  return (n ?? "").replace(/\s*\([^)]*\)\s*/g, " ").trim().replace(/\s+/g, " ").toLowerCase();
}

function tokenize(s: string): string[] {
  return s.toLowerCase()
    .replace(/['']s\b/g, "")
    .replace(/['']/g, "")
    .replace(/[^a-z0-9\s]+/g, " ")
    .split(/\s+/)
    .filter((t) => t.length > 0);
}

function distinctiveSetTokens(setName: string): string[] {
  return tokenize(setName).filter((t) => t.length >= 4 && !SET_STOPWORDS.has(t));
}

function normalizeCardNumber(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const t = String(raw).trim();
  if (!t) return null;
  const lower = t.split("/")[0].toLowerCase().replace(/[^a-z0-9]/g, "");
  if (!lower) return null;
  const stripped = lower.replace(/^0+/, "");
  return stripped.length > 0 ? stripped : "0";
}

export function scoreSearchCard(
  card: SearchCardLite,
  identity: IdentityForSearch,
): { score: number; accept: boolean } {
  const idName = cleanName(identity.card_name);
  const cardName = cleanName(card.name ?? "");
  if (!idName || !cardName) return { score: 0, accept: false };
  if (!(idName.includes(cardName) || cardName.includes(idName))) return { score: 0, accept: false };
  let score = 2; // name hit
  let numberExact = false;
  const idNum = normalizeCardNumber(identity.card_number);
  const cardNum = normalizeCardNumber(card.cardNumber);
  if (idNum && cardNum) {
    if (idNum === cardNum) { score += 3; numberExact = true; }
    else if (idNum.startsWith(cardNum) || cardNum.startsWith(idNum)) score += 1;
  }
  const idSet = new Set(distinctiveSetTokens(identity.set_name));
  const cardSet = new Set(distinctiveSetTokens(card.set?.name ?? ""));
  let overlap = 0;
  for (const t of idSet) if (cardSet.has(t)) overlap += 1;
  score += overlap;
  return { score, accept: numberExact || overlap >= 2 };
}

// ── Sold-listing parsing (Task 2.2) ──────────────────────────────────────

export function parseListings(body: unknown): SoldListingWire[] {
  const data = (body as { data?: unknown })?.data;
  if (!Array.isArray(data)) return [];
  const out: SoldListingWire[] = [];
  for (const it of data) {
    if (!it || typeof it !== "object") continue;
    const r = it as Record<string, unknown>;
    const id = typeof r.sourceItemId === "string" ? r.sourceItemId : "";
    const soldAt = typeof r.soldAt === "string" ? r.soldAt : "";
    if (!id || !soldAt) continue;
    out.push({
      source_listing_id: id,
      title: typeof r.title === "string" ? r.title : null,
      price_cents: dollarsToCents(r.price),
      sold_at: soldAt,
      grader: typeof r.grader === "string" ? r.grader : null,
      grade: typeof r.grade === "string" ? r.grade : null,
      condition: typeof r.condition === "string" ? r.condition : null,
      url: typeof r.listingUrl === "string" ? r.listingUrl : null,
      anomaly_flag: typeof r.anomalyFlag === "string" ? r.anomalyFlag : null,
    });
  }
  return out;
}
