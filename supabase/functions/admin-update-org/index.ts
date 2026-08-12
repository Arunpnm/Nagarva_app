// ============================================================
// supabase/functions/admin-update-org/index.ts
//
// RLS remediation Tier B (NG-BRIEF-rls-remediation.md §3 Tier B) — the
// legitimate replacement path for organizations.plan_id/active writes.
//
// WHY THIS EXISTS: Tier B's SQL migration revokes UPDATE (plan_id,
// plan_status, trial_ends_at, active) on `organizations` from
// `authenticated` entirely — "no app-side write at all," per the brief,
// because that row is Nagarva's own subscription/tenancy state, not
// tenant data. Before that migration can land, the two real live writers
// of those columns need a replacement:
//   - lib/super_admin_page/super_admin_page_widget.dart's _changePlan()
//     (writes plan_id)
//   - lib/super_admin_page/tenant_detail_page.dart's _toggleActive()
//     (writes active)
// Both are Super Admin (platform-operator) tools, not tenant-facing — the
// brief's suggestion to "coordinate with the Razorpay webhook work" turned
// out not to apply here: that work doesn't exist yet (org_subscriptions/
// billing_events/platform_invoices/org_usage are all live-but-empty, zero
// Dart references anywhere), and it wouldn't have been the right owner for
// this specific write anyway — a platform admin manually overriding a
// tenant's plan or suspending them is a distinct, already-built, already-
// used action from whatever a payment-gateway webhook will someday do.
//
// AUTHORISATION: platform_admins membership, checked here under the
// service role exactly like staff-deactivate/staff-invite check
// org_members.role — this is NOT an org_id-scoped check (the caller need
// not be a member of the target org at all, by design: super_admin_page's
// own header comment documents this as the one deliberate cross-tenant
// read path in the app).
//
// trial_ends_at and plan_status are NOT exposed here — no live Dart call
// site writes either today (grepped before writing this), so there is
// nothing to replace. If a "extend trial" or manual plan_status override
// UI is ever built, extend this function's body then, not preemptively.
//
// Deploy:  supabase functions deploy admin-update-org
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

  try {
    const { org_id, plan_id, active } = await req.json();
    if (!org_id) {
      return json({ error: "org_id is required" }, 400);
    }
    const hasPlanChange = plan_id !== undefined;
    const hasActiveChange = active !== undefined;
    if (!hasPlanChange && !hasActiveChange) {
      return json({ error: "plan_id and/or active is required" }, 400);
    }
    if (hasPlanChange && typeof plan_id !== "string") {
      return json({ error: "plan_id must be a string" }, 400);
    }
    if (hasActiveChange && typeof active !== "boolean") {
      return json({ error: "active must be a boolean" }, 400);
    }

    // ---- Caller must be a real, signed-in platform admin. Service role
    // bypasses RLS entirely, so — same reasoning as every other admin-*
    // function in this app — authorisation has to be explicit here rather
    // than left to a policy.
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

    const { data: orgRow, error: orgErr } = await admin
      .from("organizations")
      .select("id, name, plan_id, active")
      .eq("id", org_id)
      .maybeSingle();
    if (orgErr) return json({ error: "Lookup failed" }, 500);
    if (!orgRow) return json({ error: "Organization not found" }, 404);

    // ---- The write. Only the two fields the caller actually asked to
    // change go in the payload — never a full-row send.
    const updatePayload: Record<string, unknown> = {};
    if (hasPlanChange) updatePayload.plan_id = plan_id;
    if (hasActiveChange) updatePayload.active = active;

    const { error: updErr } = await admin
      .from("organizations")
      .update(updatePayload)
      .eq("id", org_id);
    if (updErr) {
      console.error("organizations update:", updErr.message);
      return json({ error: "Could not update organization" }, 500);
    }

    // ---- Audit trail. billing_events already exists live for exactly
    // this shape (org_id, event_type, detail jsonb) and has had zero
    // writers until now — best-effort, does not fail the request if it
    // errors, same convention as the notification writes in
    // supervisor_job_page_widget.dart's OTP-completion flow.
    const events: Array<{ org_id: string; event_type: string; detail: unknown }> = [];
    if (hasPlanChange && plan_id !== orgRow.plan_id) {
      events.push({
        org_id,
        event_type: "plan_changed",
        detail: { from: orgRow.plan_id, to: plan_id, changed_by: caller.user.id },
      });
    }
    if (hasActiveChange && active !== orgRow.active) {
      events.push({
        org_id,
        event_type: active ? "reactivated" : "suspended",
        detail: { from: orgRow.active, to: active, changed_by: caller.user.id },
      });
    }
    if (events.length > 0) {
      const { error: evErr } = await admin.from("billing_events").insert(events);
      if (evErr) console.error("billing_events insert:", evErr.message);
    }

    return json({
      ok: true,
      org_id,
      plan_id: hasPlanChange ? plan_id : orgRow.plan_id,
      active: hasActiveChange ? active : orgRow.active,
    });
  } catch (e) {
    console.error("admin-update-org:", e);
    return json({ error: "Unexpected error" }, 500);
  }
});
