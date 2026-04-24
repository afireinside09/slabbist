// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.

// supabase/functions/price-comp/stats/outliers.ts
import { mean, median } from "./aggregates.ts";

const MAD_SCALE = 1.4826;
const MAD_THRESHOLD = 3;

export function detectOutliers(prices: number[]): boolean[] {
  if (prices.length < 2) return prices.map(() => false);
  const med = median(prices);
  const deviations = prices.map(p => Math.abs(p - med));
  const mad = median(deviations);
  if (mad === 0) return prices.map(() => false);
  const cutoff = MAD_THRESHOLD * MAD_SCALE * mad;
  return prices.map(p => Math.abs(p - med) > cutoff);
}

export function trimmedMean(prices: number[], outlierFlags: boolean[]): number {
  const kept = prices.filter((_, i) => !outlierFlags[i]);
  if (kept.length === 0) return mean(prices);
  return mean(kept);
}
