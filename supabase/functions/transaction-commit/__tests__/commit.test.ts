import { assertEquals } from "jsr:@std/assert";
import { buildIdentitySnapshot, resolveVendorNameSnapshot } from "../index.ts";

Deno.test("buildIdentitySnapshot pulls all expected fields", () => {
  const snap = buildIdentitySnapshot({
    scan: { grader: "PSA", grade: "10", cert_number: "12345678",
            reconciled_headline_price_cents: 18500, reconciled_source: "avg" },
    identity: { card_name: "Charizard", set_name: "Base Set",
                card_number: "4", year: 1999, variant: "Holo" },
  });
  assertEquals(snap, {
    card_name: "Charizard", set_name: "Base Set", card_number: "4",
    year: 1999, variant: "Holo",
    grader: "PSA", grade: "10", cert_number: "12345678",
    comp_used_cents: 18500, reconciled_source: "avg",
  });
});

Deno.test("buildIdentitySnapshot tolerates missing identity (manual entry scan)", () => {
  const snap = buildIdentitySnapshot({
    scan: { grader: "PSA", grade: null, cert_number: "x",
            reconciled_headline_price_cents: null, reconciled_source: null },
    identity: null,
  });
  assertEquals(snap, {
    card_name: null, set_name: null, card_number: null,
    year: null, variant: null,
    grader: "PSA", grade: null, cert_number: "x",
    comp_used_cents: null, reconciled_source: null,
  });
});

Deno.test("resolveVendorNameSnapshot precedence: override > vendor > unknown", () => {
  assertEquals(resolveVendorNameSnapshot({ override: "X", vendor: { display_name: "Y" } }), "X");
  assertEquals(resolveVendorNameSnapshot({ override: null, vendor: { display_name: "Y" } }), "Y");
  assertEquals(resolveVendorNameSnapshot({ override: null, vendor: null }), "(unknown)");
  assertEquals(resolveVendorNameSnapshot({ override: "", vendor: { display_name: "Y" } }), "Y");
});
