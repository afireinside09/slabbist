// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
// supabase/functions/price-comp/ebay/cascade.ts
import type { GradedCardIdentity, GradingService, SoldListingRaw } from "../types.ts";
import { buildCascadeQueries, type CascadeQuery } from "./query-builder.ts";
import { parseGradedTitle } from "../lib/graded-title-parse.ts";

export interface BucketFetchResult {
  status: number;
  listings: SoldListingRaw[];
}

export interface RunCascadeOpts {
  minResults: number;
  fetchBucket: (q: CascadeQuery) => Promise<BucketFetchResult>;
}

export interface CascadeResult {
  listings: SoldListingRaw[];
  sampleWindowDays: 90 | 365;
  bucketHit: 1 | 2 | 3 | 4 | null;
}

function validateListings(
  raw: SoldListingRaw[],
  svc: GradingService,
  grade: string,
): SoldListingRaw[] {
  return raw.filter(l => {
    const parsed = parseGradedTitle(l.title);
    return parsed?.gradingService === svc && parsed.grade === grade;
  });
}

export async function runCascade(
  identity: GradedCardIdentity,
  svc: GradingService,
  grade: string,
  opts: RunCascadeOpts,
): Promise<CascadeResult> {
  const queries = buildCascadeQueries(identity, svc, grade);
  let best: { listings: SoldListingRaw[]; window: 90 | 365; bucket: 1 | 2 | 3 | 4 } | null = null;
  for (let i = 0; i < queries.length; i++) {
    const q = queries[i]!;
    const result = await opts.fetchBucket(q);
    const valid = validateListings(result.listings, svc, grade);
    if (valid.length === 0) continue;
    const sorted = valid.slice().sort((a, b) => b.sold_at.localeCompare(a.sold_at)).slice(0, 10);
    const bucketNum = (i + 1) as 1 | 2 | 3 | 4;
    const windowDays = q.windowDays;
    if (sorted.length >= opts.minResults) {
      return { listings: sorted, sampleWindowDays: windowDays, bucketHit: bucketNum };
    }
    if (!best || sorted.length > best.listings.length) {
      best = { listings: sorted, window: windowDays, bucket: bucketNum };
    }
  }
  if (best) {
    return { listings: best.listings, sampleWindowDays: best.window, bucketHit: best.bucket };
  }
  return { listings: [], sampleWindowDays: 90, bucketHit: null };
}
