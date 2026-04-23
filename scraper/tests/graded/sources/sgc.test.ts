import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { sgcCertLookup } from "@/graded/sources/sgc.js";

const F = join(dirname(fileURLToPath(import.meta.url)), "../../fixtures/sgc");
const html = readFileSync(join(F, "cert-lookup.html"), "utf8");
const mockOk = (body: string) => vi.fn().mockResolvedValue(new Response(body, { status: 200 }));

describe("sgc source", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("sgcCertLookup parses dl-structured cert detail", async () => {
    vi.stubGlobal("fetch", mockOk(html));
    const rec = await sgcCertLookup("12345678", { userAgent: "t" });
    expect(rec.gradingService).toBe("SGC");
    expect(rec.grade).toBe("9");
    expect(rec.identity.cardName).toBe("Snorlax");
    expect(rec.identity.setName).toBe("Pokemon Jungle");
    expect(rec.identity.cardNumber).toBe("11");
    expect(rec.identity.variant).toBe("Holo");
  });

  it("throws when cert-result section is missing", async () => {
    vi.stubGlobal("fetch", mockOk("<html></html>"));
    await expect(sgcCertLookup("0", { userAgent: "t" })).rejects.toThrow(/SGC cert/i);
  });
});
