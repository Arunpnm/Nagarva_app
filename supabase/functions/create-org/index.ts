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
// ============================================================
// DEPLOY ORDER — owner_name (12 Aug 2026, NG-BRIEF-vendor-auth-flow.md §3
// follow-up). This file now sends a 5th RPC argument, p_owner_name.
// DO NOT DEPLOY THIS until 20260812_owner_name_persistence.sql has been
// run and confirmed live (see that migration's own header for the
// verification query). If this deploys first, every signup breaks
// immediately: the live create_org_with_owner() would still only have
// the 4-argument signature, Postgres has no matching overload for a
// 5-argument call, and the RPC fails outright — not a graceful
// degradation, a hard error on every single signup until the migration
// catches up. Order: migration first, THEN
// `supabase functions deploy create-org`, THEN confirm with a real
// signup (see the migration's own verify section).
// ============================================================
// DEPLOY ORDER — invite-code gate (16 Aug 2026, closed beta ahead of
// Item 12). Same rule again: this file now reads/writes the
// `invite_codes`/`platform_settings` tables. DO NOT DEPLOY until
// 20260816_invite_codes.sql has been run — otherwise every signup 500s
// on missing tables instead of gracefully degrading either way. Order:
// migration first, THEN deploy, THEN confirm with a real signup using a
// seeded code.
//
// TURNING THE GATE OFF (Item 12 ships): update the DB row, not a
// secret (changed 17 Aug 2026 — is_invite_code_valid, the anon-callable
// pre-check RPC signup_page_widget.dart calls before auth.signUp(),
// needs to read the same flag this function does, and Postgres can't
// read a Deno Edge Function secret):
//   update platform_settings set value = 'false'::jsonb
//     where key = 'signup_requires_invite';
// No redeploy of this function needed — it's read fresh on every
// request. Missing row, or any value other than the JSON boolean
// `true`, keeps the gate ON (fails closed).
// ============================================================
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
    // owner_name: optional here at the HTTP layer even though
    // signup_page_widget.dart's form requires it — this endpoint is also
    // hit by login_page_widget.dart's §2 recovery path, where an
    // old-format account may have no owner_name in its auth metadata at
    // all (see that file's own comment on metaOwnerName). null is a valid,
    // expected input, not a validation failure.
    const ownerName = typeof body.owner_name === "string" ? body.owner_name.trim() : null;
    const inviteCode = typeof body.invite_code === "string" ? body.invite_code.trim() : "";

    // ---- Closed-beta gate (16 Aug 2026): signup is live but the CFT
    // catalogue is still APC-shaped, so every new tenant today gets a
    // product that doesn't fit their business. Gated here, not on
    // auth.signUp() itself — a user can still create+confirm a Supabase
    // Auth account without a code; what a missing/invalid code blocks is
    // finishing org bootstrap, so they never get an org/org_members row
    // and the app has nowhere to land them.
    //
    // Skipped entirely for a caller who already has an org — this is the
    // idempotent-retry path (a confirmation-gap recovery, or a plain
    // double-call) reusing this same endpoint for someone already
    // onboarded; re-demanding a code here would incorrectly lock out a
    // legitimate existing user if the code they used has since been
    // exhausted or deactivated.
    // Single source of truth for the on/off flag — `platform_settings`,
    // not an Edge Function secret (changed 17 Aug 2026): the signup-time
    // pre-check RPC (is_invite_code_valid) needs to read the same flag
    // and Postgres can't read a Deno secret, so this reads what that RPC
    // reads instead of duplicating the flag in two places that could
    // drift. Missing row = fail closed, same as the RPC.
    const { data: settingRow } = await admin
      .from("platform_settings")
      .select("value")
      .eq("key", "signup_requires_invite")
      .maybeSingle();
    const requiresInvite = settingRow ? settingRow.value === true : true;

    let inviteCodeToConsume: string | null = null;
    let inviteCodeUsedCount = 0;
    if (requiresInvite) {
      const { data: existingMember } = await admin
        .from("org_members")
        .select("id")
        .eq("user_id", caller.user.id)
        .limit(1)
        .maybeSingle();

      if (!existingMember) {
        if (!inviteCode) {
          return json({
            error:
              "Nagarva is currently in closed beta. Enter your invite code to continue, or contact us for access.",
          }, 403);
        }
        const { data: codeRow, error: codeErr } = await admin
          .from("invite_codes")
          .select("code, active, max_uses, used_count, expires_at")
          .eq("code", inviteCode)
          .maybeSingle();
        if (codeErr) {
          console.error("invite_codes lookup:", codeErr.message);
          return json({ error: "Could not verify invite code. Please try again." }, 500);
        }
        const notExpired = !codeRow?.expires_at ||
          new Date(codeRow.expires_at) > new Date();
        const valid = codeRow && codeRow.active && notExpired &&
          (codeRow.max_uses == null || codeRow.used_count < codeRow.max_uses);
        if (!valid) {
          return json({
            error: "That invite code is invalid or has already been used.",
          }, 403);
        }
        // Consumed AFTER create_org_with_owner succeeds below, not here —
        // a code shouldn't burn a use for an org creation that then fails
        // (e.g. slug exhaustion) and gets retried.
        inviteCodeToConsume = inviteCode;
        inviteCodeUsedCount = codeRow!.used_count;
      }
    }

    // ---- The atomic write. ----
    const { data: rows, error: rpcErr } = await admin.rpc(
      "create_org_with_owner",
      {
        p_user_id: caller.user.id,
        p_org_name: orgName,
        p_phone: phone,
        p_gstin: gstin,
        p_owner_name: ownerName,
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

    // ---- Consume the invite code now that the org actually exists.
    // Best-effort: the org is already created successfully at this point,
    // so a failure to increment the usage counter must not fail the
    // whole request over bookkeeping. Plain read-then-write, not atomic —
    // a race between two signups on the same code at the exact same
    // instant could both pass and over-consume by one; acceptable for a
    // small, manually-managed closed beta, not worth a migration for an
    // atomic RPC just for this. ----
    if (inviteCodeToConsume) {
      const { error: incErr } = await admin
        .from("invite_codes")
        .update({
          used_count: inviteCodeUsedCount + 1,
          // Only set on first use — a code can outlive a single org (see
          // max_uses), so this stays whichever org used it first rather
          // than being overwritten on a later use.
          ...(inviteCodeUsedCount === 0 ? { used_by_org_id: row.org_id } : {}),
        })
        .eq("code", inviteCodeToConsume);
      if (incErr) {
        console.error("invite_codes increment:", incErr.message);
      }
    }

    // ---- Shape the response for signup_page_widget.dart's
    // AppSession.instance.setVendorSession(), read directly from
    // lib/app_session.dart this session rather than assumed:
    //   authUserId, orgId, orgName, orgSlug, limits, features,
    //   planName, planStatus, trialEndsAt, orgActive
    // authUserId is not returned here - the client already has it, it's
    // whoever it just authenticated as.
    //
    // caller_role IS THE FIELD THE CLIENT MUST GATE ON, not is_new. A
    // staff/manager member at someone else's org hitting this endpoint
    // also gets is_new=false - identical to a genuine signup retry on
    // that field alone. Only caller_role distinguishes them. Step 3 (the
    // signup_page_widget.dart rewrite, not yet built) must call
    // setVendorSession() only when caller_role === 'owner', checked as
    // its own standalone condition - never compounded with is_new, so
    // there is no flag combination that lets a non-owner through.
    return json({
      ok: true,
      is_new: row.is_new,
      // The SQL function already normalises this to lowercase (org_members.role
      // has no CHECK constraint enforcing casing at the DB level pre-31 Jul,
      // and 20260731_org_members_role_check.sql only constrains rows written
      // AFTER it runs, not retroactively). Lower-cased again here anyway -
      // free, and this is the exact value step 3 will do `=== 'owner'` against,
      // so it costs nothing to not depend on a single layer for that.
      caller_role:
        typeof row.caller_role === "string" ? row.caller_role.toLowerCase() : row.caller_role,
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
