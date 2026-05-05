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
  pricecharting_product_id: string | null;
  pricecharting_url: string | null;
}

export interface PriceCompRequest {
  graded_card_identity_id: string;
  grading_service: GradingService;
  grade: string;
}

export interface PriceCompResponse {
  headline_price_cents: number | null;
  grading_service: GradingService;
  grade: string;

  loose_price_cents:     number | null;
  grade_7_price_cents:   number | null;
  grade_8_price_cents:   number | null;
  grade_9_price_cents:   number | null;
  grade_9_5_price_cents: number | null;
  psa_10_price_cents:    number | null;
  bgs_10_price_cents:    number | null;
  cgc_10_price_cents:    number | null;
  sgc_10_price_cents:    number | null;

  pricecharting_product_id: string;
  pricecharting_url: string;

  fetched_at: string;
  cache_hit: boolean;
  is_stale_fallback: boolean;
}

export type CacheState = "hit" | "miss" | "stale";
