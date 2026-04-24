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
}

export interface PriceCompRequest {
  graded_card_identity_id: string;
  grading_service: GradingService;
  grade: string;
}

export type OutlierReason = "price_high" | "price_low" | null;

export interface SoldListing {
  sold_price_cents: number;
  sold_at: string;           // ISO 8601
  title: string;
  url: string;
  source: "ebay";
  is_outlier: boolean;
  outlier_reason: OutlierReason;
}

export interface SoldListingRaw {
  sold_price_cents: number;
  sold_at: string;
  title: string;
  url: string;
  source_listing_id: string;
}

export interface PriceCompResponse {
  blended_price_cents: number;
  mean_price_cents: number;
  trimmed_mean_price_cents: number;
  median_price_cents: number;
  low_price_cents: number;
  high_price_cents: number;
  confidence: number;
  sample_count: number;
  sample_window_days: 90 | 365;
  velocity_7d: number;
  velocity_30d: number;
  velocity_90d: number;
  sold_listings: SoldListing[];
  fetched_at: string;
  cache_hit: boolean;
  is_stale_fallback: boolean;
}

export type CacheState = "hit" | "miss" | "stale";
