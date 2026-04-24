import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradingService } from "@/graded/models.js";

export const GRADE_TIERS_BY_SERVICE: Record<GradingService, readonly string[]> = {
  PSA: ["10", "9", "8"],
  CGC: ["10", "9.5"],
  BGS: ["10", "9.5"],
  SGC: ["10"],
  TAG: ["10"],
};

export interface WatchlistQueryRow {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  popularityRank: number | null;
  cardName: string;
  setName: string;
  year: number | null;
}

export function buildEbayQueryForWatchlistRow(row: WatchlistQueryRow): string {
  const parts: string[] = [];
  parts.push(`"${row.cardName}"`);
  if (row.setName) parts.push(`"${row.setName}"`);
  if (row.year) parts.push(String(row.year));
  parts.push(row.gradingService);
  parts.push(row.grade);
  return parts.join(" ");
}

export async function fetchActiveWatchlistQueries(
  supabase: SupabaseClient,
  limit = 2000,
): Promise<string[]> {
  const { data, error } = await supabase
    .from("graded_watchlist")
    .select(
      "identity_id, grading_service, grade, popularity_rank, " +
      "graded_card_identities(card_name, set_name, year)",
    )
    .eq("is_active", true)
    .order("popularity_rank", { ascending: true, nullsFirst: false })
    .limit(limit);
  if (error) throw new Error(`supabase: ${error.message}`);

  const queries: string[] = [];
  const seen = new Set<string>();
  const rows = (data ?? []) as unknown as Array<Record<string, unknown>>;
  for (const row of rows) {
    const identity = row.graded_card_identities as
      | { card_name?: string; set_name?: string; year?: number | null }
      | null;
    if (!identity || !identity.card_name) continue;
    const service = String(row.grading_service);
    if (!isGradingService(service)) continue;
    const q = buildEbayQueryForWatchlistRow({
      identityId: String(row.identity_id),
      gradingService: service,
      grade: String(row.grade),
      popularityRank: (row.popularity_rank as number | null) ?? null,
      cardName: identity.card_name,
      setName: identity.set_name ?? "",
      year: identity.year ?? null,
    });
    if (seen.has(q)) continue;
    seen.add(q);
    queries.push(q);
  }
  return queries;
}

function isGradingService(s: string): s is GradingService {
  return s === "PSA" || s === "CGC" || s === "BGS" || s === "SGC" || s === "TAG";
}
