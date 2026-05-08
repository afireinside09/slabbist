// src/raw/ingest.ts
import type { SupabaseClient } from "@supabase/supabase-js";
import { extractPokemonFields } from "@/raw/extractors.js";
import { fetchGroups, fetchProducts, fetchPrices } from "@/raw/sources/tcgcsv.js";
import { mapConcurrent } from "@/shared/concurrency.js";
import { throwIfError } from "@/shared/db/supabase.js";
import type { Logger } from "@/shared/logger.js";

export interface IngestOptions {
  categoryId: number;
  supabase: SupabaseClient;
  userAgent: string;
  concurrency?: number;
  delayMs?: number;
  log?: Logger;
}

export interface IngestResult {
  scrapeRunId: string;
  status: "completed" | "failed";
  groupsDone: number;
  productsUpserted: number;
  pricesUpserted: number;
  errorMessage?: string;
}

const BATCH = 500;

function chunk<T>(arr: readonly T[], n: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}

export async function ingestTcgcsvForCategory(opts: IngestOptions): Promise<IngestResult> {
  const { supabase, categoryId, log } = opts;
  const { userAgent } = opts;
  const concurrency = opts.concurrency ?? 3;
  const delayMs = opts.delayMs ?? 200;
  const categoryName = categoryId === 3 ? "Pokemon" : categoryId === 85 ? "Pokemon Japan" : `cat-${categoryId}`;

  // Ensure the tcg_categories row exists (idempotent upsert of the category).
  await throwIfError(supabase.from("tcg_categories").upsert(
    [{ category_id: categoryId, name: categoryName, modified_on: new Date().toISOString() }],
    { onConflict: "category_id" },
  ));

  // Open a run row.
  const runId = crypto.randomUUID();
  log?.info("category starting", { categoryId, category: categoryName, runId });
  await throwIfError(supabase.from("tcg_scrape_runs").insert({
    id: runId, category_id: categoryId, status: "running",
    started_at: new Date().toISOString(),
  }));

  let groupsDone = 0;
  let productsUpserted = 0;
  let pricesUpserted = 0;

  try {
    const groups = await fetchGroups(categoryId, { userAgent });
    log?.info("groups fetched", { categoryId, count: groups.length });
    await throwIfError(supabase.from("tcg_scrape_runs").update({ groups_total: groups.length }).eq("id", runId));

    await throwIfError(supabase.from("tcg_groups").upsert(
      groups.map((g) => ({
        group_id: g.groupId, category_id: g.categoryId, name: g.name,
        abbreviation: g.abbreviation, is_supplemental: g.isSupplemental,
        published_on: g.publishedOn, modified_on: g.modifiedOn,
      })),
      { onConflict: "group_id" },
    ));

    await mapConcurrent(groups, concurrency, async (group) => {
      try {
        const products = await fetchProducts(categoryId, group.groupId, { userAgent });
        const rows = products.map((p) => {
          const ex = extractPokemonFields(p.extendedData);
          return {
            product_id: p.productId, group_id: p.groupId, category_id: p.categoryId,
            name: p.name, clean_name: p.cleanName, image_url: p.imageUrl, url: p.url,
            modified_on: p.modifiedOn, image_count: p.imageCount,
            is_presale: p.presaleInfo?.isPresale ?? false,
            presale_release_on: p.presaleInfo?.releasedOn ?? null,
            presale_note: p.presaleInfo?.note ?? null,
            card_number: ex.cardNumber, rarity: ex.rarity, card_type: ex.cardType, hp: ex.hp, stage: ex.stage,
            extended_data: p.extendedData,
          };
        });
        for (const batch of chunk(rows, BATCH)) {
          await throwIfError(supabase.from("tcg_products").upsert(batch, { onConflict: "product_id" }));
          productsUpserted += batch.length;
        }

        const prices = await fetchPrices(categoryId, group.groupId, { userAgent });
        const priceRows = prices.map((p) => ({
          product_id: p.productId, sub_type_name: p.subTypeName,
          low_price: p.lowPrice, mid_price: p.midPrice, high_price: p.highPrice,
          market_price: p.marketPrice, direct_low_price: p.directLowPrice,
          updated_at: new Date().toISOString(),
        }));
        const historyRows = prices.map((p) => ({
          scrape_run_id: runId, product_id: p.productId, sub_type_name: p.subTypeName,
          low_price: p.lowPrice, mid_price: p.midPrice, high_price: p.highPrice,
          market_price: p.marketPrice, direct_low_price: p.directLowPrice,
          captured_at: new Date().toISOString(),
        }));
        for (const b of chunk(priceRows, BATCH)) {
          await throwIfError(supabase.from("tcg_prices").upsert(b, { onConflict: "product_id,sub_type_name" }));
          pricesUpserted += b.length;
        }
        for (const b of chunk(historyRows, BATCH)) {
          await throwIfError(supabase.from("tcg_price_history").insert(b));
        }

        groupsDone += 1;
        await throwIfError(supabase.from("tcg_scrape_runs").update({
          groups_done: groupsDone, products_upserted: productsUpserted, prices_upserted: pricesUpserted,
        }).eq("id", runId));
        log?.info("group done", {
          categoryId,
          current: groupsDone,
          total: groups.length,
          group: group.name,
          products: rows.length,
          prices: priceRows.length,
        });
      } catch (e) {
        const msg = String((e as Error).message ?? e);
        log?.warn("group failed", { categoryId, group: group.name, groupId: group.groupId, error: msg });
        // Per-group failure: record via run row but continue.
        await supabase.from("tcg_scrape_runs").update({
          error_message: `group ${group.groupId}: ${msg}`,
        }).eq("id", runId);
      }
    }, { delayMs });

    await throwIfError(supabase.from("tcg_scrape_runs").update({
      status: "completed", finished_at: new Date().toISOString(),
      groups_done: groupsDone, products_upserted: productsUpserted, prices_upserted: pricesUpserted,
    }).eq("id", runId));
    log?.info("category complete", {
      categoryId, category: categoryName, groupsDone, productsUpserted, pricesUpserted,
    });

    return { scrapeRunId: runId, status: "completed", groupsDone, productsUpserted, pricesUpserted };
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    log?.error("category failed", { categoryId, category: categoryName, error: msg });
    await supabase.from("tcg_scrape_runs").update({
      status: "failed", finished_at: new Date().toISOString(), error_message: msg,
    }).eq("id", runId);
    return { scrapeRunId: runId, status: "failed", groupsDone, productsUpserted, pricesUpserted, errorMessage: msg };
  }
}

export async function ingestPokemonAllCategories(opts: Omit<IngestOptions, "categoryId">): Promise<IngestResult[]> {
  const out: IngestResult[] = [];
  for (const id of [3, 85]) out.push(await ingestTcgcsvForCategory({ ...opts, categoryId: id }));
  // Refresh per-set movers, then prune price history to the 90-day
  // window the movers refresh anchors against. Both calls run regardless
  // of each other's outcome (prune is a useful GC even if refresh failed),
  // but any failure here MUST surface to the workflow — a silent green
  // run with stale `movers` is the failure mode we're guarding against.
  // Ceiling matches `ALTER FUNCTION ... SET statement_timeout = '5min'`
  // applied in the 20260508210000 migration; PostgREST otherwise inherits
  // the authenticator role's 8s GUC and these RPCs would be killed
  // server-side as tcg_price_history grows.
  const RPC_TIMEOUT_MS = 300_000;
  const errors: string[] = [];
  const startedAt = new Date();

  const { error: refreshErr } = await opts.supabase
    .rpc("refresh_movers")
    .abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS));
  if (refreshErr) {
    errors.push(`refresh_movers: ${refreshErr.message}`);
    opts.log?.error("refresh_movers failed", { error: refreshErr.message });
  } else {
    // PostgREST returned 200, but the function may have committed nothing
    // (e.g. role/GUC misconfig). Verify by reading back the watermark.
    const { data: vRow, error: vErr } = await opts.supabase
      .from("movers")
      .select("refreshed_at")
      .order("refreshed_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (vErr) {
      errors.push(`refresh_movers verify: ${vErr.message}`);
      opts.log?.error("refresh_movers verify failed", { error: vErr.message });
    } else if (!vRow?.refreshed_at || new Date(vRow.refreshed_at) < startedAt) {
      const observed = vRow?.refreshed_at ?? "(none)";
      errors.push(`refresh_movers verify: refreshed_at=${observed} did not advance past ${startedAt.toISOString()}`);
      opts.log?.error("refresh_movers verify: stale watermark", {
        startedAt: startedAt.toISOString(), observed,
      });
    } else {
      opts.log?.info("movers refreshed", { refreshed_at: vRow.refreshed_at });
    }
  }

  const { data: pruneData, error: pruneErr } = await opts.supabase
    .rpc("prune_tcg_price_history")
    .abortSignal(AbortSignal.timeout(RPC_TIMEOUT_MS));
  if (pruneErr) {
    errors.push(`prune_tcg_price_history: ${pruneErr.message}`);
    opts.log?.error("prune_tcg_price_history failed", { error: pruneErr.message });
  } else {
    opts.log?.info("price history pruned", { deleted: typeof pruneData === "number" ? pruneData : null });
  }

  if (errors.length > 0) {
    throw new Error(`maintenance RPC failures: ${errors.join("; ")}`);
  }
  return out;
}
