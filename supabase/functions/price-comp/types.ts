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
  ppt_tcgplayer_id: string | null;
  ppt_url: string | null;
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

export interface PriceCompResponse {
  headline_price_cents: number | null;
  grading_service: GradingService;
  grade: string;

  loose_price_cents:    number | null;
  psa_7_price_cents:    number | null;
  psa_8_price_cents:    number | null;
  psa_9_price_cents:    number | null;
  psa_9_5_price_cents:  number | null;
  psa_10_price_cents:   number | null;
  bgs_10_price_cents:   number | null;
  cgc_10_price_cents:   number | null;
  sgc_10_price_cents:   number | null;

  price_history: PriceHistoryWirePoint[];

  ppt_tcgplayer_id: string;
  ppt_url: string;

  fetched_at: string;
  cache_hit: boolean;
  is_stale_fallback: boolean;
}

export type CacheState = "hit" | "miss" | "stale";
