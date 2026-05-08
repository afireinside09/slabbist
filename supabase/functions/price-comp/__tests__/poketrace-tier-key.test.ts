import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { poketraceTierKey } from "../lib/poketrace-tier-key.ts";

Deno.test("poketraceTierKey: PSA + 10 → PSA_10", () => {
  assertEquals(poketraceTierKey("PSA", "10"), "PSA_10");
});

Deno.test("poketraceTierKey: PSA + 9.5 → PSA_9_5", () => {
  assertEquals(poketraceTierKey("PSA", "9.5"), "PSA_9_5");
});

Deno.test("poketraceTierKey: BGS + 10 → BGS_10", () => {
  assertEquals(poketraceTierKey("BGS", "10"), "BGS_10");
});

Deno.test("poketraceTierKey: lowercase grading service is normalized", () => {
  assertEquals(poketraceTierKey("psa", "10"), "PSA_10");
});

Deno.test("poketraceTierKey: SGC + 9.5 → SGC_9_5", () => {
  assertEquals(poketraceTierKey("SGC", "9.5"), "SGC_9_5");
});

Deno.test("poketraceTierKey: TAG + 1.5 → TAG_1_5", () => {
  assertEquals(poketraceTierKey("TAG", "1.5"), "TAG_1_5");
});
