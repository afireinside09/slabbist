import { z } from "zod";
import { httpJson } from "@/shared/http/fetch.js";
import type { GradedCertRecord, PopRow } from "@/graded/models.js";

const PSA_BASE = "https://api.psacard.com/publicapi";

const CertLookupResponse = z.object({
  PSACert: z.object({
    CertNumber: z.string(),
    Grade: z.string(),
    Brand: z.string(),
    Subject: z.string(),
    Variety: z.string().nullable().optional(),
    CardNumber: z.string().nullable().optional(),
    Year: z.string().nullable().optional(),
    GradedDate: z.string().nullable().optional(),
  }),
});

const PopReportResponse = z.object({
  SpecID: z.number(),
  Subject: z.string(),
  CardNumber: z.string().nullable().optional(),
  Brand: z.string(),
  Year: z.string().nullable().optional(),
  Variety: z.string().nullable().optional(),
  Pops: z.array(z.object({ Grade: z.string(), Population: z.number() })),
});

export interface PsaOpts { apiKey: string; userAgent: string; }

function headers(opts: PsaOpts): Record<string, string> {
  return { Authorization: `Bearer ${opts.apiKey}` };
}

export async function psaCertLookup(certNumber: string, opts: PsaOpts): Promise<GradedCertRecord> {
  const body = await httpJson(`${PSA_BASE}/cert/GetByCertNumber/${certNumber}`, {
    userAgent: opts.userAgent, headers: headers(opts),
  });
  const p = CertLookupResponse.parse(body).PSACert;
  return {
    gradingService: "PSA",
    certNumber: p.CertNumber,
    grade: p.Grade,
    gradedAt: p.GradedDate ?? null,
    identity: {
      game: "pokemon",
      language: "en",
      setName: p.Brand,
      cardName: p.Subject,
      cardNumber: p.CardNumber ?? null,
      variant: p.Variety ?? null,
      year: p.Year ? Number(p.Year) : null,
    },
    sourcePayload: body,
  };
}

export async function psaPopReport(specId: number, opts: PsaOpts): Promise<PopRow[]> {
  const body = await httpJson(`${PSA_BASE}/pop/GetPSASpecPopulation/${specId}`, {
    userAgent: opts.userAgent, headers: headers(opts),
  });
  const p = PopReportResponse.parse(body);
  return p.Pops.map((pop) => ({
    gradingService: "PSA",
    grade: pop.Grade,
    population: pop.Population,
    identity: {
      game: "pokemon",
      language: "en",
      setName: p.Brand,
      cardName: p.Subject,
      cardNumber: p.CardNumber ?? null,
      variant: p.Variety ?? null,
      year: p.Year ? Number(p.Year) : null,
    },
  }));
}
