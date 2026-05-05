// supabase/functions/price-comp/__tests__/grade-key.test.ts
// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { gradeKeyFor } from "../lib/grade-key.ts";

Deno.test("PSA 10 -> psa_10", () => {
  assertEquals(gradeKeyFor("PSA", "10"), "psa_10");
});

Deno.test("BGS 10 -> bgs_10", () => {
  assertEquals(gradeKeyFor("BGS", "10"), "bgs_10");
});

Deno.test("CGC 10 -> cgc_10", () => {
  assertEquals(gradeKeyFor("CGC", "10"), "cgc_10");
});

Deno.test("SGC 10 -> sgc_10", () => {
  assertEquals(gradeKeyFor("SGC", "10"), "sgc_10");
});

Deno.test("PSA 9.5 -> grade_9_5 (generic intermediate tier)", () => {
  assertEquals(gradeKeyFor("PSA", "9.5"), "grade_9_5");
});

Deno.test("BGS 9.5 -> grade_9_5 (generic intermediate tier)", () => {
  assertEquals(gradeKeyFor("BGS", "9.5"), "grade_9_5");
});

Deno.test("PSA 9 -> grade_9", () => {
  assertEquals(gradeKeyFor("PSA", "9"), "grade_9");
});

Deno.test("PSA 7 -> grade_7", () => {
  assertEquals(gradeKeyFor("PSA", "7"), "grade_7");
});

Deno.test("PSA 6 -> null (not published as a tier by PriceCharting)", () => {
  assertEquals(gradeKeyFor("PSA", "6"), null);
});

Deno.test("Whitespace and PSA verbose adjectives are tolerated", () => {
  assertEquals(gradeKeyFor("PSA", "GEM MT 10"), "psa_10");
  assertEquals(gradeKeyFor("PSA", " 10 "), "psa_10");
});

Deno.test("TAG (unsupported by PriceCharting) -> null", () => {
  assertEquals(gradeKeyFor("TAG", "10"), null);
});
