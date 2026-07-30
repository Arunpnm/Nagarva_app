// ============================================================
// supabase/functions/staff-deactivate/index.ts
//
// Auth plan REVISED, build-order item 1: "Staff session revoke on
// deactivation — live exposure, smallest fix."
//
// THE EXPOSURE: staff use their own personal phones. When a supervisor
// leaves, that phone walks out of the business still holding a valid
// session. Setting `staff.active = false` does NOT help on its own —
// staff-login only checks active status AT LOGIN, so an already-minted
// JWT keeps working until it expires. The leaver keeps full access to
// their orders, customer contacts and job history for the life of that
// token.
//
// This function makes deactivation and revocation ONE operation. The app
// previously wrote `active: false` straight from staff_form_sheet, which
// could never revoke anything: the anon/authenticated client has no
// admin API. Doing it here also removes the failure mode where the app
// deactivates, then a separate revoke call fails, leaving a deactivated
// staff member with a live session and nobody aware.
//
// ORDER MATTERS: deactivate FIRST, then sign out. If the sign-out fails
// the row is still deactivated, so the next login attempt is refused and
// the exposure is bounded by token lifetime rather than being unbounded.
// Signing out first would leave a window where the token is dead but the
// row is still active, and a retry would just mint a fresh session.
//
// Deploy:  supabase functions deploy staff-deactivate
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
    const { staff_id, active } = await req.json();
    if (!staff_id || typeof active !== "boolean") {
      return json({ error: "staff_id and active (boolean) are required" }, 400);
    }

    // ---- Caller must be a real, signed-in owner of THAT staff member's
    // org. This runs with the service role, so without this check anyone
    // holding the anon key could deactivate any staff member in any
    // tenant. The service role bypasses RLS entirely — the authorisation
    // has to be explicit here.
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Not authorised" }, 401);

    const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !caller?.user) {
      return json({ error: "Not authorised" }, 401);
    }

    const { data: staffRow, error: staffErr } = await admin
      .from("staff")
      .select("id, org_id, auth_user_id, name")
      .eq("id", staff_id)
      .maybeSingle();
    if (staffErr) {
      console.error("staff lookup:", staffErr.message);
      return json({ error: "Lookup failed" }, 500);
    }
    if (!staffRow) return json({ error: "Staff member not found" }, 404);

    // Owner of that specific org, not merely a member of some org.
    const { data: membership, error: memErr } = await admin
      .from("org_members")
      .select("role")
      .eq("org_id", staffRow.org_id)
      .eq("user_id", caller.user.id)
      .maybeSingle();
    if (memErr) {
      console.error("membership lookup:", memErr.message);
      return json({ error: "Lookup failed" }, 500);
    }
    if (!membership || membership.role !== "owner") {
      return json({ error: "Only the owner can do this" }, 403);
    }

    // Refuse to let an owner deactivate themselves out of their own app.
    if (staffRow.auth_user_id && staffRow.auth_user_id === caller.user.id) {
      return json({ error: "You cannot deactivate your own account" }, 400);
    }

    // ---- 1. Flip the row. See ORDER MATTERS in the header.
    const { error: updErr } = await admin
      .from("staff")
      .update({ active })
      .eq("id", staff_id)
      .eq("org_id", staffRow.org_id);
    if (updErr) {
      console.error("staff update:", updErr.message);
      return json({ error: "Could not update staff member" }, 500);
    }

    // ---- 2. Kill live sessions, but only when deactivating.
    // Re-activating must NOT sign anyone out.
    let revoked = false;
    let revokeError: string | null = null;
    if (!active && staffRow.auth_user_id) {
      const { error: soErr } = await admin.auth.admin.signOut(
        staffRow.auth_user_id,
        "global",
      );
      if (soErr) {
        // Reported, NOT thrown. The row is already deactivated, so login
        // is refused from here on and the residual exposure is bounded by
        // the existing token's lifetime. Failing the whole call would
        // leave the caller thinking nothing happened, and they would very
        // likely just retry — which changes nothing — instead of chasing
        // the phone.
        revokeError = soErr.message;
        console.error("signOut failed for", staffRow.auth_user_id, soErr.message);
      } else {
        revoked = true;
      }
    }

    return json({
      ok: true,
      staff_id,
      active,
      // false with no error means the staff member never had an auth user
      // (they have never logged in), so there was nothing to revoke.
      sessions_revoked: revoked,
      revoke_error: revokeError,
      had_auth_user: Boolean(staffRow.auth_user_id),
    });
  } catch (e) {
    console.error("staff-deactivate:", e);
    return json({ error: "Unexpected error" }, 500);
  }
});
