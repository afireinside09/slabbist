import { assertEquals } from "jsr:@std/assert";
import { computeNewState } from "../index.ts";

Deno.test("computeNewState: drafting → priced when total > 0", () => {
  assertEquals(computeNewState({ current: "drafting", totalCents: 1500 }), "priced");
});

Deno.test("computeNewState: drafting stays drafting when total = 0", () => {
  assertEquals(computeNewState({ current: "drafting", totalCents: 0 }), "drafting");
});

Deno.test("computeNewState: priced → drafting when all prices cleared", () => {
  assertEquals(computeNewState({ current: "priced", totalCents: 0 }), "drafting");
});

Deno.test("computeNewState: terminal states never change", () => {
  for (const s of ["paid", "voided", "declined"] as const) {
    assertEquals(computeNewState({ current: s, totalCents: 0 }), s);
    assertEquals(computeNewState({ current: s, totalCents: 9999 }), s);
  }
});

Deno.test("computeNewState: presented/accepted preserve their state", () => {
  for (const s of ["presented", "accepted"] as const) {
    assertEquals(computeNewState({ current: s, totalCents: 1500 }), s);
  }
});
