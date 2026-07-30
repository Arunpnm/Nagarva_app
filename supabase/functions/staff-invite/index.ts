// ============================================================
// supabase/functions/staff-invite/index.ts
//
// Auth plan REVISED item 3 — the OWNER side of remote staff onboarding.
//
// Two actions on one function:
//   generate  -> mint a single-use code for a staff member, returning the
//                plaintext ONCE. Supersedes any existing live invite.
//   revoke    -> kill the outstanding invite for a staff member.
//
// The plaintext code is returned exactly once and never stored — only its
// sha256. An invite grants the ability to bind a device to a staff
// identity, so a leaked backup must not hand over working invites.
//
// Requires a signed-in OWNER of that staff member's org. This runs with
// the service role, which bypasses RLS entirely, so authorisation is
// explicit here — same reasoning as staff-deactivate.
//
// Deploy:  supabase functions deploy staff-invite
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

// Deliberately excludes I, O, 0, 1 — these get read aloud over the phone
// and typed on a small keyboard, and those four are where transcription
// errors come from. 32 chars ^ 8 is still ~1.1e12 combinations.
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generateCode(): string {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  // Rejection-free mapping is fine here: 256 % 32 === 0, so the modulo is
  // uniform across the alphabet with no bias.
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join("");
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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { action, staff_id, valid_days } = await req.json();
    if (!staff_id || (action !== "generate" && action !== "revoke")) {
      return json(
        { error: "staff_id and action ('generate' | 'revoke') are required" },
        400,
      );
    }

    // ---- Caller must be an owner of THAT staff member's org.
    const jwt = (req.headers.get("Authorization") ?? "").replace(
      /^Bearer\s+/i,
      "",
    );
    if (!jwt) return json({ error: "Not authorised" }, 401);

    const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
    if (callerErr || !caller?.user) return json({ error: "Not authorised" }, 401);

    const { data: staffRow, error: staffErr } = await admin
      .from("staff")
      .select("id, org_id, name, active")
      .eq("id", staff_id)
      .maybeSingle();
    if (staffErr) return json({ error: "Lookup failed" }, 500);
    if (!staffRow) return json({ error: "Staff member not found" }, 404);

    const { data: membership } = await admin
      .from("org_members")
      .select("role")
      .eq("org_id", staffRow.org_id)
      .eq("user_id", caller.user.id)
      .maybeSingle();
    if (!membership || membership.role !== "owner") {
      return json({ error: "Only the owner can do this" }, 403);
    }

    // ---- revoke -----------------------------------------------------
    if (action === "revoke") {
      const { error } = await admin
        .from("staff_invites")
        .update({ revoked_at: new Date().toISOString() })
        .eq("staff_id", staff_id)
        .eq("org_id", staffRow.org_id)
        .is("used_at", null)
        .is("revoked_at", null);
      if (error) return json({ error: "Could not revoke" }, 500);
      return json({ ok: true, revoked: true });
    }

    // ---- generate ---------------------------------------------------
    // An invite for a deactivated staff member would bind a device to an
    // identity that cannot log in — confusing, and a foot-gun if they are
    // later reactivated without anyone remembering the invite exists.
    if (staffRow.active === false) {
      return json(
        { error: "This staff member is deactivated. Reactivate them first." },
        400,
      );
    }

    // Supersede any live invite FIRST. The partial unique index allows only
    // one unused+unrevoked invite per staff member, so without this the
    // insert below would fail — and more importantly, an old code the owner
    // has forgotten about must stop working the moment a new one is issued.
    await admin
      .from("staff_invites")
      .update({ revoked_at: new Date().toISOString() })
      .eq("staff_id", staff_id)
      .is("used_at", null)
      .is("revoked_at", null);

    const days = Number.isFinite(valid_days) && valid_days > 0
      ? Math.min(Number(valid_days), 30)
      : 7;

    const code = generateCode();
    const codeHash = await sha256(code);
    const expiresAt = new Date(Date.now() + days * 86400_000).toISOString();

    const { error: insErr } = await admin.from("staff_invites").insert({
      org_id: staffRow.org_id,
      staff_id,
      code_hash: codeHash,
      code_hint: code.slice(0, 4),
      expires_at: expiresAt,
      created_by: caller.user.id,
    });
    if (insErr) {
      console.error("invite insert:", insErr.message);
      return json({ error: "Could not create invite" }, 500);
    }

    // The ONLY time the plaintext exists outside the owner's screen.
    return json({
      ok: true,
      code,
      staff_name: staffRow.name,
      expires_at: expiresAt,
    });
  } catch (e) {
    console.error("staff-invite:", e);
    return json({ error: "Unexpected error" }, 500);
  }
});
