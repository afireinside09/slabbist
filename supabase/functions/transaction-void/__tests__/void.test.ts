import { assertEquals } from "jsr:@std/assert";
import { buildVoidRow } from "../index.ts";

Deno.test("buildVoidRow inverts total and links to original", () => {
  const orig = {
    id: "00000000-0000-0000-0000-000000000001",
    store_id: "00000000-0000-0000-0000-0000000000aa",
    lot_id: "00000000-0000-0000-0000-0000000000bb",
    vendor_id: "00000000-0000-0000-0000-0000000000cc",
    vendor_name_snapshot: "Acme",
    total_buy_cents: 10_000,
    payment_method: "cash",
  };
  const userId = "00000000-0000-0000-0000-0000000000ff";
  const row = buildVoidRow({ original: orig, userId, reason: "vendor returned" });
  assertEquals(row.total_buy_cents, -10_000);
  assertEquals(row.void_of_transaction_id, orig.id);
  assertEquals(row.voided_by_user_id, userId);
  assertEquals(row.void_reason, "vendor returned");
  assertEquals(row.vendor_name_snapshot, "Acme");
  assertEquals(row.payment_method, "cash");
  assertEquals(typeof row.voided_at, "string");
});
