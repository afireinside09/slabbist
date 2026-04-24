import { assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { buildCascadeQueries } from "../ebay/query-builder.ts";
import type { GradedCardIdentity } from "../types.ts";

const identity: GradedCardIdentity = {
  id: "abc",
  game: "pokemon",
  language: "en",
  set_code: "SV-SS",
  set_name: "Surging Sparks",
  card_number: "247/191",
  card_name: "Pikachu ex",
  variant: null,
  year: 2024,
};

describe("buildCascadeQueries", () => {
  it("produces 4 buckets in fixed order (narrow-90, broad-90, narrow-365, broad-365)", () => {
    const qs = buildCascadeQueries(identity, "PSA", "10");
    assertEquals(qs.length, 4);
    assertEquals(qs[0].windowDays, 90); assertEquals(qs[0].shape, "narrow");
    assertEquals(qs[1].windowDays, 90); assertEquals(qs[1].shape, "broad");
    assertEquals(qs[2].windowDays, 365); assertEquals(qs[2].shape, "narrow");
    assertEquals(qs[3].windowDays, 365); assertEquals(qs[3].shape, "broad");
  });

  it("narrow query quotes card_name+card_number and grading+grade", () => {
    const qs = buildCascadeQueries(identity, "PSA", "10");
    assertEquals(qs[0].q, `"Pikachu ex 247/191" "PSA 10"`);
  });

  it("broad query is unquoted tokens including set_name", () => {
    const qs = buildCascadeQueries(identity, "PSA", "10");
    assertEquals(qs[1].q, "Pikachu ex Surging Sparks 247/191 PSA 10");
  });

  it("omits null card_number from narrow phrase", () => {
    const noCn = { ...identity, card_number: null };
    const qs = buildCascadeQueries(noCn, "PSA", "10");
    assertEquals(qs[0].q, `"Pikachu ex" "PSA 10"`);
  });

  it("uses Pokemon category id 183454 on every bucket", () => {
    const qs = buildCascadeQueries(identity, "PSA", "10");
    assertEquals(qs.every(q => q.categoryId === "183454"), true);
  });
});
