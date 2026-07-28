// ============================================================
// supabase/functions/track-order/index.ts
//
// Live-test fix brief #2, item 6 — customer-facing order tracking via a
// public link. Read-only.
//
// Same posture as sign-document: the token is the credential, it is only
// dereferenced through the SECURITY DEFINER get_order_tracking() RPC
// (service_role-only grant), and anon RLS on `orders` stays closed.
//
// The RPC — not this function — decides what is safe to return. Crew
// details (vehicle / driver / phone) are gated on the org's
// `tracking_show_crew` setting and come back null otherwise, so a change
// to this function can't accidentally leak them.
//
// Route (POST body): { token } -> tracking payload
//
// Deploy:  supabase functions deploy track-order
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

  const token = String(body.token ?? "").trim();
  if (!token) return json({ error: "Missing token" }, 400);

  const { data, error } = await admin.rpc("get_order_tracking", {
    p_token: token,
  });
  if (error) return json({ error: error.message }, 500);

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return json({ error: "Invalid or expired link" }, 404);

  return json({
    orderRef: row.order_ref,
    customer: row.cust_name,
    fromCity: row.from_city,
    toCity: row.to_city,
    moveDate: row.move_date,
    status: row.current_status,
    trackingStage: row.tracking_stage,
    orgName: row.org_name,
    crew: row.show_crew
      ? {
        vehicle: row.crew_vehicle,
        driver: row.crew_driver,
        phone: row.crew_phone,
      }
      : null,
    history: row.history ?? [],
  });
});
