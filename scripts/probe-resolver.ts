#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env

/**
 * probe-resolver.ts
 *
 * Purpose:
 *   Calls /price-comp against every identity in remote graded_card_identities.
 *   Useful for checking resolver hit-rate after alias CSV changes, parser tweaks,
 *   or fresh deploys.
 *
 * Usage:
 *   # Run a full probe (one PPT credit per cold-path identity, free for cached)
 *   ./scripts/probe-resolver.ts
 *
 *   # Output: docs/data/resolver-probe-2026-05-07.csv + console summary
 *
 * Expected output (console):
 *   Fetched 47 identities
 *   Probing ... (1/47) Base Set Charizard ...
 *   ...
 *   ---
 *   Total: 47  OK: 44  no_data: 1  not_resolved: 2
 *   Hit rate: 93.6 %  Cache hits: 38/47 (80.9 %)
 *   Written: docs/data/resolver-probe-2026-05-07.csv
 *
 * Rate limit: PPT allows 60 req/min. Script sleeps 1.2s between calls.
 * Token: read from ~/.slabbist/ppt-token (never echoed to stdout/stderr/CSV).
 */

import { join } from "https://deno.land/std@0.224.0/path/mod.ts";
import { ensureDir } from "https://deno.land/std@0.224.0/fs/mod.ts";

// ── Config ────────────────────────────────────────────────────────────────────

const SUPABASE_URL = "https://ksildxueezkvrwryybln.supabase.co";
const PUBLISHABLE_KEY = "sb_publishable_UJGm3z2syyn6eqRcGgX_DQ_3gU_dhql";
const TOKEN_PATH = `${Deno.env.get("HOME")}/.slabbist/ppt-token`;
const RATE_DELAY_MS = 1200; // 1.2s between calls → ~50 req/min, safely under 60

// ── Types ─────────────────────────────────────────────────────────────────────

interface Identity {
  id: string;
  card_name: string;
  card_number: string | null;
  set_name: string;
  year: number | null;
  ppt_tcgplayer_id: string | null;
}

interface ProbeRow {
  identity_id: string;
  set_name: string;
  card_name: string;
  card_number: string;
  year: string;
  had_cached_id: string;
  status: string;
  tcg_player_id: string;
  headline_dollars: string;
  cache_hit: string;
  is_stale_fallback: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function toCsvLine(row: ProbeRow): string {
  const fields: (keyof ProbeRow)[] = [
    "identity_id",
    "set_name",
    "card_name",
    "card_number",
    "year",
    "had_cached_id",
    "status",
    "tcg_player_id",
    "headline_dollars",
    "cache_hit",
    "is_stale_fallback",
  ];
  return fields
    .map((f) => {
      const v = row[f];
      if (v.includes(",") || v.includes('"') || v.includes("\n")) {
        return `"${v.replace(/"/g, '""')}"`;
      }
      return v;
    })
    .join(",");
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function dateSuffix(): string {
  return new Date().toISOString().slice(0, 10);
}

// ── Fetch all identities ──────────────────────────────────────────────────────

async function fetchIdentities(): Promise<Identity[]> {
  const url =
    `${SUPABASE_URL}/rest/v1/graded_card_identities` +
    `?select=id,card_name,card_number,set_name,year,ppt_tcgplayer_id&limit=500`;

  const resp = await fetch(url, {
    headers: {
      apikey: PUBLISHABLE_KEY,
      Authorization: `Bearer ${PUBLISHABLE_KEY}`,
    },
  });

  if (!resp.ok) {
    throw new Error(
      `Failed to fetch identities: ${resp.status} ${await resp.text()}`
    );
  }

  return resp.json() as Promise<Identity[]>;
}

// ── Probe one identity ────────────────────────────────────────────────────────

interface ProbeResult {
  status: string;
  tcgPlayerId: string;
  headlineCents: number | null;
  cacheHit: boolean | null;
  isStaleFallback: boolean | null;
}

async function probeIdentity(
  identity: Identity,
  pptToken: string
): Promise<ProbeResult> {
  const url = `${SUPABASE_URL}/functions/v1/price-comp`;

  let resp: Response;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: PUBLISHABLE_KEY,
        Authorization: `Bearer ${PUBLISHABLE_KEY}`,
        // PPT token forwarded in the function invocation — function reads it
        // from its own env, but some setups accept it as a header
        "x-ppt-token": pptToken,
      },
      body: JSON.stringify({
        graded_card_identity_id: identity.id,
        grading_service: "PSA",
        grade: "10",
      }),
    });
  } catch (err) {
    return {
      status: "network_error",
      tcgPlayerId: "",
      headlineCents: null,
      cacheHit: null,
      isStaleFallback: null,
    };
  }

  if (resp.ok) {
    let body: Record<string, unknown>;
    try {
      body = await resp.json();
    } catch {
      return {
        status: "decode_error",
        tcgPlayerId: "",
        headlineCents: null,
        cacheHit: null,
        isStaleFallback: null,
      };
    }

    return {
      status: "ok",
      tcgPlayerId: String(body.ppt_tcgplayer_id ?? body.tcgplayer_id ?? ""),
      headlineCents:
        typeof body.headline_price_cents === "number"
          ? body.headline_price_cents
          : null,
      cacheHit: typeof body.cache_hit === "boolean" ? body.cache_hit : null,
      isStaleFallback:
        typeof body.is_stale_fallback === "boolean"
          ? body.is_stale_fallback
          : null,
    };
  }

  // Error path — parse error code from body
  let errorCode = `http_${resp.status}`;
  try {
    const body = await resp.json();
    if (body?.error) {
      // Normalise to snake_case lowercase
      errorCode = String(body.error).toLowerCase().replace(/[^a-z0-9]+/g, "_");
    }
  } catch {
    // leave as http_<n>
  }

  return {
    status: errorCode,
    tcgPlayerId: "",
    headlineCents: null,
    cacheHit: null,
    isStaleFallback: null,
  };
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  // Read token — never echo
  let pptToken = "";
  try {
    pptToken = (await Deno.readTextFile(TOKEN_PATH)).trim();
  } catch {
    console.error(`Cannot read token from ${TOKEN_PATH}. Aborting.`);
    Deno.exit(1);
  }
  if (!pptToken) {
    console.error("Token file is empty. Aborting.");
    Deno.exit(1);
  }

  console.log("Fetching identities from remote...");
  const identities = await fetchIdentities();
  console.log(`Fetched ${identities.length} identities`);

  const rows: ProbeRow[] = [];
  const statusCounts: Record<string, number> = {};
  let cacheHitCount = 0;
  let okCount = 0;

  for (let i = 0; i < identities.length; i++) {
    const identity = identities[i];
    const label = `${identity.set_name} / ${identity.card_name}`;
    const progress = `(${i + 1}/${identities.length})`;
    Deno.stdout.writeSync(
      new TextEncoder().encode(`\rProbing ${progress} ${label} ...          `)
    );

    const result = await probeIdentity(identity, pptToken);

    statusCounts[result.status] = (statusCounts[result.status] ?? 0) + 1;
    if (result.status === "ok") okCount++;
    if (result.cacheHit === true) cacheHitCount++;

    const headlineDollars =
      result.headlineCents !== null
        ? (result.headlineCents / 100).toFixed(2)
        : "";

    rows.push({
      identity_id: identity.id,
      set_name: identity.set_name,
      card_name: identity.card_name,
      card_number: identity.card_number ?? "",
      year: identity.year !== null ? String(identity.year) : "",
      had_cached_id: identity.ppt_tcgplayer_id ? "true" : "false",
      status: result.status,
      tcg_player_id: result.tcgPlayerId,
      headline_dollars: headlineDollars,
      cache_hit: result.cacheHit !== null ? String(result.cacheHit) : "",
      is_stale_fallback:
        result.isStaleFallback !== null ? String(result.isStaleFallback) : "",
    });

    // Rate limit — sleep between calls (except after last one)
    if (i < identities.length - 1) {
      await sleep(RATE_DELAY_MS);
    }
  }

  // Clear progress line
  Deno.stdout.write(new TextEncoder().encode("\n"));

  // Write CSV
  const csvHeader =
    "identity_id,set_name,card_name,card_number,year,had_cached_id,status,tcg_player_id,headline_dollars,cache_hit,is_stale_fallback";
  const csvLines = [csvHeader, ...rows.map(toCsvLine)].join("\n") + "\n";

  const outDir = "docs/data";
  await ensureDir(outDir);
  const outPath = join(outDir, `resolver-probe-${dateSuffix()}.csv`);
  await Deno.writeTextFile(outPath, csvLines);

  // Summary
  const total = identities.length;
  const hitRatePct =
    total > 0 ? ((okCount / total) * 100).toFixed(1) : "0.0";
  const cacheRatePct =
    total > 0 ? ((cacheHitCount / total) * 100).toFixed(1) : "0.0";

  console.log("\n---");
  console.log(`Total: ${total}  OK: ${okCount}`);

  const nonOk = Object.entries(statusCounts)
    .filter(([k]) => k !== "ok")
    .sort((a, b) => b[1] - a[1]);
  if (nonOk.length > 0) {
    const failSummary = nonOk.map(([k, v]) => `${k}: ${v}`).join("  ");
    console.log(`Failures: ${failSummary}`);
  }

  console.log(
    `Hit rate: ${hitRatePct}%  Cache hits: ${cacheHitCount}/${total} (${cacheRatePct}%)`
  );
  console.log(`Written: ${outPath}`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  Deno.exit(1);
});
