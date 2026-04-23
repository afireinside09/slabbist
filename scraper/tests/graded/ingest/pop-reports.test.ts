// tests/graded/ingest/pop-reports.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { runPopReportIngest } from "@/graded/ingest/pop-reports.js";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makeFakeSupabase } from "../../_helpers/fake-supabase.js";

const F = (...p: string[]) => join(dirname(fileURLToPath(import.meta.url)), "../../fixtures", ...p);

describe("runPopReportIngest", () => {
  beforeEach(() => { vi.restoreAllMocks(); });

  it("writes pop rows from PSA fixture and records a completed run", async () => {
    const psaPop = JSON.parse(readFileSync(F("psa/pop-report-sample.json"), "utf8"));
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
      new Response(JSON.stringify(psaPop), { status: 200, headers: { "content-type": "application/json" } }),
    ));

    const supa = makeFakeSupabase() as any;
    const result = await runPopReportIngest({
      supabase: supa,
      userAgent: "t",
      services: ["psa"],
      psa: { apiKey: "k", specIds: [123456] },
    });

    expect(result.status).toBe("completed");
    const pops = await supa._debug.pool.query("select * from public.graded_card_pops");
    expect(pops.rows.length).toBe(3);
  });
});
