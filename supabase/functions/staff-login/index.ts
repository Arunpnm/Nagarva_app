// ============================================================
// supabase/functions/staff-login/index.ts
//
// Staff PIN login — server side.
// Flow:
//   1. Verify PIN via verify_staff_pin() RPC (bcrypt, in Postgres)
//   2. First login: create shadow auth user for the staff member,
//      link staff.auth_user_id, insert org_members row (RLS anchor)
//   3. Refresh app_metadata.staff_role (every login, not just first —
//      see the comment further down) then mint a REAL Supabase session
//      via admin.generateLink(magiclink) -> verifyOtp(token_hash)
//   4. Return tokens; Flutter calls supabase.auth.setSession()
//
// Result: staff sessions carry a genuine auth.uid(), so
// current_org_ids() and every org_isolation RLS policy work
// for staff exactly like they do for vendors.
//
// 17 Aug 2026: staff_role moved from user_metadata to app_metadata (was
// never actually read for an authorization decision, but user_metadata
// is client-writable via supabase.auth.updateUser() — a staff member
// could otherwise self-escalate by just setting it themselves. Item 30's
// branch-scoping RLS reads role/branch live from `staff` on every check
// (current_staff_role()/current_staff_branch()), not from this claim —
// app_metadata.staff_role exists only for the client's own UI-preset
// convenience, so it doesn't need to be perfectly fresh; it's refreshed
// on every login regardless (cheap, and self-heals the 3 shadow users
// that already existed before this change with no app_metadata at all).
//
// Deploy:  supabase functions deploy staff-login
// (or paste into Dashboard > Edge Functions > New Function)
// No extra secrets needed — SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY are injected automatically.
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

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

// Deterministic internal email per staff member (never sent mail)
function staffEmail(staffId: string): string {
  return `staff-${staffId}@staff.nagarva.in`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { staff_id, pin } = await req.json();

    if (!staff_id || !pin) {
      return json({ error: "staff_id and pin are required" }, 400);
    }

    // ---- 1. Verify PIN (bcrypt compare happens inside Postgres) ----
    const { data: rows, error: vErr } = await admin.rpc("verify_staff_pin", {
      p_staff_id: staff_id,
      p_pin: String(pin),
    });
    if (vErr) {
      console.error("verify_staff_pin error:", vErr.message);
      return json({ error: "Verification failed" }, 500);
    }

    const v = rows?.[0];
    if (!v) return json({ error: "Staff not found or inactive" }, 401);
    if (!v.ok) {
      // 20260725_staff_pin_rate_limit.sql: verify_staff_pin tracks failed
      // attempts and locks out after 5, atomically in Postgres so
      // concurrent requests can't race the counter. Since 20260819 the
      // lock escalates 15 min -> 1 hour -> 24 hours instead of resetting.
      if (v.locked) {
        const until = v.locked_until
          // timeZone is REQUIRED, not cosmetic. Deno Deploy runs UTC, so
          // toLocaleTimeString without it renders a UTC clock time in an
          // Indian locale format — 5.5 hours early. A locked-out vendor
          // reads "try again after 06:27 pm" when the lock actually ends
          // at 11:57 pm, retries immediately, escalates their own lock
          // from 15 minutes to an hour, and concludes the app is broken.
          // This string is the ONLY instruction a locked-out user gets.
          ? new Date(v.locked_until).toLocaleTimeString("en-IN", {
              hour: "2-digit",
              minute: "2-digit",
              timeZone: "Asia/Kolkata",
            })
          : null;
        return json({
          error: until
            ? `Too many failed attempts. Try again after ${until}.`
            : "Too many failed attempts. Try again later.",
        }, 429);
      }
      return json({ error: "Invalid PIN" }, 401);
    }

    const email = staffEmail(staff_id);
    let authUserId: string | null = v.auth_user_id;

    // ---- 2. First login: create shadow auth user + org link ----
    if (!authUserId) {
      const { data: created, error: cErr } = await admin.auth.admin.createUser(
        {
          email,
          email_confirm: true,
          // staff_role is NOT here — see the header comment. It's set
          // via app_metadata below, unconditionally, for both a
          // brand-new shadow user and one that already existed.
          user_metadata: {
            kind: "staff",
            staff_id,
            org_id: v.org_id,
            name: v.name,
          },
        },
      );

      if (cErr) {
        // User may already exist from a previous partial run — find it
        const { data: list, error: lstErr } = await admin.auth.admin
          .listUsers({ page: 1, perPage: 1000 });
        if (lstErr) return json({ error: lstErr.message }, 500);
        const existing = list.users.find((u) => u.email === email);
        if (!existing) return json({ error: cErr.message }, 500);
        authUserId = existing.id;
      } else {
        authUserId = created.user.id;
      }

      // Link staff row -> auth user
      const { error: updErr } = await admin
        .from("staff")
        .update({ auth_user_id: authUserId })
        .eq("id", staff_id);
      if (updErr) return json({ error: updErr.message }, 500);

      // org_members row = the RLS anchor (current_org_ids())
      const { data: existingMember } = await admin
        .from("org_members")
        .select("id")
        .eq("org_id", v.org_id)
        .eq("user_id", authUserId)
        .maybeSingle();

      if (!existingMember) {
        const { error: memErr } = await admin.from("org_members").insert({
          org_id: v.org_id,
          user_id: authUserId,
          role: "staff",
        });
        if (memErr) return json({ error: memErr.message }, 500);
      }
    }

    // ---- Refresh app_metadata.staff_role, every login (not just the
    // first) — see header comment. Best-effort: a failure here must not
    // block login, since nothing security-relevant depends on this
    // value being fresh.
    const { error: metaErr } = await admin.auth.admin.updateUserById(
      authUserId,
      { app_metadata: { staff_role: v.role } },
    );
    if (metaErr) {
      console.error("app_metadata refresh failed:", metaErr.message);
    }

    // ---- 3. Mint a real session for the shadow user ----
    const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkErr) return json({ error: linkErr.message }, 500);

    const tokenHash = link.properties?.hashed_token;
    if (!tokenHash) return json({ error: "Could not generate session" }, 500);

    const anonClient = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: otp, error: otpErr } = await anonClient.auth.verifyOtp({
      type: "email",
      token_hash: tokenHash,
    });
    if (otpErr || !otp.session) {
      return json({ error: otpErr?.message ?? "Session mint failed" }, 500);
    }

    // ---- 4. Return tokens + staff profile ----
    return json({
      access_token: otp.session.access_token,
      refresh_token: otp.session.refresh_token,
      staff: {
        id: staff_id,
        name: v.name,
        role: v.role,
        org_id: v.org_id,
        auth_user_id: authUserId,
      },
    });
  } catch (e) {
    console.error("staff-login unhandled:", e);
    return json({ error: "Unexpected error" }, 500);
  }
});
