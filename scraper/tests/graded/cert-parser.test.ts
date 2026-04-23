import { describe, it, expect } from "vitest";
import { parseGradedTitle } from "@/graded/cert-parser.js";

describe("parseGradedTitle", () => {
  it("parses a PSA 10 title", () => {
    const out = parseGradedTitle("1999 Pokemon Base Set Charizard Holo #4 PSA 10 GEM MINT");
    expect(out?.gradingService).toBe("PSA");
    expect(out?.grade).toBe("10");
    expect(out?.certNumber).toBeNull();
  });

  it("parses a BGS 9.5 title with half-grade", () => {
    const out = parseGradedTitle("Charizard Base Set BGS 9.5 Gem Mint");
    expect(out?.gradingService).toBe("BGS");
    expect(out?.grade).toBe("9.5");
  });

  it("parses CGC 10 Pristine", () => {
    const out = parseGradedTitle("CGC 10 PRISTINE Pikachu Illustrator Promo");
    expect(out?.gradingService).toBe("CGC");
    expect(out?.grade).toBe("10");
  });

  it("extracts cert number when present", () => {
    const out = parseGradedTitle("PSA 9 Blastoise Base #2 Cert 54829123 Unlimited");
    expect(out?.certNumber).toBe("54829123");
  });

  it("returns null for non-graded title", () => {
    expect(parseGradedTitle("Charizard Base Set Unlimited Ungraded")).toBeNull();
  });

  it("parses SGC 9 and TAG 10", () => {
    expect(parseGradedTitle("SGC 9 Mew Promo")?.gradingService).toBe("SGC");
    expect(parseGradedTitle("TAG 10 Charizard VMAX")?.gradingService).toBe("TAG");
  });
});
