// supabase/functions/price-comp/lib/poketrace-tier-key.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Build a Poketrace tier key from a (gradingService, grade) pair as the
// app stores them on graded_market. Poketrace's tier strings replace
// '.' with '_' in the grade portion.
//
//   ('PSA', '10')  -> 'PSA_10'
//   ('PSA', '9.5') -> 'PSA_9_5'
//   ('BGS', '10')  -> 'BGS_10'
//
// Documented at https://poketrace.com/docs/markets-tiers.

import type { GradingService } from "../types.ts";

export function poketraceTierKey(
  service: GradingService | string,
  grade: string,
): string {
  return `${service.toUpperCase()}_${grade.replace(".", "_")}`;
}
