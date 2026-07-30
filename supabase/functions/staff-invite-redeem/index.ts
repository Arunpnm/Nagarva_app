// ============================================================
// supabase/functions/staff-invite-redeem/index.ts
//
// Auth plan REVISED item 3 — the STAFF side of remote onboarding.
//
// Runs PRE-AUTH. The staff member has no session; that is the point. So
// this cannot go through RLS and instead runs under the service role with
// its own rate limiting.
//
// Takes {code, device_id} and, on success, returns the staff_id + org
// details the device needs to bind itself. It does NOT mint a session —
// the staff member still has to set/enter their PIN and go through
// staff-login. Redeeming an invite proves "this device belongs to this
// person"; the PIN proves "this is that person". Two separate facts, and
// collapsing them would mean a leaked code alone grants access.
//
// Deploy:  supabase functions deploy staff-invite-redeem
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

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(s),
  );
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const MAX_ATTEMPTS = 8;
const LOCK_MINUTES = 30;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { code, device_id } = await req.json();
    if (!code || !device_id) {
      return json({ error: "code and device_id are required", reason: "invalid" }, 400);
    }

    // ---- Rate limit per device. An 8-char code over a 32-char alphabet
    // is ~1.1e12 combinations, so this is not the primary defence — but
    // without any limit a script could grind, and there is no session to
    // attribute failures to.
    const { data: att } = await admin
      .from("invite_redeem_attempts")
      .select("failed_attempts, locked_until")
      .eq("device_id", device_id)
      .maybeSingle();

    if (att?.locked_until && new Date(att.locked_until) > new Date()) {
      return json(
        { error: "Too many attempts. Try again later.", reason: "locked" },
        429,
      );
    }

    const codeHash = await sha256(String(code).trim().toUpperCase());

    const { data: invite, error: invErr } = await admin
      .from("staff_invites")
      .select("id, org_id, staff_id, expires_at, used_at, revoked_at")
      .eq("code_hash", codeHash)
      .maybeSingle();
    if (invErr) {
      console.error("invite lookup:", invErr.message);
      return json({ error: "Lookup failed", reason: "network" }, 500);
    }

    // Distinct reasons for the four failure modes. A staff member holding
    // an expired code needs to be told to ask for a new one, not "invalid"
    // — the difference is a phone call either way, but only one of them
    // ends with them knowing what to do.
    if (!invite) {
      await bumpFailure(device_id, att?.failed_attempts ?? 0);
      return json({ error: "That code is not valid.", reason: "not_found" }, 404);
    }
    if (invite.revoked_at) {
      return json(
        { error: "That code was cancelled. Ask for a new one.", reason: "revoked" },
        410,
      );
    }
    if (invite.used_at) {
      return json(
        { error: "That code has already been used.", reason: "already_used" },
        410,
      );
    }
    if (new Date(invite.expires_at) < new Date()) {
      return json(
        { error: "That code has expired. Ask for a new one.", reason: "expired" },
        410,
      );
    }

    // ---- Claim it. Conditional on still being unused, so two devices
    // racing the same code cannot both succeed — whichever UPDATE matches
    // first wins and the other sees zero rows.
    const { data: claimed, error: claimErr } = await admin
      .from("staff_invites")
      .update({
        used_at: new Date().toISOString(),
        used_by_device: String(device_id).slice(0, 200),
      })
      .eq("id", invite.id)
      .is("used_at", null)
      .is("revoked_at", null)
      .select("id");
    if (claimErr) {
      console.error("invite claim:", claimErr.message);
      return json({ error: "Could not redeem", reason: "network" }, 500);
    }
    if (!claimed || claimed.length === 0) {
      return json(
        { error: "That code has already been used.", reason: "already_used" },
        410,
      );
    }

    // ---- Everything the device needs to bind itself to this person.
    const { data: staffRow } = await admin
      .from("staff")
      .select("id, name, role, active")
      .eq("id", invite.staff_id)
      .maybeSingle();
    const { data: org } = await admin
      .from("organizations")
      .select("id, name, slug")
      .eq("id", invite.org_id)
      .maybeSingle();

    if (!staffRow || staffRow.active === false) {
      return json(
        { error: "That account is not active. Contact your owner.", reason: "inactive" },
        403,
      );
    }

    // Clear the device's failure counter on success.
    await admin.from("invite_redeem_attempts").upsert({
      device_id,
      failed_attempts: 0,
      locked_until: null,
      updated_at: new Date().toISOString(),
    });

    return json({
      ok: true,
      staff_id: staffRow.id,
      staff_name: staffRow.name,
      staff_role: staffRow.role,
      org_id: org?.id,
      org_name: org?.name,
      org_slug: org?.slug,
      // No session and no PIN here on purpose — see the header.
    });
  } catch (e) {
    console.error("staff-invite-redeem:", e);
    return json({ error: "Unexpected error", reason: "network" }, 500);
  }
});

async function bumpFailure(deviceId: string, current: number) {
  const next = current + 1;
  const locked = next >= MAX_ATTEMPTS;
  await admin.from("invite_redeem_attempts").upsert({
    device_id: deviceId,
    failed_attempts: locked ? 0 : next,
    locked_until: locked
      ? new Date(Date.now() + LOCK_MINUTES * 60_000).toISOString()
      : null,
    updated_at: new Date().toISOString(),
  });
}
