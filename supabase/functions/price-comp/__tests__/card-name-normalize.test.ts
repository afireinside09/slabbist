// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.

import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { normalizeCardName } from "../lib/card-name-normalize.ts";

describe("normalizeCardName", () => {
  it("strips -HOLO suffix from PSA-style names", () => {
    assertEquals(normalizeCardName("CHARIZARD-HOLO"), "CHARIZARD");
    assertEquals(normalizeCardName("BLASTOISE-HOLO"), "BLASTOISE");
  });

  it("strips multiple trailing variant tags", () => {
    assertEquals(normalizeCardName("PIKACHU-HOLO-1ST"), "PIKACHU");
  });

  it("preserves hyphens that are part of the card name", () => {
    assertEquals(normalizeCardName("HO-OH"), "HO-OH");
    assertEquals(normalizeCardName("MIME JR"), "MIME JR");
  });

  it("leaves names without trailing tags untouched", () => {
    assertEquals(normalizeCardName("CHARIZARD"), "CHARIZARD");
    assertEquals(normalizeCardName("Pikachu ex"), "Pikachu ex");
  });

  it("strips trailing tags from mixed-case input", () => {
    assertEquals(normalizeCardName("Charizard-Holo"), "Charizard");
  });

  it("trims surrounding whitespace", () => {
    assertEquals(normalizeCardName("  CHARIZARD-HOLO  "), "CHARIZARD");
  });
});
