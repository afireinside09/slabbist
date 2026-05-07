// supabase/functions/price-comp/lib/grade-key.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import type { GradingService } from "../types.ts";

export type TierKey =
  | "loose"
  | "psa_7"
  | "psa_8"
  | "psa_9"
  | "psa_9_5"
  | "psa_10"
  | "bgs_10"
  | "cgc_10"
  | "sgc_10";

// Strip PSA's verbose adjectives ("GEM MT 10" -> "10") and trim whitespace.
function bareGrade(grade: string): string {
  const m = grade.trim().match(/(\d+(?:\.\d+)?)$/);
  return m ? m[1] : grade.trim();
}

export function gradeKeyFor(service: GradingService, grade: string): TierKey | null {
  const g = bareGrade(grade);
  if (service === "PSA") {
    if (g === "10")  return "psa_10";
    if (g === "9.5") return "psa_9_5";
    if (g === "9")   return "psa_9";
    if (g === "8")   return "psa_8";
    if (g === "7")   return "psa_7";
    return null;
  }
  if (g === "10") {
    if (service === "BGS") return "bgs_10";
    if (service === "CGC") return "cgc_10";
    if (service === "SGC") return "sgc_10";
  }
  return null;
}
