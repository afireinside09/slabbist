import { z } from "zod";
import { httpJson } from "@/shared/http/fetch.js";
import type { GradedCertRecord } from "@/graded/models.js";

const TAG_BASE = "https://api.taggrading.com/v1/cert";

const CertResponse = z.object({
  cert: z.object({
    certId: z.string(),
    grade: z.string(),
    game: z.string(),
    setName: z.string(),
    year: z.number().nullable().optional(),
    cardName: z.string(),
    cardNumber: z.string().nullable().optional(),
    variant: z.string().nullable().optional(),
    language: z.string().nullable().optional(),
    gradedOn: z.string().nullable().optional(),
  }),
});

export interface TagOpts { userAgent: string; apiKey?: string; }

export async function tagCertLookup(certNumber: string, opts: TagOpts): Promise<GradedCertRecord> {
  const body = await httpJson(`${TAG_BASE}/${encodeURIComponent(certNumber)}`, {
    userAgent: opts.userAgent,
    headers: opts.apiKey ? { Authorization: `Bearer ${opts.apiKey}` } : {},
  });
  const parsed = CertResponse.parse(body).cert;
  return {
    gradingService: "TAG",
    certNumber: parsed.certId,
    grade: parsed.grade,
    gradedAt: parsed.gradedOn ?? null,
    identity: {
      game: "pokemon",
      language: (parsed.language ?? "").toLowerCase().startsWith("jap") ? "jp" : "en",
      setName: parsed.setName,
      cardName: parsed.cardName,
      cardNumber: parsed.cardNumber ?? null,
      variant: parsed.variant ?? null,
      year: parsed.year ?? null,
    },
    sourcePayload: body,
  };
}
