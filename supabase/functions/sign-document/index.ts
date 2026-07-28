// ============================================================
// supabase/functions/sign-document/index.ts
//
// Live-test fix brief #2, item 3 — customer signature on quotes and
// invoices via a public link.
//
// The token IS the credential. Nothing here trusts the caller's identity;
// it only dereferences `sign_token` through two SECURITY DEFINER RPCs
// (get_signature_request / submit_signature, see
// supabase/20260728_public_links_sign_and_track.sql) that are granted to
// service_role only. Anon RLS is never opened on quotations or orders —
// same posture as the staff-PIN functions.
//
// Routes (POST body):
//   { action: "get",  token }                     -> document to display
//   { action: "sign", token, signature, name }    -> record the signature
//
// Deploy:  supabase functions deploy sign-document
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// A signature pad PNG is a few KB. Anything much larger is either a
// mistake or someone using the endpoint as free storage — reject before
// it reaches the database.
const MAX_SIGNATURE_BYTES = 512 * 1024;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const action = String(body.action ?? "get");
  const token = String(body.token ?? "").trim();
  if (!token) return json({ error: "Missing token" }, 400);

  if (action === "get") {
    const { data, error } = await admin.rpc("get_signature_request", {
      p_token: token,
    });
    if (error) return json({ error: error.message }, 500);
    const row = Array.isArray(data) ? data[0] : data;
    if (!row) return json({ error: "Invalid or expired link" }, 404);
    return json({
      status: row.sig_status,
      documentType: row.doc_type,
      documentId: row.doc_id,
      customerName: row.sig_customer_name,
      signedAt: row.sig_signed_at,
      orgName: row.org_name,
      document: row.payload,
    });
  }

  if (action === "sign") {
    const signature = String(body.signature ?? "");
    const name = String(body.name ?? "");
    if (!signature) return json({ error: "Signature is required" }, 400);
    if (signature.length > MAX_SIGNATURE_BYTES) {
      return json({ error: "Signature image too large" }, 413);
    }

    // Best-effort only — behind Supabase's proxy this is the forwarded
    // chain, and it is recorded for audit, never trusted for authz.
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      null;

    const { data, error } = await admin.rpc("submit_signature", {
      p_token: token,
      p_signature_data: signature,
      p_customer_name: name,
      p_signer_ip: ip,
    });
    if (error) return json({ error: error.message }, 500);
    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.ok) {
      return json({ error: row?.message ?? "Could not sign" }, 400);
    }
    return json({ ok: true, message: row.message });
  }

  return json({ error: `Unknown action: ${action}` }, 400);
});
