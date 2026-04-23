// src/graded/ingest/pop-reports.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService, PopRow } from "@/graded/models.js";
import { findOrCreateIdentity } from "@/graded/identity.js";
import { psaPopReport } from "@/graded/sources/psa.js";
import { throwIfError } from "@/shared/db/supabase.js";

export interface PopIngestOptions {
  supabase: SupabaseClient;
  userAgent: string;
  services: Array<GradingService | "psa" | "cgc" | "bgs" | "sgc" | "tag">;
  psa?: { apiKey: string; specIds: number[] };
}

export interface PopIngestResult {
  runId: string;
  status: "completed" | "failed";
  stats: Record<string, number | string>;
  errorMessage?: string;
}

export async function runPopReportIngest(opts: PopIngestOptions): Promise<PopIngestResult> {
  const runId = crypto.randomUUID();
  await throwIfError(opts.supabase.from("graded_ingest_runs").insert({
    id: runId, source: "pop", status: "running", started_at: new Date().toISOString(), stats: {},
  }));
  const stats: Record<string, number | string> = {};
  try {
    const all: PopRow[] = [];
    for (const s of opts.services) {
      const svc = String(s).toLowerCase();
      if (svc === "psa") {
        if (!opts.psa || opts.psa.specIds.length === 0) {
          // Warn but do not fail — other services can still run.
          stats["psa_skipped"] = "no_spec_ids";
          continue;
        }
        for (const specId of opts.psa.specIds) {
          const rows = await psaPopReport(specId, { apiKey: opts.psa.apiKey, userAgent: opts.userAgent });
          all.push(...rows);
          stats["psa"] = (Number(stats["psa"] ?? 0)) + rows.length;
        }
      }
      // Other services gate on opts.<svc> being configured; placeholder for future sources.
    }

    for (const row of all) {
      const identityId = await findOrCreateIdentity(opts.supabase, row.identity);
      await throwIfError(opts.supabase.from("graded_card_pops").insert({
        identity_id: identityId, grading_service: row.gradingService, grade: row.grade,
        population: row.population, captured_at: new Date().toISOString(),
      }));
    }

    await throwIfError(opts.supabase.from("graded_ingest_runs").update({
      status: "completed", finished_at: new Date().toISOString(), stats,
    }).eq("id", runId));
    return { runId, status: "completed", stats };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    await opts.supabase.from("graded_ingest_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg, stats,
    }).eq("id", runId);
    return { runId, status: "failed", stats, errorMessage: msg };
  }
}
