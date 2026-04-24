import { assertAlmostEquals, assertEquals } from "std/assert";
import { describe, it } from "std/testing/bdd";
import { sampleFactor, freshnessFactor, confidence } from "../stats/confidence.ts";

describe("sampleFactor", () => {
  it("0 at n=0", () => assertEquals(sampleFactor(0), 0));
  it("0.1 at n=1", () => assertAlmostEquals(sampleFactor(1), 0.1, 1e-9));
  it("1.0 at n=10", () => assertEquals(sampleFactor(10), 1.0));
  it("clamps above 10", () => assertEquals(sampleFactor(25), 1.0));
});

describe("freshnessFactor", () => {
  it("1.0 for 90d window", () => assertEquals(freshnessFactor(90), 1.0));
  it("0.5 for 365d window", () => assertEquals(freshnessFactor(365), 0.5));
});

describe("confidence (composite)", () => {
  it("1.0 at n=10 and 90d", () => assertEquals(confidence(10, 90), 1.0));
  it("0.5 at n=10 and 365d", () => assertEquals(confidence(10, 365), 0.5));
  it("0.15 at n=3 and 365d", () => assertAlmostEquals(confidence(3, 365), 0.15, 1e-9));
  it("0.0 on n=0", () => assertEquals(confidence(0, 90), 0.0));
});
