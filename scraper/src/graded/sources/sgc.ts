import { httpText } from "@/shared/http/fetch.js";
import type { GradedCertRecord } from "@/graded/models.js";

const SGC_BASE = "https://gosgc.com/certlookup";

function dtValue(html: string, key: string): string | null {
  const re = new RegExp(
    `<dt>\\s*${key.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}\\s*</dt>\\s*<dd>([\\s\\S]*?)</dd>`,
    "i",
  );
  const m = html.match(re);
  return m ? m[1]!.replace(/<[^>]+>/g, "").trim() : null;
}

export interface SgcOpts { userAgent: string; }

export async function sgcCertLookup(certNumber: string, opts: SgcOpts): Promise<GradedCertRecord> {
  const html = await httpText(`${SGC_BASE}/${certNumber}`, { userAgent: opts.userAgent });
  if (!/cert-result/.test(html)) throw new Error(`SGC cert not found: ${certNumber}`);
  return {
    gradingService: "SGC",
    certNumber,
    grade: dtValue(html, "Grade") ?? "",
    gradedAt: null,
    identity: {
      game: "pokemon",
      language: "en",
      setName: dtValue(html, "Set") ?? "",
      cardName: dtValue(html, "Player") ?? "",
      cardNumber: dtValue(html, "Card Number"),
      variant: dtValue(html, "Variety"),
      year: (() => { const y = dtValue(html, "Year"); return y ? Number(y) : null; })(),
    },
    sourcePayload: { html: html.slice(0, 10_000) },
  };
}
