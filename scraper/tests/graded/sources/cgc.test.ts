import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { cgcCertLookup } from "@/graded/sources/cgc.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/cgc");
const html = readFileSync(join(F, "cert-lookup.html"), "utf8");
const mockOkHtml = (body: string) => vi.fn().mockResolvedValue(new Response(body, { status: 200 }));

describe("cgc source", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("cgcCertLookup scrapes fields into GradedCertRecord", async () => {
    vi.stubGlobal("fetch", mockOkHtml(html));
    const rec = await cgcCertLookup("1234567890", { userAgent: "t" });
    expect(rec.gradingService).toBe("CGC");
    expect(rec.certNumber).toBe("1234567890");
    expect(rec.grade).toBe("9.5");
    expect(rec.identity.setName).toBe("Base Set Shadowless");
    expect(rec.identity.cardName).toBe("Charizard-Holo");
    expect(rec.identity.cardNumber).toBe("4");
    expect(rec.identity.variant).toBe("1st Edition");
    expect(rec.identity.language).toBe("en");
  });

  it("throws when the cert-details block is missing", async () => {
    vi.stubGlobal("fetch", mockOkHtml("<html><body>not found</body></html>"));
    await expect(cgcCertLookup("0000000000", { userAgent: "t" })).rejects.toThrow(/CGC cert/i);
  });
});
