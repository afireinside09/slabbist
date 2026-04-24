// @ts-nocheck — runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports.
//
// eBay Marketplace Account Deletion / Closure notification endpoint.
// https://developer.ebay.com/marketplace-account-deletion
//
// Two request shapes:
//   GET  ?challenge_code=...  → returns { challengeResponse: sha256Hex(challengeCode + verificationToken + endpointUrl) }
//   POST { notification: { data: { username, userId, eiasToken } } }  → 200, then delete user data
//
// Env (set via `supabase secrets set`):
//   EBAY_VERIFICATION_TOKEN          — 32–80 char token [A-Za-z0-9_-]; also pasted into eBay console.
//   EBAY_NOTIFICATION_ENDPOINT_URL   — exact public URL registered with eBay; used in the challenge hash.

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  const verificationToken = Deno.env.get("EBAY_VERIFICATION_TOKEN");
  const endpointUrl = Deno.env.get("EBAY_NOTIFICATION_ENDPOINT_URL");
  if (!verificationToken || !endpointUrl) {
    console.error("ebay-account-deletion: missing env EBAY_VERIFICATION_TOKEN or EBAY_NOTIFICATION_ENDPOINT_URL");
    return jsonResponse(500, { error: "server_misconfigured" });
  }

  if (req.method === "GET") {
    const challengeCode = new URL(req.url).searchParams.get("challenge_code");
    if (!challengeCode) return jsonResponse(400, { error: "missing_challenge_code" });
    const challengeResponse = await sha256Hex(challengeCode + verificationToken + endpointUrl);
    return jsonResponse(200, { challengeResponse });
  }

  if (req.method === "POST") {
    let payload: unknown;
    try {
      payload = await req.json();
    } catch {
      return jsonResponse(400, { error: "invalid_json" });
    }

    const data = (payload as { notification?: { data?: { username?: string; userId?: string; eiasToken?: string } } })
      ?.notification?.data;

    // TODO: once any table stores eBay seller identifiers (username / userId / eiasToken),
    // delete/anonymize matching rows here using the service-role client. eBay requires the
    // deletion to complete within 30 days; returning 200 now only acknowledges receipt.
    console.log("ebay-account-deletion: received notification", {
      username: data?.username,
      userId: data?.userId,
      eiasToken: data?.eiasToken,
    });

    return jsonResponse(200, { ok: true });
  }

  return jsonResponse(405, { error: "method_not_allowed" });
});
