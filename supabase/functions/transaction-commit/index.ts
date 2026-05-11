// @ts-nocheck — Deno + remote imports.
//
// /transaction-commit
// Atomic: verify lot is .accepted, read priced scans, snapshot identities,
// INSERT transactions row, INSERT transaction_lines rows, UPDATE lots.lot_offer_state to 'paid'.
//
// Request: { lot_id, payment_method, payment_reference?, vendor_id?, vendor_name_override? }
// Response 200: { transaction, lines[] }
// Response 200 + deduped: true when a duplicate commit race hits the unique index.
// Response 409: state precondition failure (lot not accepted).
// Response 422: no priced scans.
// Response 403: caller not a store member.
// Response 401: not authenticated.

import { createClient } from "@supabase/supabase-js";

interface Scan {
  id: string;
  grader: string;
  grade: string | null;
  cert_number: string;
  buy_price_cents: number | null;
  graded_card_identity_id: string | null;
  reconciled_headline_price_cents: number | null;
  reconciled_source: string | null;
}

interface Identity {
  id: string;
  card_name: string;
  set_name: string;
  card_number: string | null;
  year: number | null;
  variant: string | null;
}

interface Vendor {
  id: string;
  display_name: string;
}

export function buildIdentitySnapshot(args: {
  scan: Pick<Scan, "grader" | "grade" | "cert_number" | "reconciled_headline_price_cents" | "reconciled_source">;
  identity: Pick<Identity, "card_name" | "set_name" | "card_number" | "year" | "variant"> | null;
}): Record<string, unknown> {
  const i = args.identity;
  return {
    card_name: i?.card_name ?? null,
    set_name: i?.set_name ?? null,
    card_number: i?.card_number ?? null,
    year: i?.year ?? null,
    variant: i?.variant ?? null,
    grader: args.scan.grader,
    grade: args.scan.grade,
    cert_number: args.scan.cert_number,
    comp_used_cents: args.scan.reconciled_headline_price_cents,
    reconciled_source: args.scan.reconciled_source,
  };
}

export function resolveVendorNameSnapshot(args: {
  override: string | null | undefined;
  vendor: Pick<Vendor, "display_name"> | null;
}): string {
  const o = (args.override ?? "").trim();
  if (o) return o;
  if (args.vendor?.display_name) return args.vendor.display_name;
  return "(unknown)";
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

  let body: { lot_id?: string; payment_method?: string; payment_reference?: string;
              vendor_id?: string; vendor_name_override?: string };
  try { body = await req.json(); } catch { return json(400, { code: "INVALID_JSON" }); }
  if (!body?.lot_id || !body?.payment_method) return json(400, { code: "MISSING_FIELDS" });

  const userClient = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });
  const serviceClient = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

  // Identify caller.
  const { data: who, error: whoErr } = await userClient.auth.getUser();
  if (whoErr || !who?.user) return json(401, { code: "UNAUTHENTICATED" });
  const userId = who.user.id;

  // Membership check (MVP: any member can commit; subproject 7 will gate by role).
  const { data: lot, error: lotErr } = await serviceClient
    .from("lots")
    .select("id, store_id, vendor_id, lot_offer_state")
    .eq("id", body.lot_id)
    .maybeSingle();
  if (lotErr) return json(500, { code: "DB_ERROR", detail: lotErr.message });
  if (!lot) return json(404, { code: "LOT_NOT_FOUND" });

  const { data: membership } = await serviceClient
    .from("store_members")
    .select("role")
    .eq("store_id", lot.store_id)
    .eq("user_id", userId)
    .maybeSingle();
  if (!membership) return json(403, { code: "NOT_A_MEMBER" });

  if (lot.lot_offer_state !== "accepted") {
    return json(409, { code: "WRONG_STATE", lot_offer_state: lot.lot_offer_state });
  }

  // Fetch priced scans + identities for snapshot.
  const { data: scans, error: scansErr } = await serviceClient
    .from("scans")
    .select("id, grader, grade, cert_number, buy_price_cents, graded_card_identity_id, reconciled_headline_price_cents, reconciled_source")
    .eq("lot_id", body.lot_id);
  if (scansErr) return json(500, { code: "DB_ERROR", detail: scansErr.message });

  const priced = (scans ?? []).filter((s) => typeof s.buy_price_cents === "number" && s.buy_price_cents > 0);
  if (priced.length === 0) return json(422, { code: "NO_PRICED_LINES" });

  // Hydrate identities.
  const identityIds = priced.map((s) => s.graded_card_identity_id).filter((id): id is string => !!id);
  let identityMap: Record<string, Identity> = {};
  if (identityIds.length > 0) {
    const { data: idents, error: identErr } = await serviceClient
      .from("graded_card_identities")
      .select("id, card_name, set_name, card_number, year, variant")
      .in("id", identityIds);
    if (identErr) return json(500, { code: "DB_ERROR", detail: identErr.message });
    identityMap = Object.fromEntries((idents ?? []).map((i) => [i.id, i as Identity]));
  }

  // Resolve vendor snapshot.
  let vendor: Vendor | null = null;
  const vendorId = body.vendor_id ?? lot.vendor_id ?? null;
  if (vendorId) {
    const { data: v } = await serviceClient
      .from("vendors")
      .select("id, display_name")
      .eq("id", vendorId)
      .maybeSingle();
    vendor = v as Vendor | null;
  }
  const vendorNameSnapshot = resolveVendorNameSnapshot({
    override: body.vendor_name_override ?? null,
    vendor: vendor ? { display_name: vendor.display_name } : null,
  });

  const totalBuyCents = priced.reduce((acc, s) => acc + (s.buy_price_cents ?? 0), 0);
  const txnId = crypto.randomUUID();
  const paidAt = new Date().toISOString();

  // INSERT transaction. Unique partial index guards against duplicate commits.
  const { error: txnErr } = await serviceClient.from("transactions").insert({
    id: txnId,
    store_id: lot.store_id,
    lot_id: lot.id,
    vendor_id: vendorId,
    vendor_name_snapshot: vendorNameSnapshot,
    total_buy_cents: totalBuyCents,
    payment_method: body.payment_method,
    payment_reference: body.payment_reference ?? null,
    paid_at: paidAt,
    paid_by_user_id: userId,
  });
  if (txnErr) {
    if (txnErr.code === "23505") {
      // Race: another request landed the transaction first. Reconcile so the
      // dedup response is consistent — re-run the line INSERT (idempotent on
      // the (transaction_id, scan_id) primary key — duplicate rows would
      // 23505 but the upsert ignoreDuplicates flag swallows them) and re-run
      // the lot UPDATE (convergent — repeated assignment of 'paid' is a no-op).
      // Without this, an earlier attempt that crashed between the txn INSERT
      // and the lines INSERT / lot UPDATE would leave divergent state that
      // never recovered.
      const { data: existing } = await serviceClient
        .from("transactions")
        .select("*")
        .eq("lot_id", lot.id)
        .is("void_of_transaction_id", null)
        .is("voided_at", null)
        .maybeSingle();
      if (existing) {
        // Idempotent line insert — PK conflicts on duplicate (transaction_id,
        // scan_id) rows are ignored via upsert ignoreDuplicates.
        const dedupLines = priced.map((s, idx) => ({
          transaction_id: existing.id,
          scan_id: s.id,
          line_index: idx,
          buy_price_cents: s.buy_price_cents!,
          identity_snapshot: buildIdentitySnapshot({
            scan: s,
            identity: s.graded_card_identity_id ? (identityMap[s.graded_card_identity_id] ?? null) : null,
          }),
        }));
        await serviceClient
          .from("transaction_lines")
          .upsert(dedupLines, { onConflict: "transaction_id,scan_id", ignoreDuplicates: true });
        // Idempotent lot flip — convergent assignment. Don't CAS here because
        // a prior in-flight attempt may have already moved the lot to 'paid'.
        await serviceClient
          .from("lots")
          .update({
            lot_offer_state: "paid",
            lot_offer_state_updated_at: new Date().toISOString(),
            status: "converted",
          })
          .eq("id", lot.id);
        const { data: existingLines } = await serviceClient
          .from("transaction_lines")
          .select("*")
          .eq("transaction_id", existing.id);
        return json(200, { transaction: existing, lines: existingLines ?? [], deduped: true });
      }
    }
    return json(500, { code: "DB_ERROR", detail: txnErr.message });
  }

  // INSERT transaction_lines.
  const lines = priced.map((s, idx) => ({
    transaction_id: txnId,
    scan_id: s.id,
    line_index: idx,
    buy_price_cents: s.buy_price_cents!,
    identity_snapshot: buildIdentitySnapshot({
      scan: s,
      identity: s.graded_card_identity_id ? (identityMap[s.graded_card_identity_id] ?? null) : null,
    }),
  }));
  const { error: linesErr } = await serviceClient.from("transaction_lines").insert(lines);
  if (linesErr) return json(500, { code: "DB_ERROR", detail: linesErr.message });

  // Flip the lot. CAS on `lot_offer_state = 'accepted'` so we don't trample
  // a state change that happened between the initial read and this write.
  // The transaction + lines we already inserted are durable; surfacing 409
  // here lets the caller (operator UI) notice the actual conflict instead of
  // silently overwriting whatever state the lot raced into.
  const { data: updated, error: lotUpdErr } = await serviceClient
    .from("lots")
    .update({
      lot_offer_state: "paid",
      lot_offer_state_updated_at: paidAt,
      status: "converted",
    })
    .eq("id", lot.id)
    .eq("lot_offer_state", "accepted")
    .select("id")
    .maybeSingle();
  if (lotUpdErr) return json(500, { code: "DB_ERROR", detail: lotUpdErr.message });
  if (!updated) {
    return json(409, { code: "LOT_STATE_RACED", lot_id: lot.id });
  }

  // Re-read for the response.
  const { data: txn } = await serviceClient.from("transactions").select("*").eq("id", txnId).maybeSingle();
  return json(200, { transaction: txn, lines });
});
