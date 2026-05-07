// supabase/functions/price-comp/lib/tcg-products.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Local lookup against the `tcg_products` table for Tier A of the resolver.
//
// Given a tcg_groups.group_id (looked up via PSA-set-name alias) and a
// PSA cert's card_number / card_name, returns the matching
// `tcg_products.product_id`. That product_id IS the same integer PPT
// uses as `tcgPlayerId`, so the caller can hit PPT directly with no
// fuzzy search at all.
//
// Strategy:
//   1. Normalize PSA's card_number into a few prefix variants (PSA
//      pads with zeros — "020" — while TCGPlayer rows show up as
//      "020/198", "20/198", or sometimes the bare "020"). We OR
//      together exact + prefix variants and let Postgres index the
//      filter.
//   2. Score each candidate row: +5 for an exact (post-normalization)
//      card_number match, +2 for a name-substring overlap with the
//      PSA card_name (after stripping parens). Anything < 5 is dropped
//      so we don't accidentally bind to the wrong card just because
//      it happens to share a set.
//   3. If `cardNumber` is null on the identity, skip the card_number
//      filter and return the best name-overlap match (lower
//      confidence; +2 is enough since name+set is the only signal).

import type { SupabaseClient } from "@supabase/supabase-js";

export interface TcgProductMatch {
  productId: number;
  cardName: string;
  cardNumber: string;
}

interface CandidateRow {
  product_id: number;
  card_number: string | null;
  name: string | null;
}

interface FindArgs {
  groupId: number;
  cardNumber: string | null;
  cardName: string;
}

/**
 * Strip leading zeros while preserving single "0". "020" → "20",
 * "001" → "1", "0" → "0", "10" → "10".
 */
function stripLeadingZeros(s: string): string {
  if (!s) return s;
  const stripped = s.replace(/^0+/, "");
  return stripped.length > 0 ? stripped : "0";
}

/**
 * Normalize for *exact* equality: strip "/<denominator>", lowercase,
 * drop non-alphanumerics, strip leading zeros. Used for the +5 scoring
 * branch.
 */
function normalizeForCompare(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const beforeSlash = String(raw).split("/")[0];
  const lower = beforeSlash.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (!lower) return null;
  return stripLeadingZeros(lower);
}

function cleanName(name: string): string {
  return (name ?? "").replace(/\s*\([^)]*\)\s*/g, " ").trim().replace(/\s+/g, " ").toLowerCase();
}

function buildCardNumberVariants(raw: string): string[] {
  // Inputs come from PSA cert (e.g. "4", "020", "199", "SWSH285"). Build
  // the list of likely card_number column shapes in tcg_products.
  //
  // We generate three forms for each zero-padding level (original,
  // stripped, 2-digit-padded, 3-digit-padded) so that PSA "4" matches
  // tcg_products rows like "04/62" and "004/XXX", and PSA "020" matches
  // both "020/198" and "20/198".
  const variants = new Set<string>();
  const trimmed = raw.trim();
  if (!trimmed) return [];

  // Only the numeric prefix (before any slash) matters for padding logic.
  const slashIdx = trimmed.indexOf("/");
  const prefix = slashIdx >= 0 ? trimmed.slice(0, slashIdx) : trimmed;
  const isNumeric = /^\d+$/.test(prefix);

  // Helper: add exact + slash-prefix + bare-prefix variants for one value.
  function addVariants(v: string) {
    variants.add(v);          // exact (e.g. "04")
    variants.add(`${v}/%`);   // slash-prefix  (e.g. "04/%")
    variants.add(`${v}%`);    // bare prefix   (e.g. "04%")
  }

  // 1. The original PSA value and its prefix forms.
  addVariants(trimmed);

  if (isNumeric) {
    const stripped = stripLeadingZeros(prefix);

    // 2. Leading-zeros-stripped variants (e.g. "020" → "20").
    if (stripped !== prefix) {
      addVariants(stripped);
    }

    // 3. Zero-padded to 2 digits.
    if (prefix.length < 2) {
      const pad2 = prefix.padStart(2, "0");
      addVariants(pad2);
    }

    // 4. Zero-padded to 3 digits.
    if (prefix.length < 3) {
      const pad3 = prefix.padStart(3, "0");
      addVariants(pad3);
    }
  }

  return Array.from(variants);
}

function buildOrFilter(variants: string[]): string {
  // Supabase PostgREST OR filter: comma-joined list of `col.op.val`.
  // First entry is exact; the rest are ILIKE patterns.
  const parts: string[] = [];
  if (variants.length > 0) {
    parts.push(`card_number.eq.${variants[0]}`);
    for (let i = 1; i < variants.length; i += 1) {
      parts.push(`card_number.ilike.${variants[i]}`);
    }
  }
  return parts.join(",");
}

/**
 * Look up a tcg_products row that best matches the given identity. See
 * file header for scoring rules.
 */
export async function findTcgProductByGroupAndCard(
  supabase: SupabaseClient | unknown,
  args: FindArgs,
): Promise<TcgProductMatch | null> {
  const sb = supabase as SupabaseClient;
  const { groupId, cardNumber, cardName } = args;

  let query: any = sb.from("tcg_products")
    .select("product_id, name, card_number")
    .eq("group_id", groupId);

  if (cardNumber && cardNumber.trim().length > 0) {
    const variants = buildCardNumberVariants(cardNumber);
    const orFilter = buildOrFilter(variants);
    if (orFilter) query = query.or(orFilter);
  }

  const { data, error } = await query.limit(20);
  if (error) return null;
  const rows = (data ?? []) as CandidateRow[];
  if (rows.length === 0) return null;

  const psaNum = normalizeForCompare(cardNumber);
  const psaName = cleanName(cardName);

  let best: { row: CandidateRow; score: number } | null = null;
  let bestCount = 0; // how many rows share the top score (tie-breaking)
  for (const row of rows) {
    let score = 0;
    const rowNum = normalizeForCompare(row.card_number);
    if (psaNum && rowNum && psaNum === rowNum) score += 5;
    const rowName = cleanName(row.name ?? "");
    if (rowName && psaName) {
      if (rowName.includes(psaName) || psaName.includes(rowName)) score += 2;
    }
    if (best === null || score > best.score) {
      best = { row, score };
      bestCount = 1;
    } else if (score === best.score) {
      bestCount += 1;
    }
  }

  if (!best) return null;

  // Threshold: when we have a PSA card_number we require an exact match
  // (+5) — name overlap alone (+2) is too weak to bind on. When PSA's
  // card_number is null, we accept on name overlap alone (+2), but we
  // require the name match to be unambiguous — if multiple candidates
  // share the same top score we return null rather than guess.
  const minScore = cardNumber ? 5 : 2;
  if (best.score < minScore) return null;

  // When card_number is null, name is the sole signal; an ambiguous tie
  // is worse than no match (false positives are more harmful than misses).
  if (!cardNumber && bestCount > 1) return null;

  return {
    productId: best.row.product_id,
    cardName: best.row.name ?? "",
    cardNumber: best.row.card_number ?? "",
  };
}
