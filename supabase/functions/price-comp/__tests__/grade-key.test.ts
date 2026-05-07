// @ts-nocheck — Deno runtime; LSP can't resolve std/* or .ts paths.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { gradeKeyFor } from "../lib/grade-key.ts";

Deno.test("(PSA, '10') maps to psa_10", () => {
  assertEquals(gradeKeyFor("PSA", "10"), "psa_10");
});

Deno.test("(PSA, '9.5') maps to psa_9_5", () => {
  assertEquals(gradeKeyFor("PSA", "9.5"), "psa_9_5");
});

Deno.test("(PSA, '9') maps to psa_9", () => {
  assertEquals(gradeKeyFor("PSA", "9"), "psa_9");
});

Deno.test("(PSA, '8') maps to psa_8", () => {
  assertEquals(gradeKeyFor("PSA", "8"), "psa_8");
});

Deno.test("(PSA, '7') maps to psa_7", () => {
  assertEquals(gradeKeyFor("PSA", "7"), "psa_7");
});

Deno.test("(BGS, '10') maps to bgs_10", () => {
  assertEquals(gradeKeyFor("BGS", "10"), "bgs_10");
});

Deno.test("(CGC, '10') maps to cgc_10", () => {
  assertEquals(gradeKeyFor("CGC", "10"), "cgc_10");
});

Deno.test("(SGC, '10') maps to sgc_10", () => {
  assertEquals(gradeKeyFor("SGC", "10"), "sgc_10");
});

Deno.test("(TAG, '10') returns null (unsupported in v1)", () => {
  assertEquals(gradeKeyFor("TAG", "10"), null);
});

Deno.test("(BGS, '9.5') returns null in v1 (deferred)", () => {
  assertEquals(gradeKeyFor("BGS", "9.5"), null);
});

Deno.test("(PSA, '6') returns null (sub-PSA-7 unsupported)", () => {
  assertEquals(gradeKeyFor("PSA", "6"), null);
});

Deno.test("PSA verbose grade strings strip down to bare grade", () => {
  assertEquals(gradeKeyFor("PSA", "GEM MT 10"), "psa_10");
  assertEquals(gradeKeyFor("PSA", "MINT 9"), "psa_9");
});
