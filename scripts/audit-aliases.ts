#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env

/**
 * audit-aliases.ts
 *
 * Purpose:
 *   Validates docs/data/psa-tcggroup-aliases.csv against the live tcg_groups
 *   table in Supabase. Catches stale group IDs, name drift, abbreviation drift,
 *   year drift, low-confidence high-overlap oddities, and duplicate target groups.
 *
 * Usage:
 *   ./scripts/audit-aliases.ts
 *
 * Expected output (clean run):
 *   Loaded 87 alias rows
 *   Fetched 1823 tcg_groups rows
 *   Checking aliases ...
 *   ✓ All clean — 0 errors, 0 warnings
 *
 * Expected output (issues found):
 *   ERRORS:
 *     [row 14] "Topps Pikachu" — unknown_group_id: 99999 not in tcg_groups
 *   WARNINGS:
 *     [row  3] "Base Set" — name_drift: CSV has "Base Set", DB has "Pokémon Base Set"
 *   Summary: 1 error(s), 1 warning(s)
 *
 * Exit code: 0 if no errors, 1 if any errors.
 */

import { parse as parseCsv } from "https://deno.land/std@0.224.0/csv/mod.ts";

// ── Config ────────────────────────────────────────────────────────────────────

const SUPABASE_URL = "https://ksildxueezkvrwryybln.supabase.co";
const PUBLISHABLE_KEY = "sb_publishable_UJGm3z2syyn6eqRcGgX_DQ_3gU_dhql";
const ALIAS_CSV_PATH = "docs/data/psa-tcggroup-aliases.csv";

// ANSI colours — degrade gracefully if not a TTY
const isTTY = Deno.stdout.isTerminal?.() ?? false;
const RED = isTTY ? "\x1b[31m" : "";
const YELLOW = isTTY ? "\x1b[33m" : "";
const GREEN = isTTY ? "\x1b[32m" : "";
const RESET = isTTY ? "\x1b[0m" : "";
const BOLD = isTTY ? "\x1b[1m" : "";

// ── Types ─────────────────────────────────────────────────────────────────────

interface AliasRow {
  rowIndex: number; // 1-based (skipping header)
  psa_set_name: string;
  psa_years: string;
  psa_count: string;
  tcg_group_id: string;
  tcg_group_name: string;
  tcg_abbreviation: string;
  tcg_published_year: string;
  confidence: string;
  alt_2_id: string;
  alt_2_name: string;
  alt_2_score: string;
  alt_3_id: string;
  alt_3_name: string;
  alt_3_score: string;
  notes: string;
}

interface TcgGroup {
  group_id: number;
  name: string;
  abbreviation: string | null;
  published_on: string | null;
}

interface Issue {
  rowIndex: number;
  psaName: string;
  code: string;
  detail: string;
}

// ── Fetch tcg_groups (paginated) ─────────────────────────────────────────────

async function fetchTcgGroups(): Promise<TcgGroup[]> {
  const pageSize = 1000;
  const results: TcgGroup[] = [];
  let offset = 0;

  while (true) {
    const url =
      `${SUPABASE_URL}/rest/v1/tcg_groups` +
      `?select=group_id,name,abbreviation,published_on` +
      `&limit=${pageSize}&offset=${offset}`;

    const resp = await fetch(url, {
      headers: {
        apikey: PUBLISHABLE_KEY,
        Authorization: `Bearer ${PUBLISHABLE_KEY}`,
        "Range-Unit": "items",
        Range: `${offset}-${offset + pageSize - 1}`,
      },
    });

    if (!resp.ok) {
      throw new Error(
        `Failed to fetch tcg_groups (offset=${offset}): ${resp.status} ${await resp.text()}`
      );
    }

    const page: TcgGroup[] = await resp.json();
    results.push(...page);

    if (page.length < pageSize) break; // last page
    offset += pageSize;
  }

  return results;
}

// ── Token-overlap score ───────────────────────────────────────────────────────

function tokenOverlap(a: string, b: string): number {
  const tokenise = (s: string) =>
    new Set(
      s
        .toLowerCase()
        .replace(/[^a-z0-9 ]/g, " ")
        .split(/\s+/)
        .filter(Boolean)
    );
  const ta = tokenise(a);
  const tb = tokenise(b);
  if (ta.size === 0 || tb.size === 0) return 0;
  let intersection = 0;
  for (const t of ta) {
    if (tb.has(t)) intersection++;
  }
  return intersection / Math.min(ta.size, tb.size);
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  // 1. Load alias CSV
  let csvText: string;
  try {
    csvText = await Deno.readTextFile(ALIAS_CSV_PATH);
  } catch {
    console.error(`Cannot read ${ALIAS_CSV_PATH}. Aborting.`);
    Deno.exit(1);
  }

  const parsed = parseCsv(csvText, { skipFirstRow: true, strip: true });

  const EXPECTED_HEADERS = [
    "psa_set_name",
    "psa_years",
    "psa_count",
    "tcg_group_id",
    "tcg_group_name",
    "tcg_abbreviation",
    "tcg_published_year",
    "confidence",
    "alt_2_id",
    "alt_2_name",
    "alt_2_score",
    "alt_3_id",
    "alt_3_name",
    "alt_3_score",
    "notes",
  ];

  // Validate headers
  const parsedFull = parseCsv(csvText, { skipFirstRow: false, strip: true });
  const actualHeaders = parsedFull[0] as string[];
  for (let i = 0; i < EXPECTED_HEADERS.length; i++) {
    if (actualHeaders[i] !== EXPECTED_HEADERS[i]) {
      console.error(
        `Header mismatch at col ${i + 1}: expected "${EXPECTED_HEADERS[i]}", got "${actualHeaders[i]}". Aborting.`
      );
      Deno.exit(1);
    }
  }

  const aliasRows: AliasRow[] = (parsed as Record<string, string>[]).map(
    (r, i) => ({
      rowIndex: i + 2, // 1-based, row 1 = header
      psa_set_name: r["psa_set_name"] ?? "",
      psa_years: r["psa_years"] ?? "",
      psa_count: r["psa_count"] ?? "",
      tcg_group_id: r["tcg_group_id"] ?? "",
      tcg_group_name: r["tcg_group_name"] ?? "",
      tcg_abbreviation: r["tcg_abbreviation"] ?? "",
      tcg_published_year: r["tcg_published_year"] ?? "",
      confidence: r["confidence"] ?? "",
      alt_2_id: r["alt_2_id"] ?? "",
      alt_2_name: r["alt_2_name"] ?? "",
      alt_2_score: r["alt_2_score"] ?? "",
      alt_3_id: r["alt_3_id"] ?? "",
      alt_3_name: r["alt_3_name"] ?? "",
      alt_3_score: r["alt_3_score"] ?? "",
      notes: r["notes"] ?? "",
    })
  );

  console.log(`Loaded ${aliasRows.length} alias rows`);

  // 2. Fetch tcg_groups
  console.log("Fetching tcg_groups from remote...");
  const tcgGroups = await fetchTcgGroups();
  console.log(`Fetched ${tcgGroups.length} tcg_groups rows`);

  // Build lookup maps
  const groupById = new Map<number, TcgGroup>();
  for (const g of tcgGroups) {
    groupById.set(g.group_id, g);
  }

  // 3. Audit each alias row
  console.log("Checking aliases...");
  const errors: Issue[] = [];
  const warnings: Issue[] = [];

  // Track duplicates: group_id → list of psa_set_name
  const groupIdToAliases = new Map<number, string[]>();

  for (const row of aliasRows) {
    if (!row.tcg_group_id) continue; // empty mapping — skip structural checks

    const groupId = parseInt(row.tcg_group_id, 10);
    if (isNaN(groupId)) {
      errors.push({
        rowIndex: row.rowIndex,
        psaName: row.psa_set_name,
        code: "invalid_group_id",
        detail: `"${row.tcg_group_id}" is not a valid integer`,
      });
      continue;
    }

    // Track duplicates
    const existing = groupIdToAliases.get(groupId) ?? [];
    existing.push(row.psa_set_name);
    groupIdToAliases.set(groupId, existing);

    const group = groupById.get(groupId);

    // 3a. unknown_group_id
    if (!group) {
      errors.push({
        rowIndex: row.rowIndex,
        psaName: row.psa_set_name,
        code: "unknown_group_id",
        detail: `group_id ${groupId} not found in tcg_groups`,
      });
      continue; // can't check further without the group
    }

    // 3b. name_drift
    if (
      row.tcg_group_name &&
      group.name &&
      row.tcg_group_name !== group.name
    ) {
      warnings.push({
        rowIndex: row.rowIndex,
        psaName: row.psa_set_name,
        code: "name_drift",
        detail: `CSV has "${row.tcg_group_name}", DB has "${group.name}"`,
      });
    }

    // 3c. abbreviation_drift
    if (
      row.tcg_abbreviation &&
      group.abbreviation !== null &&
      group.abbreviation !== undefined &&
      row.tcg_abbreviation !== group.abbreviation
    ) {
      warnings.push({
        rowIndex: row.rowIndex,
        psaName: row.psa_set_name,
        code: "abbreviation_drift",
        detail: `CSV has "${row.tcg_abbreviation}", DB has "${group.abbreviation}"`,
      });
    }

    // 3d. year_drift
    if (row.tcg_published_year && group.published_on) {
      const csvYear = parseInt(row.tcg_published_year, 10);
      const dbYear = new Date(group.published_on).getFullYear();
      if (!isNaN(csvYear) && csvYear !== dbYear) {
        warnings.push({
          rowIndex: row.rowIndex,
          psaName: row.psa_set_name,
          code: "year_drift",
          detail: `CSV has ${csvYear}, DB published_on year is ${dbYear}`,
        });
      }
    }

    // 3e. low_overlap_high_confidence
    if (row.confidence === "high" && row.tcg_group_name) {
      const overlap = tokenOverlap(row.psa_set_name, row.tcg_group_name);
      if (overlap < 0.3) {
        warnings.push({
          rowIndex: row.rowIndex,
          psaName: row.psa_set_name,
          code: "low_overlap_high_confidence",
          detail: `confidence=high but token overlap is ${overlap.toFixed(2)} (< 0.3) between "${row.psa_set_name}" and "${row.tcg_group_name}"`,
        });
      }
    }
  }

  // 3f. duplicate_target_group
  for (const [groupId, names] of groupIdToAliases.entries()) {
    if (names.length > 1) {
      // Find one representative row index for each dup
      const rows = aliasRows.filter(
        (r) => r.tcg_group_id === String(groupId)
      );
      const firstRow = rows[0];
      warnings.push({
        rowIndex: firstRow?.rowIndex ?? 0,
        psaName: names.join(" / "),
        code: "duplicate_target_group",
        detail: `group_id ${groupId} is referenced by ${names.length} PSA entries: ${names.map((n) => `"${n}"`).join(", ")}`,
      });
    }
  }

  // 4. Report
  if (errors.length > 0) {
    console.log(`\n${BOLD}${RED}ERRORS:${RESET}`);
    for (const e of errors) {
      console.log(
        `  ${RED}[row ${String(e.rowIndex).padStart(3)}]${RESET} "${e.psaName}" — ${BOLD}${e.code}${RESET}: ${e.detail}`
      );
    }
  }

  if (warnings.length > 0) {
    console.log(`\n${BOLD}${YELLOW}WARNINGS:${RESET}`);
    for (const w of warnings) {
      console.log(
        `  ${YELLOW}[row ${String(w.rowIndex).padStart(3)}]${RESET} "${w.psaName}" — ${BOLD}${w.code}${RESET}: ${w.detail}`
      );
    }
  }

  if (errors.length === 0 && warnings.length === 0) {
    console.log(`\n${GREEN}✓ All clean — 0 errors, 0 warnings${RESET}`);
  } else {
    console.log(
      `\nSummary: ${errors.length} error(s), ${warnings.length} warning(s)`
    );
  }

  Deno.exit(errors.length > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error("Fatal:", err);
  Deno.exit(1);
});
