// supabase/functions/price-comp/lib/graded-title-parse.ts
// Vendored from scraper/src/graded/cert-parser.ts (2026-04-23).
// Keep in sync if the scraper copy changes.

import type { GradingService } from "../types.ts";

const SERVICE_PATTERN = /\b(PSA|CGC|BGS|SGC|TAG)\s*([0-9]+(?:\.5)?)/i;

export interface ParsedTitle {
  gradingService: GradingService;
  grade: string;
}

export function parseGradedTitle(title: string): ParsedTitle | null {
  const m = title.match(SERVICE_PATTERN);
  if (!m) return null;
  return {
    gradingService: m[1]!.toUpperCase() as GradingService,
    grade: m[2]!,
  };
}
