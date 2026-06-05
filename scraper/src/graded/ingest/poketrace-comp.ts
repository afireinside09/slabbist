// scraper/src/graded/ingest/poketrace-comp.ts (pure core; DB wiring in runPoketraceCompIngest below)
import type { SearchResult, Psa10Result } from "@/graded/sources/poketrace.js";

export interface CompProduct { productId: number; resolvedAt: string | null }

export interface CompUpsertRow {
  product_id: number;
  poketrace_card_id: string;
  psa10_price_cents: number;
  pt_sale_count: number | null;
  resolved_at: string;
}

export interface BackfillDeps {
  now: () => number;
  dailyFloor: number;
  maxRequests: number;
  search: (tcgplayerId: number) => Promise<SearchResult>;
  detail: (cardId: string) => Promise<Psa10Result>;
  upsert: (row: CompUpsertRow) => Promise<void>;
}

export interface BackfillResult {
  covered: number;       // wrote a real comp (uuid + PSA 10 price)
  noMatch: number;       // search found no card — nothing written
  noPrice: number;       // matched a card but it has no PSA 10 price — nothing written
  transient: number;     // skipped, will retry next run
  skippedFresh: number;  // < 7d old, untouched
  requests: number;
  stoppedOnBudget: boolean;
}

const SEVEN_DAYS = 7 * 86_400_000;

// We only persist rows that carry a usable PSA 10 price. No-match and
// matched-but-no-price products write nothing — keeping tcg_grade_comp to the
// rows the Grade Gains page actually reads. The trade-off is that those
// products are re-resolved each run (they are no longer negatively cached).
export async function backfillProducts(products: CompProduct[], deps: BackfillDeps): Promise<BackfillResult> {
  const r: BackfillResult = { covered: 0, noMatch: 0, noPrice: 0, transient: 0, skippedFresh: 0, requests: 0, stoppedOnBudget: false };
  const nowMs = deps.now();
  for (const p of products) {
    if (p.resolvedAt && nowMs - Date.parse(p.resolvedAt) < SEVEN_DAYS) { r.skippedFresh++; continue; }
    if (r.requests >= deps.maxRequests) { r.stoppedOnBudget = true; break; }

    const s = await deps.search(p.productId);
    r.requests++;
    if (s.cardId === undefined) { r.transient++; }        // transient — write nothing
    else if (s.cardId === null) { r.noMatch++; }          // confirmed no match — write nothing
    else {                                                // match — fetch PSA 10
      const d = await deps.detail(s.cardId);
      r.requests++;
      if (d.psa10PriceCents !== null) {                   // only persist priced comps
        await deps.upsert({
          product_id: p.productId, poketrace_card_id: s.cardId, psa10_price_cents: d.psa10PriceCents,
          pt_sale_count: d.ptSaleCount, resolved_at: new Date(nowMs).toISOString(),
        });
        r.covered++;
      } else {
        r.noPrice++;
      }
      if (d.dailyRemaining !== null && d.dailyRemaining < deps.dailyFloor) { r.stoppedOnBudget = true; break; }
    }
    if (s.dailyRemaining !== null && s.dailyRemaining < deps.dailyFloor) { r.stoppedOnBudget = true; break; }
    if (r.requests >= deps.maxRequests) { r.stoppedOnBudget = true; break; }
  }
  return r;
}

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Logger } from "@/shared/logger.js";
import { throwIfError } from "@/shared/db/supabase.js";
import { searchCardId, fetchPsa10, type PoketraceClient } from "@/graded/sources/poketrace.js";

export interface RunOptions {
  supabase: SupabaseClient;
  client: PoketraceClient;
  dailyFloor: number;
  maxRequests: number;
  log: Logger;
}

/**
 * Pull English (category 3) candidate products newest-set-first, one group
 * at a time. A single global product sort exceeded the statement timeout;
 * instead we walk groups newest-first (cheap) and pull each group's stale
 * candidates by the group_id index (cheap), stopping once we have `limit`.
 */
async function loadCandidatesNewestFirst(supabase: SupabaseClient, limit: number): Promise<CompProduct[]> {
  const { data: groups, error: gErr } = await supabase.rpc("grade_comp_groups");
  if (gErr) throw gErr;
  const out: CompProduct[] = [];
  for (const g of ((groups ?? []) as { group_id: number }[])) {
    if (out.length >= limit) break;
    const { data, error } = await supabase.rpc("grade_comp_candidates_for_group", { p_group_id: g.group_id });
    if (error) throw error;
    for (const r of ((data ?? []) as { product_id: number; resolved_at: string | null }[])) {
      out.push({ productId: r.product_id, resolvedAt: r.resolved_at });
      if (out.length >= limit) break;
    }
  }
  return out;
}

export async function runPoketraceCompIngest(opts: RunOptions): Promise<BackfillResult & { runId: string }> {
  const runId = crypto.randomUUID();
  await throwIfError(opts.supabase.from("graded_ingest_runs").insert({
    id: runId, source: "poketrace-comp", status: "running", started_at: new Date().toISOString(), stats: {},
  }));
  try {
    const fetchLimit = Number.isFinite(opts.maxRequests) ? opts.maxRequests : 6000;
    const products = await loadCandidatesNewestFirst(opts.supabase, fetchLimit);
    const result = await backfillProducts(products, {
      now: () => Date.now(),
      dailyFloor: opts.dailyFloor,
      maxRequests: opts.maxRequests,
      search: (id) => searchCardId(opts.client, id),
      detail: (cardId) => fetchPsa10(opts.client, cardId),
      upsert: async (row) => {
        await throwIfError(opts.supabase.from("tcg_grade_comp").upsert(row, { onConflict: "product_id" }));
      },
    });
    opts.log.info("grade-comp backfill", { ...result });
    await throwIfError(opts.supabase.from("graded_ingest_runs").update({
      status: "completed", finished_at: new Date().toISOString(), stats: result as unknown as Record<string, number>,
    }).eq("id", runId));
    return { ...result, runId };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    await opts.supabase.from("graded_ingest_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg,
    }).eq("id", runId);
    throw e;
  }
}
