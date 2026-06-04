// supabase/functions/price-comp/types.ts

export type GradingService = "PSA" | "BGS" | "CGC" | "SGC" | "TAG";

export interface GradedCardIdentity {
  id: string;
  game: "pokemon";
  language: "en" | "jp" | string;
  set_code: string | null;
  set_name: string;
  card_number: string | null;
  card_name: string;
  variant: string | null;
  year: number | null;
  tcgplayer_product_id: string | null;
}

export interface PriceCompRequest {
  graded_card_identity_id: string;
  grading_service: GradingService;
  grade: string;
}

export interface PriceHistoryWirePoint {
  ts: string;
  price_cents: number;
}

export type CacheState = "hit" | "miss" | "stale";

// ---- Poketrace -------------------------------------------------------------

export interface PoketraceTierFields {
  avg_cents:        number | null;
  low_cents:        number | null;
  high_cents:       number | null;
  avg_1d_cents:     number | null;
  avg_7d_cents:     number | null;
  avg_30d_cents:    number | null;
  median_3d_cents:  number | null;
  median_7d_cents:  number | null;
  median_30d_cents: number | null;
  trend:            "up" | "down" | "stable" | null;
  confidence:       "high" | "medium" | "low" | null;
  sale_count:       number | null;
}

/**
 * Per-tier ladder map for the iOS comp-card. Keys are snake_case tier ids
 * ("loose", "psa_7", "psa_8", "psa_9", "psa_9_5", "psa_10", "bgs_10",
 * "cgc_10", "sgc_10"); values are integer cents.
 *
 * Populated when the Poketrace card-detail response contains a matching
 * tier under any of its top-level price source keys (typically `ebay`
 * for US graded data). Tiers that aren't present are simply absent from
 * the map — iOS treats absence as "no data" for that cell.
 */
export type PoketraceLadderCents = Record<string, number>;

export interface PoketraceBlock extends PoketraceTierFields {
  card_id: string;
  tier:    string;                 // e.g. "PSA_10"
  tier_prices_cents: PoketraceLadderCents;
  price_history: PriceHistoryWirePoint[];
  fetched_at: string;
}

export interface SoldListingWire {
  source_listing_id: string;
  title: string | null;
  price_cents: number | null;
  sold_at: string;            // ISO8601
  grader: string | null;      // PSA | BGS | CGC | SGC
  grade: string | null;
  condition: string | null;
  url: string | null;
  anomaly_flag: string | null;
}

// v3 response — Poketrace is the sole source. No PPT fields, no reconciled block.
export interface PriceCompResponse {
  grading_service: GradingService;
  grade: string;
  headline_price_cents: number | null;   // = poketrace avg
  poketrace: PoketraceBlock | null;       // null when no graded tier data
  sold_listings: SoldListingWire[];       // [] off the Scale plan
  marketplace_url: string | null;         // ebay sold-results deep link
  fetched_at: string;
  cache_hit: boolean;
}
