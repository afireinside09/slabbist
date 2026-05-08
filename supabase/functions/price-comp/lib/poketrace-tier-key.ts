// supabase/functions/price-comp/lib/poketrace-tier-key.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Build a Poketrace tier key from a (gradingService, grade) pair as the
// app stores them on graded_market. The graded_market.grade column stores
// human-readable strings like "GEM MT 10" or "MINT 9" (PPT-shape), so we
// strip the verbose adjectives down to a bare number first. Poketrace's
// tier strings then replace '.' with '_' in the grade portion.
//
//   ('PSA', '10')         -> 'PSA_10'
//   ('PSA', '9.5')        -> 'PSA_9_5'
//   ('PSA', 'GEM MT 10')  -> 'PSA_10'
//   ('PSA', 'MINT 9')     -> 'PSA_9'
//   ('BGS', '10')         -> 'BGS_10'
//
// Documented at https://poketrace.com/docs/markets-tiers.

import type { GradingService } from "../types.ts";

// Strip PSA's verbose adjectives ("GEM MT 10" -> "10") and trim whitespace.
// Mirrors `bareGrade` in lib/grade-key.ts (kept duplicated to avoid widening
// that helper's public API for an unrelated consumer).
function bareGrade(grade: string): string {
  const m = grade.trim().match(/(\d+(?:\.\d+)?)$/);
  return m ? m[1] : grade.trim();
}

export function poketraceTierKey(
  service: GradingService | string,
  grade: string,
): string {
  const numeric = bareGrade(grade);
  return `${service.toUpperCase()}_${numeric.replace(".", "_")}`;
}
