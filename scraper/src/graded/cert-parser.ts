import type { GradingService } from "@/graded/models.js";

const SERVICE_PATTERN = /\b(PSA|CGC|BGS|SGC|TAG)\s*([0-9]+(?:\.5)?)/i;
const CERT_PATTERN = /\b(?:cert|cert\s*#|certificate)\s*#?\s*([0-9]{5,})\b/i;

export interface ParsedTitle {
  gradingService: GradingService;
  grade: string;
  certNumber: string | null;
}

export function parseGradedTitle(title: string): ParsedTitle | null {
  const m = title.match(SERVICE_PATTERN);
  if (!m) return null;
  const gradingService = m[1]!.toUpperCase() as GradingService;
  const grade = m[2]!;
  const certMatch = title.match(CERT_PATTERN);
  const certNumber = certMatch ? certMatch[1]! : null;
  return { gradingService, grade, certNumber };
}
