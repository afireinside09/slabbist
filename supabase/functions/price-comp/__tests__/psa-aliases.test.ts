// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aliasForPsaSet } from "../lib/psa-aliases.ts";

Deno.test("aliasForPsaSet: 'Base Set' returns group_id 604", () => {
  const a = aliasForPsaSet("Base Set");
  assertEquals(a?.groupId, 604);
  assertEquals(a?.abbreviation, "BS");
  assertEquals(a?.publishedYear, 1999);
  assertEquals(a?.confidence, "medium");
});

Deno.test("aliasForPsaSet: 'SV-P Promo' maps to SV: Scarlet & Violet Promo Cards (22872)", () => {
  const a = aliasForPsaSet("SV-P Promo");
  assertEquals(a?.groupId, 22872);
  assertEquals(a?.abbreviation, "SVP");
});

Deno.test("aliasForPsaSet: 'Terastal Festival ex' maps to SV8a Terastal Fest ex (23909)", () => {
  const a = aliasForPsaSet("Terastal Festival ex");
  assertEquals(a?.groupId, 23909);
  assertEquals(a?.abbreviation, "SV8a");
  assertEquals(a?.publishedYear, 2024);
});

Deno.test("aliasForPsaSet: 'M-P Promo' maps to M-P Promotional Cards (24423)", () => {
  const a = aliasForPsaSet("M-P Promo");
  assertEquals(a?.groupId, 24423);
  assertEquals(a?.confidence, "high");
});

Deno.test("aliasForPsaSet: 'Champion's Path ETB Promo' aliases to Champion's Path (2685)", () => {
  const a = aliasForPsaSet("Champion's Path ETB Promo");
  assertEquals(a?.groupId, 2685);
});

Deno.test("aliasForPsaSet: nonexistent set returns null", () => {
  assertEquals(aliasForPsaSet("Definitely Not A Real Set Name"), null);
});

Deno.test("aliasForPsaSet: matching is case-sensitive", () => {
  // PSA names are stored as-spelled in graded_card_identities; we don't
  // case-fold so callers can fail loudly when an upstream rename happens.
  assertEquals(aliasForPsaSet("base set"), null);
});

Deno.test("aliasForPsaSet: empty string returns null", () => {
  assertEquals(aliasForPsaSet(""), null);
});
