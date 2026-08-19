// ============================================================
// supabase/functions/pin-login/index.ts
//
// Parity brief Part 7 — unified PIN login. The device is already bound to
// one org (see lib/backend/device_org_binding.dart); this function takes
// just {org_id, pin} — no name/phone/email — and checks both the owner
// and staff pools via the verify_org_pin() RPC (20260728_org_pin_login.sql).
//
// Two outcomes on a match:
//   - kind === 'owner': mint a session for the OWNER'S OWN pre-existing
//     Supabase Auth account (org_members.user_id). No shadow user is
//     created — this was a deliberate design decision (see the SQL
//     migration's header) so every existing owner-only permission check
//     in the app keeps working unchanged.
//   - kind === 'staff': same shadow-user flow as the existing
//     staff-login function (create on first PIN login, link
//     staff.auth_user_id, ensure an org_members row exists).
//
// Both outcomes mint a REAL Supabase session the same way: admin
// .generateLink(magiclink) -> anon client verifyOtp(token_hash). The
// existing staff-login function is untouched — this is a separate
// function so the new org-wide PIN pool (no staff_id known up front)
// can't affect that already-working, already-tested path.
//
// 17 Aug 2026: staff_role moved from user_metadata to app_metadata on
// the staff branch — same fix, same reasoning as staff-login/index.ts's
// own header comment (user_metadata is client-writable via
// supabase.auth.updateUser(), so anything an authorization decision
// might read must not live there). The owner branch is untouched — it
// mints a session for the owner's own pre-existing account and never
// carries a staff_role claim at all.
//
// Deploy:  supabase functions deploy pin-login
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

// Same deterministic internal email scheme as staff-login/index.ts —
// never actually sent mail, just an anchor for the shadow auth user.
function staffEmail(staffId: string): string {
  return `staff-${staffId}@staff.nagarva.in`;
}

async function mintSession(email: string) {
  const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (linkErr) return { error: linkErr.message };

  const tokenHash = link.properties?.hashed_token;
  if (!tokenHash) return { error: "Could not generate session" };

  const anonClient = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: otp, error: otpErr } = await anonClient.auth.verifyOtp({
    type: "email",
    token_hash: tokenHash,
  });
  if (otpErr || !otp.session) {
    return { error: otpErr?.message ?? "Session mint failed" };
  }
  return { session: otp.session };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { org_id, pin } = await req.json();
    if (!org_id || !pin) {
      return json({ error: "org_id and pin are required" }, 400);
    }

    // Rate limiting is per (org, source IP) as of 20260819. The IP MUST be
    // forwarded explicitly: verify_org_pin also reads PostgREST's
    // `request.headers` GUC as a fallback, but this call arrives there
    // under service_role from inside an Edge Function, so that GUC would
    // carry THIS function's outbound IP — every tenant on the platform
    // sharing a single bucket, a limiter that reports success while
    // enforcing nothing.
    //
    // NOTE on trust: x-forwarded-for is a client-settable header, and we
    // take the first entry (the conventional "original client" position).
    // If Supabase's edge proxy appends rather than replaces, a caller can
    // put any value in front of the real one and get a fresh bucket per
    // request. That does not reopen the tenant-wide lockout that this
    // work closed — the per-pool backstop is set at 50 and is the only
    // org-wide lock left — but it does weaken the per-IP limiter. Being
    // verified empirically before this is relied on; see
    // supabase/20260819_pin_rate_limit_hardening.sql.
    const clientIp =
      (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null;

    const { data: rows, error: vErr } = await admin.rpc("verify_org_pin", {
      p_org_id: org_id,
      p_pin: String(pin),
      p_client_ip: clientIp,
    });
    if (vErr) {
      console.error("verify_org_pin error:", vErr.message);
      return json({ error: "Verification failed" }, 500);
    }

    const v = rows?.[0];
    if (!v || !v.ok) {
      if (v?.locked) {
        const until = v.locked_until
          ? new Date(v.locked_until).toLocaleTimeString("en-IN", {
              hour: "2-digit",
              minute: "2-digit",
            })
          : null;
        return json({
          error: until
            ? `Too many failed attempts. Try again after ${until}.`
            : "Too many failed attempts. Try again later.",
        }, 429);
      }
      return json({ error: "Wrong PIN. Try again." }, 401);
    }

    // ---- Owner match: mint a session for their REAL existing account ----
    if (v.kind === "owner") {
      const { data: userRes, error: getErr } = await admin.auth.admin
        .getUserById(v.user_id);
      if (getErr || !userRes?.user?.email) {
        return json({ error: "Owner account not found" }, 500);
      }
      const minted = await mintSession(userRes.user.email);
      if ("error" in minted) return json({ error: minted.error }, 500);
      return json({
        kind: "owner",
        access_token: minted.session.access_token,
        refresh_token: minted.session.refresh_token,
      });
    }

    // ---- Staff match: same shadow-user flow as staff-login/index.ts ----
    const staffId = v.staff_id as string;
    const email = staffEmail(staffId);
    let authUserId: string | null = v.staff_auth_user_id;

    if (!authUserId) {
      const { data: created, error: cErr } = await admin.auth.admin
        .createUser({
          email,
          email_confirm: true,
          // staff_role is NOT here — see the header comment. Set via
          // app_metadata below instead, unconditionally.
          user_metadata: {
            kind: "staff",
            staff_id: staffId,
            org_id,
            name: v.staff_name,
          },
        });

      if (cErr) {
        const { data: list, error: lstErr } = await admin.auth.admin
          .listUsers({ page: 1, perPage: 1000 });
        if (lstErr) return json({ error: lstErr.message }, 500);
        const existing = list.users.find((u) => u.email === email);
        if (!existing) return json({ error: cErr.message }, 500);
        authUserId = existing.id;
      } else {
        authUserId = created.user.id;
      }

      const { error: updErr } = await admin.from("staff")
        .update({ auth_user_id: authUserId }).eq("id", staffId);
      if (updErr) return json({ error: updErr.message }, 500);

      const { data: existingMember } = await admin.from("org_members")
        .select("id").eq("org_id", org_id).eq("user_id", authUserId)
        .maybeSingle();
      if (!existingMember) {
        const { error: memErr } = await admin.from("org_members").insert({
          org_id,
          user_id: authUserId,
          role: "staff",
        });
        if (memErr) return json({ error: memErr.message }, 500);
      }
    }

    // Refresh app_metadata.staff_role, every login — see header comment.
    // Best-effort: must not block login.
    const { error: metaErr } = await admin.auth.admin.updateUserById(
      authUserId,
      { app_metadata: { staff_role: v.staff_role } },
    );
    if (metaErr) {
      console.error("app_metadata refresh failed:", metaErr.message);
    }

    const minted = await mintSession(email);
    if ("error" in minted) return json({ error: minted.error }, 500);
    return json({
      kind: "staff",
      access_token: minted.session.access_token,
      refresh_token: minted.session.refresh_token,
      staff: {
        id: staffId,
        name: v.staff_name,
        role: v.staff_role,
        org_id,
        auth_user_id: authUserId,
      },
    });
  } catch (e) {
    console.error("pin-login unhandled:", e);
    return json({ error: "Unexpected error" }, 500);
  }
});
