// @ts-nocheck — runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or remote imports.
//
// /lot-offer-recompute
// Request:  { lot_id: string }
// Response: { lot_id, offered_total_cents, lot_offer_state }
//
// Sums coalesce(scans.buy_price_cents, 0) for the lot; writes the result to
// lots.offered_total_cents; transitions lot_offer_state ↔ drafting/priced
// based on the total. Idempotent.
//
// Authentication: JWT. The caller must be a member of the lot's store —
// enforced by RLS on the underlying tables (this function uses the user's
// JWT, not service role).

import { createClient } from "@supabase/supabase-js";

type LotOfferState =
  | "drafting" | "priced" | "presented" | "accepted"
  | "declined" | "paid" | "voided";

const TERMINAL_STATES: ReadonlySet<LotOfferState> = new Set([
  "paid", "voided", "declined",
]);

const PRESERVE_STATES: ReadonlySet<LotOfferState> = new Set([
  "presented", "accepted",
]);

/**
 * Decides the new lot_offer_state given the current state and the freshly
 * summed total. Pure for unit tests.
 */
export function computeNewState(args: { current: LotOfferState; totalCents: number }): LotOfferState {
  const { current, totalCents } = args;
  if (TERMINAL_STATES.has(current)) return current;
  if (PRESERVE_STATES.has(current)) return current;
  // current is drafting or priced; flip based on total
  return totalCents > 0 ? "priced" : "drafting";
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (v === undefined || v === "") throw new Error(`missing env: ${name}`);
  return v;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
        "access-control-allow-methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  let body: { lot_id?: string };
  try { body = await req.json(); } catch { return json(400, { code: "INVALID_JSON" }); }
  if (!body?.lot_id || typeof body.lot_id !== "string") {
    return json(400, { code: "MISSING_FIELDS" });
  }

  const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });

  const { data: lot, error: lotErr } = await supabase
    .from("lots")
    .select("id, lot_offer_state")
    .eq("id", body.lot_id)
    .maybeSingle();

  if (lotErr) return json(500, { code: "DB_ERROR", detail: lotErr.message });
  if (!lot) return json(404, { code: "LOT_NOT_FOUND" });

  const current = lot.lot_offer_state as LotOfferState;
  if (TERMINAL_STATES.has(current)) {
    // Refuse recompute on terminal lots; iOS treats 409 as "trust local state".
    return json(409, { code: "TERMINAL_STATE", lot_offer_state: current });
  }

  const { data: rows, error: sumErr } = await supabase
    .from("scans")
    .select("buy_price_cents")
    .eq("lot_id", body.lot_id);

  if (sumErr) return json(500, { code: "DB_ERROR", detail: sumErr.message });

  const totalCents = (rows ?? []).reduce(
    (acc, r) => acc + (typeof r.buy_price_cents === "number" ? r.buy_price_cents : 0),
    0,
  );
  const next = computeNewState({ current, totalCents });

  const { error: updErr } = await supabase
    .from("lots")
    .update({
      offered_total_cents: totalCents,
      lot_offer_state: next,
      lot_offer_state_updated_at: new Date().toISOString(),
    })
    .eq("id", body.lot_id);

  if (updErr) return json(500, { code: "DB_ERROR", detail: updErr.message });

  return json(200, {
    lot_id: body.lot_id,
    offered_total_cents: totalCents,
    lot_offer_state: next,
  });
});
