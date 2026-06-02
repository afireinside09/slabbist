// scraper/src/graded/ingest/poketrace-comp.ts (pure core; DB wiring in runPoketraceCompIngest below)
import type { SearchResult, Psa10Result } from "@/graded/sources/poketrace.js";

export interface CompProduct { productId: number; resolvedAt: string | null }

export interface CompUpsertRow {
  product_id: number;
  poketrace_card_id: string;
  psa10_price_cents: number | null;
  pt_trend: string | null;
  pt_confidence: string | null;
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
  covered: number;       // wrote a real comp (uuid + maybe price)
  noMatch: number;       // wrote the '' sentinel
  transient: number;     // skipped, will retry next run
  skippedFresh: number;  // < 7d old, untouched
  requests: number;
  stoppedOnBudget: boolean;
}

const SEVEN_DAYS = 7 * 86_400_000;

export async function backfillProducts(products: CompProduct[], deps: BackfillDeps): Promise<BackfillResult> {
  const r: BackfillResult = { covered: 0, noMatch: 0, transient: 0, skippedFresh: 0, requests: 0, stoppedOnBudget: false };
  const nowMs = deps.now();
  for (const p of products) {
    if (p.resolvedAt && nowMs - Date.parse(p.resolvedAt) < SEVEN_DAYS) { r.skippedFresh++; continue; }
    if (r.requests >= deps.maxRequests) { r.stoppedOnBudget = true; break; }

    const s = await deps.search(p.productId);
    r.requests++;
    if (s.cardId === undefined) { r.transient++; }       // transient — write nothing
    else if (s.cardId === null) {                         // confirmed no match — sentinel
      await deps.upsert({
        product_id: p.productId, poketrace_card_id: "", psa10_price_cents: null,
        pt_trend: null, pt_confidence: null, pt_sale_count: null,
        resolved_at: new Date(nowMs).toISOString(),
      });
      r.noMatch++;
    } else {                                              // match — fetch PSA 10
      const d = await deps.detail(s.cardId);
      r.requests++;
      await deps.upsert({
        product_id: p.productId, poketrace_card_id: s.cardId, psa10_price_cents: d.psa10PriceCents,
        pt_trend: d.ptTrend, pt_confidence: d.ptConfidence, pt_sale_count: d.ptSaleCount,
        resolved_at: new Date(nowMs).toISOString(),
      });
      r.covered++;
      if (d.dailyRemaining !== null && d.dailyRemaining < deps.dailyFloor) { r.stoppedOnBudget = true; break; }
    }
    if (s.dailyRemaining !== null && s.dailyRemaining < deps.dailyFloor) { r.stoppedOnBudget = true; break; }
    if (r.requests >= deps.maxRequests) { r.stoppedOnBudget = true; break; }
  }
  return r;
}
