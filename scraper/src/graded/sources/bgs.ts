import { httpText } from "@/shared/http/fetch.js";
import type { GradedCertRecord } from "@/graded/models.js";

const BGS_BASE = "https://www.beckett-grading.com/population-report/cert-lookup";

function cellByHeader(html: string, header: string): string | null {
  const re = new RegExp(
    `<tr>\\s*<th[^>]*>\\s*${header.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}\\s*</th>\\s*<td[^>]*>([\\s\\S]*?)</td>`,
    "i",
  );
  const m = html.match(re);
  return m ? m[1]!.replace(/<[^>]+>/g, "").trim() : null;
}

export interface BgsOpts { userAgent: string; }

export async function bgsCertLookup(certNumber: string, opts: BgsOpts): Promise<GradedCertRecord> {
  const html = await httpText(`${BGS_BASE}?cert=${encodeURIComponent(certNumber)}`, { userAgent: opts.userAgent });
  if (!/cert-info/.test(html)) throw new Error(`BGS cert not found: ${certNumber}`);
  const grade = cellByHeader(html, "Grade") ?? "";
  return {
    gradingService: "BGS",
    certNumber,
    grade,
    gradedAt: null,
    identity: {
      game: "pokemon",
      language: "en",
      setName: cellByHeader(html, "Set") ?? "",
      cardName: cellByHeader(html, "Player") ?? "",
      cardNumber: cellByHeader(html, "Card Number"),
      variant: cellByHeader(html, "Attributes"),
      year: (() => { const y = cellByHeader(html, "Year"); return y ? Number(y) : null; })(),
    },
    sourcePayload: { html: html.slice(0, 10_000) },
  };
}
