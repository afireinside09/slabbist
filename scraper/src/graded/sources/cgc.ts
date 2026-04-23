import { httpText } from "@/shared/http/fetch.js";
import type { GradedCertRecord } from "@/graded/models.js";

const CGC_BASE = "https://www.cgccards.com/certlookup";

function fieldByLabel(html: string, label: string): string | null {
  const re = new RegExp(
    `<div[^>]*data-label="${label.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}"[^>]*>([^<]*)</div>`,
    "i",
  );
  const m = html.match(re);
  return m ? m[1]!.trim() : null;
}

export interface CgcOpts { userAgent: string; }

export async function cgcCertLookup(certNumber: string, opts: CgcOpts): Promise<GradedCertRecord> {
  const html = await httpText(`${CGC_BASE}/${certNumber}/`, { userAgent: opts.userAgent });
  if (!/cert-details/.test(html)) throw new Error(`CGC cert not found: ${certNumber}`);

  const grade = fieldByLabel(html, "Grade") ?? "";
  const setName = fieldByLabel(html, "Set") ?? "";
  const cardName = fieldByLabel(html, "Card") ?? "";
  const cardNumber = fieldByLabel(html, "Card Number");
  const year = fieldByLabel(html, "Year");
  const variant = fieldByLabel(html, "Variant");
  const languageRaw = (fieldByLabel(html, "Language") ?? "English").toLowerCase();
  const gradedAt = fieldByLabel(html, "Date Graded");

  return {
    gradingService: "CGC",
    certNumber,
    grade,
    gradedAt: gradedAt ?? null,
    identity: {
      game: "pokemon",
      language: languageRaw.startsWith("jap") ? "jp" : "en",
      setName,
      cardName,
      cardNumber: cardNumber ?? null,
      variant: variant ?? null,
      year: year ? Number(year) : null,
    },
    sourcePayload: { html: html.slice(0, 10_000) },
  };
}
