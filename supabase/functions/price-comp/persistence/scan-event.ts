// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.
// supabase/functions/price-comp/persistence/scan-event.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import type { CacheState, GradingService } from "../types.ts";

export interface ScanEventInput {
  identityId: string;
  gradingService: GradingService;
  grade: string;
  storeId: string | null;
  cacheState: CacheState;
}

/**
 * Best-effort write to slab_scan_events. Never throws — the user gets their
 * comp even if the signal drop fails.
 */
export async function recordScanEvent(
  supabase: SupabaseClient,
  input: ScanEventInput,
): Promise<void> {
  try {
    const { error } = await supabase.from("slab_scan_events").insert({
      identity_id: input.identityId,
      grading_service: input.gradingService,
      grade: input.grade,
      store_id: input.storeId,
      cache_state: input.cacheState,
    });
    if (error) {
      console.warn("scan-event.write.failed", { message: error.message });
    }
  } catch (e) {
    console.warn("scan-event.write.threw", { message: (e as Error).message });
  }
}
