import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { findOrCreateIdentity } from "@/graded/identity.js";
import { GRADE_TIERS_BY_SERVICE } from "@/graded/watchlist.js";
import type { GradingService, Language } from "@/graded/models.js";
import { throwIfError } from "@/shared/db/supabase.js";
import type { Logger } from "@/shared/logger.js";

const seedSchema = z.object({
  version: z.string(),
  cards: z.array(z.object({
    id: z.number(),
    name: z.string(),
    set: z.string(),
    number: z.string().nullable(),
    year: z.number().nullable(),
    language: z.string(),
    variant: z.string().nullable(),
    grading_companies: z.array(z.string()),
    popularity_rank: z.number(),
  })),
});

export type PopularSlabsSeed = z.infer<typeof seedSchema>;

export interface PopularSlabsSeedResult {
  identitiesUpserted: number;
  watchlistRowsUpserted: number;
  cardsSkipped: number;
}

function toLanguage(raw: string): Language | null {
  const v = raw.trim().toLowerCase();
  if (v === "english") return "en";
  if (v === "japanese") return "jp";
  return null;
}

function isGradingService(s: string): s is GradingService {
  return s === "PSA" || s === "CGC" || s === "BGS" || s === "SGC" || s === "TAG";
}

export async function loadSeedFromFile(path: string): Promise<PopularSlabsSeed> {
  const content = await readFile(path, "utf-8");
  return seedSchema.parse(JSON.parse(content));
}

export function defaultSeedPath(): string {
  return join(dirname(fileURLToPath(import.meta.url)), "popular-slabs.json");
}

export async function runPopularSlabsSeed(
  supabase: SupabaseClient,
  seedPath: string = defaultSeedPath(),
  log?: Logger,
): Promise<PopularSlabsSeedResult> {
  const seed = await loadSeedFromFile(seedPath);
  const total = seed.cards.length;
  log?.info("popular-slabs seed: loaded", { total, seedPath });

  let identitiesUpserted = 0;
  let cardsSkipped = 0;
  const watchlistRows: Array<Record<string, unknown>> = [];

  for (let i = 0; i < seed.cards.length; i += 1) {
    const card = seed.cards[i]!;
    const position = i + 1;
    const language = toLanguage(card.language);
    if (!language) {
      cardsSkipped += 1;
      log?.warn("popular-slabs seed: skipped (unsupported language)", {
        position, total, id: card.id, name: card.name, language: card.language,
      });
      continue;
    }

    log?.info("popular-slabs seed: upserting identity", {
      position, total, id: card.id, name: card.name, set: card.set,
    });
    const identityId = await findOrCreateIdentity(supabase, {
      game: "pokemon",
      language,
      setName: card.set,
      cardName: card.name,
      cardNumber: card.number ?? null,
      variant: card.variant ?? null,
      year: card.year ?? null,
    });
    identitiesUpserted += 1;

    let rowsForCard = 0;
    for (const service of card.grading_companies) {
      if (!isGradingService(service)) continue;
      for (const grade of GRADE_TIERS_BY_SERVICE[service]) {
        watchlistRows.push({
          identity_id: identityId,
          grading_service: service,
          grade,
          source: "seed",
          popularity_rank: card.popularity_rank,
          is_active: true,
          updated_at: new Date().toISOString(),
        });
        rowsForCard += 1;
      }
    }
    log?.debug("popular-slabs seed: queued watchlist rows", {
      position, total, id: card.id, rowsForCard, queuedTotal: watchlistRows.length,
    });
  }

  const CHUNK = 500;
  let watchlistRowsUpserted = 0;
  const totalChunks = Math.ceil(watchlistRows.length / CHUNK);
  for (let i = 0; i < watchlistRows.length; i += CHUNK) {
    const chunk = watchlistRows.slice(i, i + CHUNK);
    const chunkNo = Math.floor(i / CHUNK) + 1;
    log?.info("popular-slabs seed: upserting watchlist chunk", {
      chunk: chunkNo, totalChunks, rows: chunk.length,
    });
    await throwIfError(supabase.from("graded_watchlist").upsert(chunk, {
      onConflict: "identity_id,grading_service,grade",
      ignoreDuplicates: false,
    }));
    watchlistRowsUpserted += chunk.length;
  }

  return { identitiesUpserted, watchlistRowsUpserted, cardsSkipped };
}
