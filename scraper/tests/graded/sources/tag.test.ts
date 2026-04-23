import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { tagCertLookup } from "@/graded/sources/tag.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/tag");
const mockOkJson = (body: unknown) => vi.fn().mockResolvedValue(
  new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } }),
);

describe("tag source", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("tagCertLookup normalizes the cert JSON", async () => {
    const fixture = JSON.parse(readFileSync(join(F, "cert-lookup.json"), "utf8"));
    vi.stubGlobal("fetch", mockOkJson(fixture));
    const rec = await tagCertLookup("TAG123456", { userAgent: "t" });
    expect(rec.gradingService).toBe("TAG");
    expect(rec.grade).toBe("10");
    expect(rec.identity.cardName).toBe("Charizard VSTAR");
    expect(rec.identity.setName).toBe("Sword & Shield Brilliant Stars");
    expect(rec.identity.cardNumber).toBe("174");
    expect(rec.identity.variant).toBe("Rainbow Rare");
    expect(rec.identity.year).toBe(2022);
    expect(rec.identity.language).toBe("en");
  });
});
