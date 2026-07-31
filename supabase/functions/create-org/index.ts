// ============================================================
// supabase/functions/create-org/index.ts
//
// Registration brief, step 2. Bootstraps an org for a just-registered
// vendor, calling create_org_with_owner() (20260731_create_org_with_owner.sql)
// via RPC under the service role.
//
// WHEN THE CLIENT CALLS THIS: immediately after obtaining a fresh,
// authenticated session with no org yet — which happens either right
// after signUp() (while "Confirm email" is OFF, signUp() returns a
// session directly) or after the user clicks the email verification link
// and the deep link hands the client a session (once "Confirm email" is
// ON, signUp() returns session: null until then). This function does not
// need to know or care which case it is: by the time a valid JWT reaches
// it, Supabase Auth has already decided the caller is real. No
// email-confirmation-specific branching lives here.
//
// SAME AUTHORISATION PATTERN as staff-deactivate / staff-invite: the
// caller's identity is taken ONLY from the verified Authorization header,
// never from the request body. A request body user_id would let anyone
// holding the anon key create an org "owned by" an arbitrary uuid.
//
// ATOMICITY lives entirely in the SQL function, not here — see
// 20260731_create_org_with_owner.sql's header. This file's only job is:
// verify the JWT, validate input shape, call the RPC, shape the HTTP
// response.
//
// Deploy:  supabase functions deploy create-org
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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    // ---- 401: verified JWT required. Never trust a user_id in the body. ----
    const jwt = (req.headers.get("Authorization") ?? "").replace(
      /^Bearer\s+/i,
      "",
    );
    if (!jwt) return json({ error: "Not authorised" }, 401);

    const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !caller?.user) {
      return json({ error: "Not authorised" }, 401);
    }

    // ---- 400: validate the body. Only org_name is required; phone and
    // gstin are optional and null-coerced by the SQL function. ----
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return json({ error: "Invalid request body" }, 400);
    }
    const orgName = typeof body.org_name === "string" ? body.org_name.trim() : "";
    if (!orgName) {
      return json({ error: "org_name is required" }, 400);
    }
    if (orgName.length > 200) {
      return json({ error: "org_name is too long" }, 400);
    }
    const phone = typeof body.phone === "string" ? body.phone.trim() : null;
    const gstin = typeof body.gstin === "string" ? body.gstin.trim() : null;

    // ---- The atomic write. ----
    const { data: rows, error: rpcErr } = await admin.rpc(
      "create_org_with_owner",
      {
        p_user_id: caller.user.id,
        p_org_name: orgName,
        p_phone: phone,
        p_gstin: gstin,
      },
    );
    if (rpcErr) {
      console.error("create_org_with_owner:", rpcErr.message);
      // P0001 is this function's own raise exception calls (bad plan
      // config, slug generation exhausted) - genuinely our fault or a
      // config gap, not the caller's. Everything else is unexpected.
      return json({ error: "Could not create organisation" }, 500);
    }
    const row = Array.isArray(rows) ? rows[0] : rows;
    if (!row) {
      return json({ error: "Could not create organisation" }, 500);
    }

    // ---- Shape the response for signup_page_widget.dart's
    // AppSession.instance.setVendorSession(), read directly from
    // lib/app_session.dart this session rather than assumed:
    //   authUserId, orgId, orgName, orgSlug, limits, features,
    //   planName, planStatus, trialEndsAt, orgActive
    // authUserId is not returned here - the client already has it, it's
    // whoever it just authenticated as.
    return json({
      ok: true,
      is_new: row.is_new,
      org_id: row.org_id,
      org_name: row.org_name,
      org_slug: row.org_slug,
      plan_name: row.plan_name,
      plan_status: row.plan_status,
      limits: row.plan_limits ?? {},
      features: row.plan_features ?? {},
      trial_ends_at: row.trial_ends_at,
      org_active: row.org_active,
    }, row.is_new ? 201 : 200);
  } catch (e) {
    console.error("create-org:", e);
    return json({ error: "Unexpected error" }, 500);
  }
});
