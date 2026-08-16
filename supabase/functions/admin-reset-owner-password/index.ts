// ============================================================
// supabase/functions/admin-reset-owner-password/index.ts
//
// Super Admin console — vendor management, reset-password only (16 Aug
// 2026). A platform admin, from Tenant Detail, triggers a password-reset
// EMAIL for a tenant's owner — never a temp password read back to the
// admin and handed off manually, per instruction. Add/remove owner and
// "add another platform admin" are explicitly NOT built: the former
// wasn't asked for this pass, the latter is a deliberate SQL-only
// decision (one row in platform_admins is a full cross-tenant privilege
// escalation — not something to expose through app UI at all).
//
// WHY AN EDGE FUNCTION AND NOT A PLAIN CLIENT-SIDE
// auth.resetPasswordForEmail() CALL: that method is anon-callable by
// design (GoTrue always returns success regardless of whether the email
// exists, to prevent enumeration) — a Super Admin doesn't strictly need
// elevated privilege to fire it. But the admin console only has an
// org_id, not the owner's email with any confidence: tenant_detail_page's
// own get_org_owner_email RPC is defensive precisely because it may not
// exist live yet (supabase/20260727_super_admin_owner_email.sql).
// Resolving org_id -> owner email needs the service role (org_members
// join to auth.users), same reasoning as every other admin-* function in
// this app. Doing the resolution and the audit log server-side, gated on
// platform_admins, also means this is a real, attributable admin action —
// not indistinguishable from a random anon hitting /recover.
//
// EMAIL DELIVERY: GoTrue's admin API (admin.auth.admin.generateLink) can
// MINT a recovery link but does not itself dispatch an email — that's
// deliberately for callers handling delivery themselves. The one that
// actually sends Supabase's configured recovery email template is the
// public method, auth.resetPasswordForEmail(), on a plain (anon-key)
// client. This function creates a second, anon-key client for exactly
// that one call, after the service-role client has done the
// authorization check and the org_id -> email resolution.
//
// REDIRECT: explicitly nagarva.netlify.app, NOT the project's configured
// Site URL default. Confirmed live (16 Aug 2026 redirect-issue report)
// that Site URL / the app's own emailRedirectTo-less signUp() calls
// currently resolve to link.nagarva.in, a static site with no root page
// that 404s on every link. Hardcoding the known-working Flutter web
// build here avoids inheriting that same break for this specific flow.
// Requires https://nagarva.netlify.app to be present in Supabase's
// Redirect URLs allow-list — if it is not, GoTrue silently falls back to
// Site URL instead of rejecting the call, so this will look like it
// worked but still land the owner on the same broken page. Not
// independently verified from this session (no Dashboard access) — check
// this before relying on the reset link working end to end.
//
// AUTHORISATION: platform_admins membership, checked here under the
// service role — same pattern as admin-update-org.
//
// Deploy:  supabase functions deploy admin-reset-owner-password
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const RESET_REDIRECT_TO = "https://nagarva.netlify.app";

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

  try {
    const { org_id } = await req.json();
    if (!org_id || typeof org_id !== "string") {
      return json({ error: "org_id is required" }, 400);
    }

    // ---- Caller must be a real, signed-in platform admin. Same check as
    // admin-update-org: service role bypasses RLS, so authorisation has
    // to be explicit here rather than left to a policy.
    const jwt = (req.headers.get("Authorization") ?? "").replace(
      /^Bearer\s+/i,
      "",
    );
    if (!jwt) return json({ error: "Not authorised" }, 401);

    const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !caller?.user) return json({ error: "Not authorised" }, 401);

    const { data: adminRow, error: adminErr } = await admin
      .from("platform_admins")
      .select("user_id")
      .eq("user_id", caller.user.id)
      .maybeSingle();
    if (adminErr) return json({ error: "Lookup failed" }, 500);
    if (!adminRow) return json({ error: "Only a platform admin can do this" }, 403);

    // ---- Resolve the tenant's owner. create_org_with_owner() always
    // writes exactly one org_members row with role='owner' at org
    // creation (20260812_owner_name_persistence.sql's own body confirms
    // this literal value) — no later flow adds a second owner.
    const { data: ownerMember, error: memberErr } = await admin
      .from("org_members")
      .select("user_id")
      .eq("org_id", org_id)
      .eq("role", "owner")
      .limit(1)
      .maybeSingle();
    if (memberErr) return json({ error: "Lookup failed" }, 500);
    if (!ownerMember) {
      return json({ error: "This organization has no owner on record" }, 404);
    }

    const { data: ownerUser, error: ownerErr } =
      await admin.auth.admin.getUserById(ownerMember.user_id);
    if (ownerErr || !ownerUser?.user?.email) {
      return json({ error: "Could not resolve the owner's account" }, 500);
    }
    const ownerEmail = ownerUser.user.email;

    // ---- The actual email send. Deliberately the anon-key client, not
    // the service-role one — see header comment on why generateLink()
    // alone would mint a link but never dispatch anything.
    const anonClient = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error: resetErr } = await anonClient.auth.resetPasswordForEmail(
      ownerEmail,
      { redirectTo: RESET_REDIRECT_TO },
    );
    if (resetErr) {
      console.error("resetPasswordForEmail:", resetErr.message);
      return json({ error: "Could not send the reset email" }, 500);
    }

    // ---- Audit trail. Best-effort, same convention as admin-update-org —
    // does not fail the request if it errors.
    const { error: evErr } = await admin.from("billing_events").insert({
      org_id,
      event_type: "owner_password_reset_requested",
      detail: { owner_email: ownerEmail, requested_by: caller.user.id },
    });
    if (evErr) console.error("billing_events insert:", evErr.message);

    return json({ ok: true, email: ownerEmail });
  } catch (e) {
    console.error("admin-reset-owner-password:", e);
    return json({ error: "Unexpected error" }, 500);
  }
});
