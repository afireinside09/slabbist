import { describe, it } from "std/testing/bdd";
import { assertEquals } from "std/assert";
import { normalizeGrade } from "../lib/grade-normalize.ts";

describe("normalizeGrade", () => {
  it("strips PSA's GEM MT prefix", () => {
    assertEquals(normalizeGrade("GEM MT 10"), "10");
  });

  it("strips PSA's MINT prefix", () => {
    assertEquals(normalizeGrade("MINT 9"), "9");
  });

  it("strips PSA's NM-MT prefix", () => {
    assertEquals(normalizeGrade("NM-MT 8"), "8");
  });

  it("preserves half-grades", () => {
    assertEquals(normalizeGrade("MINT 9.5"), "9.5");
  });

  it("passes through already-normalized grades", () => {
    assertEquals(normalizeGrade("10"), "10");
    assertEquals(normalizeGrade("9.5"), "9.5");
  });

  it("trims surrounding whitespace", () => {
    assertEquals(normalizeGrade("  GEM MT 10  "), "10");
  });

  it("returns input as-is when no trailing number is present", () => {
    // PSA AUTHENTIC certs have no number — no good search alternative,
    // so we degrade gracefully rather than mangle the value.
    assertEquals(normalizeGrade("AUTHENTIC"), "AUTHENTIC");
  });
});
