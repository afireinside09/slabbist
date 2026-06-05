#!/usr/bin/env -S deno run --allow-read --allow-env --allow-net

/**
 * seed-cameos.ts
 *
 * Purpose:
 *   Parse cameo-data/*.csv and rebuild public.cameo_subjects + public.cameo_cards.
 *   Idempotent: deletes all subjects (cards cascade) then bulk-inserts fresh rows.
 *
 * Usage (needs the secret key — bypasses RLS to write; exported by the repo's
 * .envrc as SUPABASE_SECRET_KEY, an sb_secret_… service-role-equivalent key):
 *   ./scripts/seed-cameos.ts        # inside a direnv-allowed shell
 *
 * Expected output:
 *   Parsing 10 sheets ...
 *   Parsed 3214 subjects, 3811 cards
 *   Cleared existing cameo data
 *   Inserted 3214 subjects, 3811 cards
 *   ✓ Done
 */

import { parse as parseCsv } from "https://deno.land/std@0.224.0/csv/mod.ts";
import { parseCameoSheet, type ParsedSubject } from "./cameo_parse.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "https://ksildxueezkvrwryybln.supabase.co";
const SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY");
if (!SECRET_KEY) {
  console.error("SUPABASE_SECRET_KEY is required (writes bypass RLS). Run inside a direnv-allowed shell.");
  Deno.exit(1);
}

const DATA_DIR = "cameo-data";
const SHEETS: { file: string; generation: string; kind: "pokemon" | "trainer" }[] = [
  ...Array.from({ length: 9 }, (_, i) => ({
    file: `RotomAmiti's Cameo Pokémon Card Database - Gen ${i + 1}.csv`,
    generation: `Gen ${i + 1}`,
    kind: "pokemon" as const,
  })),
  {
    file: "RotomAmiti's Cameo Pokémon Card Database - Trainers.csv",
    generation: "Trainers",
    kind: "trainer" as const,
  },
];

async function loadSheet(file: string): Promise<string[][]> {
  const text = await Deno.readTextFile(`${DATA_DIR}/${file}`);
  const rows = parseCsv(text) as string[][]; // array mode (no header inference)
  return rows.slice(1); // drop the header row
}

const headers = {
  apikey: SECRET_KEY!,
  Authorization: `Bearer ${SECRET_KEY}`,
  "Content-Type": "application/json",
};

async function rest(path: string, init: RequestInit) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...init, headers: { ...headers, ...(init.headers ?? {}) } });
  if (!res.ok) {
    throw new Error(`${init.method} ${path} -> ${res.status} ${await res.text()}`);
  }
  return res;
}

async function chunkedInsert(table: string, rows: unknown[]) {
  const SIZE = 500;
  for (let i = 0; i < rows.length; i += SIZE) {
    await rest(table, {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify(rows.slice(i, i + SIZE)),
    });
  }
}

// ── Parse ───────────────────────────────────────────────────────────────────
console.log(`Parsing ${SHEETS.length} sheets ...`);
const allSubjects: ParsedSubject[] = [];
for (const sheet of SHEETS) {
  const rows = await loadSheet(sheet.file);
  allSubjects.push(...parseCameoSheet(rows, { generation: sheet.generation, kind: sheet.kind }));
}
const totalCards = allSubjects.reduce((n, s) => n + s.cards.length, 0);
console.log(`Parsed ${allSubjects.length} subjects, ${totalCards} cards`);

// ── Build insert payloads (client-generated UUIDs link cards → subjects) ──────
const subjectRows = allSubjects.map((s) => ({
  id: crypto.randomUUID(),
  kind: s.kind,
  ndex: s.ndex,
  region: s.region,
  name: s.name,
  card_count: s.cards.length,
}));
const cardRows = allSubjects.flatMap((s, i) =>
  s.cards.map((c) => ({
    subject_id: subjectRows[i].id,
    card_name: c.cardName,
    set_name: c.setName,
    card_number: c.cardNumber || null,
    notes: c.notes || null,
    generation: c.generation,
  }))
);

// ── Rebuild ───────────────────────────────────────────────────────────────────
// Delete every subject (cards cascade via FK). PostgREST requires a filter on
// DELETE; `kind` is non-null on every row, so this matches all.
await rest("cameo_subjects?kind=in.(pokemon,trainer)", { method: "DELETE", headers: { Prefer: "return=minimal" } });
console.log("Cleared existing cameo data");

await chunkedInsert("cameo_subjects", subjectRows);
await chunkedInsert("cameo_cards", cardRows);
console.log(`Inserted ${subjectRows.length} subjects, ${cardRows.length} cards`);
console.log("✓ Done");
