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
// trial_ends_at and plan_status (16 Aug 2026): the note that used to be
// here said not to expose these preemptively — overtaken now that
// tenant_detail_page.dart has a real trial-day control (a date picker
// plus a "+14 days" quick action) and needs somewhere to write it. Same
// shape as plan_id/active: optional, independent, only the fields
// actually sent get written, each diffed against the prior row for its
// own billing_events entry. No UI writes plan_status yet — accepted here
// per instruction, for whatever manual override control gets built next.
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
    const { org_id, plan_id, active, trial_ends_at, plan_status } =
      await req.json();
    if (!org_id) {
      return json({ error: "org_id is required" }, 400);
    }
    const hasPlanChange = plan_id !== undefined;
    const hasActiveChange = active !== undefined;
    const hasTrialChange = trial_ends_at !== undefined;
    const hasPlanStatusChange = plan_status !== undefined;
    if (!hasPlanChange && !hasActiveChange && !hasTrialChange && !hasPlanStatusChange) {
      return json(
        { error: "plan_id, active, trial_ends_at and/or plan_status is required" },
        400,
      );
    }
    if (hasPlanChange && typeof plan_id !== "string") {
      return json({ error: "plan_id must be a string" }, 400);
    }
    if (hasActiveChange && typeof active !== "boolean") {
      return json({ error: "active must be a boolean" }, 400);
    }
    if (
      hasTrialChange &&
      (typeof trial_ends_at !== "string" || isNaN(Date.parse(trial_ends_at)))
    ) {
      return json({ error: "trial_ends_at must be a valid ISO date string" }, 400);
    }
    if (hasPlanStatusChange && typeof plan_status !== "string") {
      return json({ error: "plan_status must be a string" }, 400);
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
      .select("id, name, plan_id, active, trial_ends_at, plan_status")
      .eq("id", org_id)
      .maybeSingle();
    if (orgErr) return json({ error: "Lookup failed" }, 500);
    if (!orgRow) return json({ error: "Organization not found" }, 404);

    // ---- The write. Only the fields the caller actually asked to
    // change go in the payload — never a full-row send.
    const updatePayload: Record<string, unknown> = {};
    if (hasPlanChange) updatePayload.plan_id = plan_id;
    if (hasActiveChange) updatePayload.active = active;
    if (hasTrialChange) updatePayload.trial_ends_at = trial_ends_at;
    if (hasPlanStatusChange) updatePayload.plan_status = plan_status;

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
    if (hasTrialChange && trial_ends_at !== orgRow.trial_ends_at) {
      events.push({
        org_id,
        event_type: "trial_extended",
        detail: {
          from: orgRow.trial_ends_at,
          to: trial_ends_at,
          changed_by: caller.user.id,
        },
      });
    }
    if (hasPlanStatusChange && plan_status !== orgRow.plan_status) {
      events.push({
        org_id,
        event_type: "plan_status_changed",
        detail: {
          from: orgRow.plan_status,
          to: plan_status,
          changed_by: caller.user.id,
        },
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
      trial_ends_at: hasTrialChange ? trial_ends_at : orgRow.trial_ends_at,
      plan_status: hasPlanStatusChange ? plan_status : orgRow.plan_status,
    });
  } catch (e) {
    console.error("admin-update-org:", e);
    return json({ error: "Unexpected error" }, 500);
  }
});
