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
 * Expected output (counts verified against the current cameo-data/*.csv):
 *   Parsing 10 sheets ...
 *   Parsed 1013 subjects, 3945 cards
 *   Cleared existing cameo data
 *   Inserted 1013 subjects, 3945 cards
 *   ✓ Done
 */

import { parse as parseCsv } from "https://deno.land/std@0.224.0/csv/mod.ts";
import { parseCameoSheet, type ParsedSubject } from "./cameo_parse.ts";

// std@0.224.0 signature: generate(namespace: string, data: Uint8Array): Promise<string>.
// (The object form `{ value, namespace }` is the newer JSR @std/uuid API — do NOT
// use it here; this script pins deno.land/std@0.224.0.)
import { generate as uuidv5 } from "https://deno.land/std@0.224.0/uuid/v5.ts";

// Fixed namespace so the same natural key always yields the same UUID across
// re-seeds. This is what makes the upsert (and thus mapping preservation) work.
const CAMEO_NS = "7c3a1f64-2b9e-4d8a-9c01-5e6f8a2b3c4d";
const enc = new TextEncoder();

const subjectId = (kind: string, name: string) =>
  uuidv5(CAMEO_NS, enc.encode(`subject|${kind}|${name}`));

const cardKey = (
  kind: string, name: string,
  cardName: string, setName: string, cardNumber: string, generation: string, notes: string,
) => `card|${kind}|${name}|${cardName}|${setName}|${cardNumber}|${generation}|${notes}`;

const cardId = (key: string) => uuidv5(CAMEO_NS, enc.encode(key));

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

async function chunkedUpsert(table: string, rows: unknown[]) {
  const SIZE = 500;
  for (let i = 0; i < rows.length; i += SIZE) {
    await rest(table, {
      method: "POST",
      // merge-duplicates → INSERT ... ON CONFLICT (pk) DO UPDATE SET <payload cols>.
      // Columns absent from the payload (tcgplayer_product_id) are left as-is.
      headers: { Prefer: "return=minimal,resolution=merge-duplicates" },
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

// ── Build upsert payloads (deterministic UUIDs link cards → subjects) ─────────
const subjectRows = await Promise.all(allSubjects.map(async (s) => ({
  id: await subjectId(s.kind, s.name),
  kind: s.kind,
  ndex: s.ndex,
  region: s.region,
  name: s.name,
  card_count: s.cards.length,
})));

const cardRowsNested = await Promise.all(allSubjects.map(async (s, i) => {
  const sid = subjectRows[i].id;
  return Promise.all(s.cards.map(async (c) => {
    const key = cardKey(s.kind, s.name, c.cardName, c.setName, c.cardNumber || "", c.generation, c.notes || "");
    return {
      id: await cardId(key),
      subject_id: sid,
      card_name: c.cardName,
      set_name: c.setName,
      card_number: c.cardNumber || null,
      notes: c.notes || null,
      generation: c.generation,
      // NOTE: tcgplayer_product_id intentionally omitted — upsert leaves the
      // user's manual mapping untouched.
    };
  }));
}));
const cardRows = cardRowsNested.flat();

// Fail loud if the natural key collides (would silently merge two cards).
const seen = new Set<string>();
const dupes = cardRows.filter((r) => seen.size === seen.add(r.id).size);
if (dupes.length > 0) {
  console.error(`✗ ${dupes.length} cards share a deterministic id (natural-key collision).`);
  console.error("  Add a discriminator to cardKey() before re-running.");
  Deno.exit(1);
}

// ── Upsert ───────────────────────────────────────────────────────────────────
// Steady state: upsert by deterministic id. Content columns refresh; the
// tcgplayer_product_id mapping is preserved (not in the payload).
//
// One-time transition: existing rows were seeded with RANDOM ids, so the first
// deterministic run would duplicate them. Run once with CAMEO_REBUILD=1 to clear
// the old rows first (safe — tcgplayer_product_id is entirely NULL until then).
if (Deno.env.get("CAMEO_REBUILD") === "1") {
  await rest("cameo_subjects?kind=in.(pokemon,trainer)", { method: "DELETE", headers: { Prefer: "return=minimal" } });
  console.log("CAMEO_REBUILD=1 → cleared existing cameo data");
}

await chunkedUpsert("cameo_subjects", subjectRows);
await chunkedUpsert("cameo_cards", cardRows);
console.log(`Upserted ${subjectRows.length} subjects, ${cardRows.length} cards`);
console.log("✓ Done");
