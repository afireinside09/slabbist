import { describe, expect, it } from "vitest";
import { buildEbayQueryForWatchlistRow, GRADE_TIERS_BY_SERVICE } from "@/graded/watchlist.js";

describe("GRADE_TIERS_BY_SERVICE", () => {
  it("defines tiers for every supported grading service", () => {
    expect(GRADE_TIERS_BY_SERVICE.PSA).toContain("10");
    expect(GRADE_TIERS_BY_SERVICE.CGC).toContain("10");
    expect(GRADE_TIERS_BY_SERVICE.BGS).toContain("9.5");
    expect(GRADE_TIERS_BY_SERVICE.SGC).toEqual(["10"]);
    expect(GRADE_TIERS_BY_SERVICE.TAG).toEqual(["10"]);
  });
});

describe("buildEbayQueryForWatchlistRow", () => {
  it("quotes card name and set, and appends year + grading service + grade", () => {
    const q = buildEbayQueryForWatchlistRow({
      identityId: "id-1",
      gradingService: "PSA",
      grade: "10",
      popularityRank: 1,
      cardName: "Charizard Holo (1st Edition Shadowless)",
      setName: "Base Set",
      year: 1999,
    });
    expect(q).toBe(`"Charizard Holo (1st Edition Shadowless)" "Base Set" 1999 PSA 10`);
  });

  it("omits year when missing and still produces a usable query", () => {
    const q = buildEbayQueryForWatchlistRow({
      identityId: "id-2",
      gradingService: "CGC",
      grade: "9.5",
      popularityRank: null,
      cardName: "Pikachu Illustrator",
      setName: "CoroCoro Comic Promo",
      year: null,
    });
    expect(q).toBe(`"Pikachu Illustrator" "CoroCoro Comic Promo" CGC 9.5`);
  });
});
