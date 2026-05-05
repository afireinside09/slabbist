// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.

// supabase/functions/price-comp/lib/card-name-normalize.ts
//
// PSA returns names like "CHARIZARD-HOLO" or "BLASTOISE-HOLO" — the
// trailing "-<TAG>" is PSA's variant marker, not how sellers write
// titles. Strip it so the eBay query reads like a human search:
// "Charizard 4/102" instead of "Charizard-Holo 4/102".
//
// Multiple suffixes are stripped greedily from the right
// (e.g. "PIKACHU-HOLO-1ST" → "PIKACHU"). Hyphens that appear inside
// the actual name (rare for Pokémon, but possible in promos) are not
// touched — only the trailing tag tokens listed below.

const TRAILING_VARIANT_TAGS = new Set([
  "HOLO",
  "REVERSE",
  "REVERSEHOLO",
  "REV-HOLO",
  "FOIL",
  "1ST",
  "1STED",
  "FIRSTEDITION",
  "SHADOWLESS",
  "PROMO",
]);

export function normalizeCardName(raw: string): string {
  let out = raw.trim();
  while (true) {
    const idx = out.lastIndexOf("-");
    if (idx < 0) break;
    const tail = out.slice(idx + 1).toUpperCase().replace(/\s+/g, "");
    if (!TRAILING_VARIANT_TAGS.has(tail)) break;
    out = out.slice(0, idx).trimEnd();
  }
  return out;
}
