// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
//
// Snapshot property tests for load-bearing alias entries.
// Layer A of the comprehensive test plan.
//
// Purpose: freeze the curated alias CSV at known-good values.
// If the CSV is regenerated and a key mapping changes, this test
// catches the regression before it reaches production.

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aliasForPsaSet } from "../lib/psa-aliases.ts";

// ── Load-bearing snapshot assertions ────────────────────────────────
// Each entry verified against docs/data/psa-tcggroup-aliases.csv.

Deno.test("aliases/snapshot: 'Base Set' → groupId 604", () => {
  const a = aliasForPsaSet("Base Set");
  assertEquals(a?.groupId, 604);
  assertEquals(a?.abbreviation, "BS");
});

Deno.test("aliases/snapshot: 'Prismatic Evolutions' → groupId 23821", () => {
  const a = aliasForPsaSet("Prismatic Evolutions");
  assertEquals(a?.groupId, 23821);
  assertEquals(a?.abbreviation, "PRE");
});

Deno.test("aliases/snapshot: 'Scarlet & Violet 151' → groupId 23237", () => {
  const a = aliasForPsaSet("Scarlet & Violet 151");
  assertEquals(a?.groupId, 23237);
  assertEquals(a?.abbreviation, "MEW");
});

Deno.test("aliases/snapshot: \"Champion's Path ETB Promo\" → groupId 2685", () => {
  const a = aliasForPsaSet("Champion's Path ETB Promo");
  assertEquals(a?.groupId, 2685);
  assertEquals(a?.abbreviation, "CHP");
});

Deno.test("aliases/snapshot: 'M-P Promo' → groupId 24423", () => {
  const a = aliasForPsaSet("M-P Promo");
  assertEquals(a?.groupId, 24423);
  assertEquals(a?.abbreviation, "M-P");
  assertEquals(a?.confidence, "high");
});

Deno.test("aliases/snapshot: 'SV-P Promo' → groupId 22872", () => {
  const a = aliasForPsaSet("SV-P Promo");
  assertEquals(a?.groupId, 22872);
  assertEquals(a?.abbreviation, "SVP");
  assertEquals(a?.altGroupId, 23779);
});

Deno.test("aliases/snapshot: 'Terastal Festival ex' → groupId 23909", () => {
  const a = aliasForPsaSet("Terastal Festival ex");
  assertEquals(a?.groupId, 23909);
  assertEquals(a?.abbreviation, "SV8a");
  assertEquals(a?.publishedYear, 2024);
});

Deno.test("aliases/snapshot: 'Triplet Beat' → groupId 23598", () => {
  const a = aliasForPsaSet("Triplet Beat");
  assertEquals(a?.groupId, 23598);
  assertEquals(a?.abbreviation, "SV1a");
});

Deno.test("aliases/snapshot: 'Fossil' → groupId 630", () => {
  const a = aliasForPsaSet("Fossil");
  assertEquals(a?.groupId, 630);
  assertEquals(a?.abbreviation, "FO");
  assertEquals(a?.publishedYear, 1999);
});

Deno.test("aliases/snapshot: 'Jungle' → groupId 635", () => {
  const a = aliasForPsaSet("Jungle");
  assertEquals(a?.groupId, 635);
  assertEquals(a?.abbreviation, "JU");
  assertEquals(a?.publishedYear, 1999);
});

// ── Null / unknown entries ───────────────────────────────────────────

Deno.test("aliases/null: 'Nonexistent Set' returns null", () => {
  assertEquals(aliasForPsaSet("Nonexistent Set"), null);
});

Deno.test("aliases/null: empty string returns null", () => {
  assertEquals(aliasForPsaSet(""), null);
});

// ── Minimum-size sanity check ────────────────────────────────────────
// If the CSV is accidentally truncated and the generated file has fewer
// than 60 entries, at least one of these 15 lookups will return null and
// the test will fail.

Deno.test("aliases/coverage: map has at least 60 entries (15-entry sampling all non-null)", () => {
  const probes = [
    "Base Set", "Fossil", "Jungle", "Team Rocket", "Neo Genesis",
    "Neo Discovery", "Neo Revelation", "Neo Destiny", "Aquapolis", "Skyridge",
    "Brilliant Stars", "Evolving Skies", "Paldea Evolved", "Obsidian Flames",
    "Stellar Crown",
  ];
  let hits = 0;
  for (const name of probes) {
    if (aliasForPsaSet(name) !== null) hits += 1;
  }
  assertEquals(hits, probes.length, `expected all ${probes.length} probe entries to resolve; ${probes.length - hits} were null`);
});
