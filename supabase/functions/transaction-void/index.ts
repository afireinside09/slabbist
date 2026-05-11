// @ts-nocheck

import { createClient } from "@supabase/supabase-js";

interface Original {
  id: string;
  store_id: string;
  lot_id: string;
  vendor_id: string | null;
  vendor_name_snapshot: string;
  total_buy_cents: number;
  payment_method: string;
}

export function buildVoidRow(args: {
  original: Original;
  userId: string;
  reason: string;
}): Record<string, unknown> {
  const now = new Date().toISOString();
  return {
    store_id: args.original.store_id,
    lot_id: args.original.lot_id,
    vendor_id: args.original.vendor_id,
    vendor_name_snapshot: args.original.vendor_name_snapshot,
    total_buy_cents: -args.original.total_buy_cents,
    payment_method: args.original.payment_method,
    paid_at: now,
    paid_by_user_id: args.userId,
    voided_at: now,
    voided_by_user_id: args.userId,
    void_reason: args.reason,
    void_of_transaction_id: args.original.id,
  };
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (v === undefined || v === "") throw new Error(`missing env: ${name}`);
  return v;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, x-client-info, apikey, content-type", "access-control-allow-methods": "POST, OPTIONS" } });
  }
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED" });

  let body: { transaction_id?: string; reason?: string };
  try { body = await req.json(); } catch { return json(400, { code: "INVALID_JSON" }); }
  if (!body?.transaction_id || !body?.reason) return json(400, { code: "MISSING_FIELDS" });

  const userClient = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });
  const service = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

  const { data: who, error: whoErr } = await userClient.auth.getUser();
  if (whoErr || !who?.user) return json(401, { code: "UNAUTHENTICATED" });
  const userId = who.user.id;

  const { data: original, error: getErr } = await service
    .from("transactions")
    .select("id, store_id, lot_id, vendor_id, vendor_name_snapshot, total_buy_cents, payment_method, voided_at, void_of_transaction_id")
    .eq("id", body.transaction_id)
    .maybeSingle();
  if (getErr) return json(500, { code: "DB_ERROR", detail: getErr.message });
  if (!original) return json(404, { code: "NOT_FOUND" });

  if (original.voided_at !== null || original.void_of_transaction_id !== null) {
    return json(409, { code: "ALREADY_VOIDED" });
  }

  const { data: membership } = await service
    .from("store_members")
    .select("role")
    .eq("store_id", original.store_id)
    .eq("user_id", userId)
    .maybeSingle();
  if (!membership) return json(403, { code: "NOT_A_MEMBER" });

  // Mark original.
  const now = new Date().toISOString();
  const { error: markErr } = await service
    .from("transactions")
    .update({ voided_at: now, voided_by_user_id: userId, void_reason: body.reason })
    .eq("id", original.id);
  if (markErr) return json(500, { code: "DB_ERROR", detail: markErr.message });

  // Insert void row.
  const voidRow = buildVoidRow({ original: original as Original, userId, reason: body.reason });
  const { data: inserted, error: voidErr } = await service.from("transactions").insert(voidRow).select("*").maybeSingle();
  if (voidErr) return json(500, { code: "DB_ERROR", detail: voidErr.message });

  // Flip lot to voided.
  await service.from("lots")
    .update({ lot_offer_state: "voided", lot_offer_state_updated_at: now })
    .eq("id", original.lot_id);

  return json(200, { void_transaction: inserted, original_id: original.id });
});
