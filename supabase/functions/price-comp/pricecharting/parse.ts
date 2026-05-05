// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { GradingService } from "../types.ts";
import { gradeKeyFor, type TierKey } from "../lib/grade-key.ts";

// PriceCharting publishes prices as integer pennies (e.g. 1732 = $17.32).
// We carry pennies-int through the response wire shape (matches iOS Int64
// cents). graded_market columns are numeric(12,2) dollars; conversion
// happens in persistence/market.ts.
export interface PCProductRow {
  id?: string;
  "product-name"?: string;
  "console-name"?: string;
  "release-date"?: string;
  "loose-price"?: number;
  "grade-7-price"?: number;
  "grade-8-price"?: number;
  "grade-9-price"?: number;
  "grade-9.5-price"?: number;
  "psa-10-price"?: number;
  "bgs-10-price"?: number;
  "cgc-10-price"?: number;
  "sgc-10-price"?: number;
  // PriceCharting may also publish "manual-only-price" / "box-only-price"
  // for video games — irrelevant for trading cards.
}

export interface LadderPrices {
  loose: number | null;
  grade_7: number | null;
  grade_8: number | null;
  grade_9: number | null;
  grade_9_5: number | null;
  psa_10: number | null;
  bgs_10: number | null;
  cgc_10: number | null;
  sgc_10: number | null;
}

const TIER_TO_FIELD: Record<keyof LadderPrices, keyof PCProductRow> = {
  loose:     "loose-price",
  grade_7:   "grade-7-price",
  grade_8:   "grade-8-price",
  grade_9:   "grade-9-price",
  grade_9_5: "grade-9.5-price",
  psa_10:    "psa-10-price",
  bgs_10:    "bgs-10-price",
  cgc_10:    "cgc-10-price",
  sgc_10:    "sgc-10-price",
};

function readPrice(row: PCProductRow, field: keyof PCProductRow): number | null {
  const v = row[field];
  if (typeof v === "number" && Number.isFinite(v) && v > 0) return v;
  return null;
}

export function extractLadder(row: PCProductRow): LadderPrices {
  const out: Partial<LadderPrices> = {};
  for (const tier of Object.keys(TIER_TO_FIELD) as Array<keyof LadderPrices>) {
    out[tier] = readPrice(row, TIER_TO_FIELD[tier]);
  }
  return out as LadderPrices;
}

export function pickTier(
  row: PCProductRow,
  service: GradingService,
  grade: string,
): number | null {
  const key = gradeKeyFor(service, grade);
  if (!key) return null;
  // `loose` would never be requested via (service, grade) — gradeKeyFor never
  // returns it. Map TierKey -> LadderPrices key.
  const ladder = extractLadder(row);
  return ladder[key as keyof LadderPrices] ?? null;
}

export function ladderHasAnyPrice(ladder: LadderPrices): boolean {
  return Object.values(ladder).some(v => v !== null);
}

function slugify(s: string): string {
  return s.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

// PriceCharting product pages live at /game/<console-slug>/<product-slug>.
// Derive deterministically from the row so we don't depend on a `url`
// field that PriceCharting may or may not return.
export function productUrl(row: PCProductRow): string {
  const console_ = slugify(row["console-name"] ?? "pokemon");
  const product = slugify(row["product-name"] ?? row.id ?? "");
  return `https://www.pricecharting.com/game/${console_}/${product}`;
}
