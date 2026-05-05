// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.

// supabase/functions/price-comp/lib/grade-normalize.ts
//
// PSA's `CardGrade` field returns verbose labels like "GEM MT 10",
// "MINT 9", "NM-MT 8" — accurate for the slab insert but useless for
// matching against eBay listing titles, which sellers always
// abbreviate to just `<grader> <number>`. This helper extracts the
// trailing numeric grade so price-comp can build queries that look
// like a normal human's eBay search.
//
// Examples:
//   "GEM MT 10"  → "10"
//   "MINT 9"     → "9"
//   "NM-MT 8"    → "8"
//   "MINT 9.5"   → "9.5"
//   "10"         → "10"   (already-normalized passes through)
//   "AUTHENTIC"  → "AUTHENTIC"  (no number, return as-is)

const TRAILING_NUMBER = /(\d+(?:\.5)?)\s*$/;

export function normalizeGrade(raw: string): string {
  const trimmed = raw.trim();
  const m = trimmed.match(TRAILING_NUMBER);
  return m ? m[1]! : trimmed;
}
