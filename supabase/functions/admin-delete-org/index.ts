// ============================================================
// supabase/functions/admin-delete-org/index.ts
//
// Tenant deletion, end to end. THIS is the entry point — not the
// delete_org() RPC on its own.
//
// Arun, 18 Aug 2026: "A tenant delete that leaves the owner's email in
// auth.users hasn't erased anything that matters legally." The SQL
// function removes public-schema rows; this removes the two things SQL
// cannot reach:
//   1. Supabase Auth users — the owner(s) and every staff shadow user
//      (staff-<uuid>@staff.nagarva.in). **This is where the email address
//      lives**, so for a DPDP erasure request this is the part that
//      actually discharges the obligation.
//   2. Storage objects — org-logos/<org_id>/... and anything else stored
//      under the org's own prefix.
//
// ORDER MATTERS, and not in the obvious way:
//   - Identities are collected BEFORE the SQL runs, because the SQL
//     deletes org_members and staff — the very rows that tell us which
//     auth users belong to this tenant. Collect first or lose them.
//   - Auth users are deleted AFTER the SQL, because org_members.user_id
//     references auth.users; removing the auth user first can cascade
//     and take rows out from under the ordered delete.
//
// DRY RUN IS THE DEFAULT. {dry_run: false} must be sent explicitly.
// A dry run reports the auth users and storage objects that would go,
// alongside the SQL function's own per-table counts.
//
// ---- THIS FUNCTION IS THE ONLY WAY TO AUTHENTICATE THE CALLER ------
// delete_org() cannot check is_platform_admin() itself: it is granted to
// service_role only, and under service_role auth.uid() is NULL, so that
// check could never pass (revision 1 deadlocked on exactly this — see
// the SQL file's header). So the platform-admin check lives HERE, where
// the caller's real JWT is available, and the verified uuid is passed to
// the RPC as p_actor.
//
// That makes the block below the actual security boundary for tenant
// deletion. It is not a convenience wrapper. Do not add a code path that
// calls delete_org() without performing this verification first.
//
// Deploy:  supabase functions deploy admin-delete-org
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
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Same guard the SQL applies. Duplicated deliberately: this function must
// refuse APC even if someone later loosens the RPC.
const APC_ORG_ID = "11111111-1111-4111-8111-111111111111";

/** Masks an email for the dry-run report — enough to recognise, not to leak. */
function maskEmail(email: string | undefined): string {
  if (!email) return "(no email)";
  const [user, domain] = email.split("@");
  if (!domain) return "(malformed)";
  const head = user.slice(0, 2);
  return `${head}${"*".repeat(Math.max(1, user.length - 2))}@${domain}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const orgId: string | undefined = body.org_id;
    // Destructive path is never the default — it must be typed.
    const dryRun: boolean = body.dry_run !== false;
    const force: boolean = body.force === true;

    if (!orgId) return json({ error: "org_id is required" }, 400);
    if (orgId === APC_ORG_ID) {
      return json({
        error:
          "Refusing to delete APC (tenant #1). Guarded unconditionally — " +
          "the force flag does not apply.",
      }, 403);
    }

    // ---- 1. Caller must be a platform admin -------------------------
    // THE security boundary for tenant deletion — see the header. Same
    // pattern as staff-deactivate / admin-update-org: verify the caller's
    // own JWT under the service role, never trust the body.
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Missing Authorization header" }, 401);

    const { data: userRes, error: uErr } = await admin.auth.getUser(jwt);
    if (uErr || !userRes?.user) return json({ error: "Invalid session" }, 401);

    const { data: padmin, error: pErr } = await admin
      .from("platform_admins")
      .select("user_id")
      .eq("user_id", userRes.user.id)
      .maybeSingle();
    if (pErr) return json({ error: pErr.message }, 500);
    if (!padmin) {
      return json({ error: "Platform admin access required." }, 403);
    }

    // The verified identity handed to the RPC. Never read from the
    // request body — it is derived from the JWT this function just
    // validated, which is the whole reason the check moved here.
    const actorId = userRes.user.id;

    // ---- 2. Collect identities BEFORE the SQL removes them ----------
    const { data: org, error: oErr } = await admin
      .from("organizations")
      .select("id, name, slug, logo_url, plan_status")
      .eq("id", orgId)
      .maybeSingle();
    if (oErr) return json({ error: oErr.message }, 500);
    if (!org) return json({ error: `No organization with id ${orgId}` }, 404);

    const { data: members } = await admin
      .from("org_members")
      .select("user_id, role")
      .eq("org_id", orgId);

    const { data: staffRows } = await admin
      .from("staff")
      .select("auth_user_id, name")
      .eq("org_id", orgId)
      .not("auth_user_id", "is", null);

    // An owner may belong to several orgs. Deleting their auth user
    // because ONE of their tenants is being removed would lock them out
    // of the others — so only delete an auth user with no membership
    // outside this org.
    const candidateIds = new Set<string>();
    for (const m of members ?? []) if (m.user_id) candidateIds.add(m.user_id);
    for (const s of staffRows ?? []) {
      if (s.auth_user_id) candidateIds.add(s.auth_user_id);
    }

    const toDeleteUsers: { id: string; email: string; reason: string }[] = [];
    const keptUsers: { id: string; email: string; reason: string }[] = [];
    // Referenced by org_members/staff but with no auth.users row behind
    // them — a stale reference, e.g. TEST 1's phantom second owner.
    // There is no email to erase, so these are neither deleted nor
    // failures. Classified here, at collection time, rather than by
    // string-matching "User not found" out of a delete error: the
    // absence is a fact we can check directly, and matching on message
    // text would break the moment gotrue rewords it.
    const absentUsers: { id: string; note: string }[] = [];

    for (const id of candidateIds) {
      const { data: otherOrgs } = await admin
        .from("org_members")
        .select("org_id")
        .eq("user_id", id)
        .neq("org_id", orgId);

      const { data: u } = await admin.auth.admin.getUserById(id);
      const email = u?.user?.email ?? "";

      if (!u?.user) {
        absentUsers.push({
          id,
          note: "no auth.users row — stale reference, nothing to erase",
        });
        continue;
      }

      if ((otherOrgs?.length ?? 0) > 0) {
        // Name the other orgs rather than counting them. "also owns Arun
        // Packers and Couriers" tells you instantly why the account is
        // being spared; "also a member of 1 other org(s)" makes you go
        // and look it up.
        const names: string[] = [];
        for (const o of otherOrgs!) {
          const { data: og } = await admin
            .from("organizations").select("name").eq("id", o.org_id).maybeSingle();
          if (og?.name) names.push(og.name);
        }
        keptUsers.push({
          id,
          email: maskEmail(email),
          reason: names.length > 0
            ? `also owns ${names.join(", ")}`
            : `also a member of ${otherOrgs!.length} other org(s)`,
        });
      } else {
        toDeleteUsers.push({ id, email: maskEmail(email), reason: "sole org" });
      }
    }

    // ---- 3. Storage objects under this org's prefix -----------------
    // Buckets are enumerated rather than hardcoded so a bucket added
    // later isn't silently skipped — the same reasoning as the SQL
    // function's coverage check.
    const storageTargets: { bucket: string; paths: string[] }[] = [];
    const { data: buckets } = await admin.storage.listBuckets();
    for (const b of buckets ?? []) {
      const { data: objs } = await admin.storage.from(b.name).list(orgId, {
        limit: 1000,
      });
      if (objs && objs.length > 0) {
        storageTargets.push({
          bucket: b.name,
          paths: objs.map((o) => `${orgId}/${o.name}`),
        });
      }
    }

    // ---- 4. Dry run: report and stop --------------------------------
    if (dryRun) {
      const { data: sqlPreview, error: rpcErr } = await admin.rpc("delete_org", {
        p_org_id: orgId,
        p_actor: actorId,
        p_dry_run: true,
        p_force: force,
      });
      if (rpcErr) return json({ error: rpcErr.message }, 400);

      return json({
        dry_run: true,
        org: { id: org.id, name: org.name, slug: org.slug,
               plan_status: org.plan_status },
        database_rows: sqlPreview,
        auth_users_to_delete: toDeleteUsers,
        auth_users_kept: keptUsers,
        auth_users_absent: absentUsers,
        storage_objects: storageTargets,
        // Stated rather than left to inference: a dry run does not write
        // an audit row, because a dry run writes NOTHING. The audit row
        // is written only on a real run, immediately before the deletes.
        audit_row_written: false,
        note:
          "Nothing was changed — including no audit_log row, because a dry " +
          "run writes nothing at all. The audit row is written only on a " +
          "real run, immediately before the deletes. Re-send with " +
          "{\"dry_run\": false} to delete.",
      });
    }

    // ---- 5. Real run ------------------------------------------------
    // SQL first: it removes org_members/staff, so it must run before the
    // auth users those rows point at are deleted.
    const { data: sqlResult, error: delErr } = await admin.rpc("delete_org", {
      p_org_id: orgId,
      p_actor: actorId,
      p_dry_run: false,
      p_force: force,
    });
    if (delErr) return json({ error: delErr.message }, 400);

    // Storage next. Failures are collected, not thrown: an orphaned logo
    // is a tidiness problem, and aborting here would leave the tenant
    // half-deleted with the auth users still present — strictly worse.
    const storageResults: Record<string, string> = {};
    for (const t of storageTargets) {
      const { error } = await admin.storage.from(t.bucket).remove(t.paths);
      storageResults[t.bucket] = error
        ? `FAILED: ${error.message}`
        : `removed ${t.paths.length} object(s)`;
    }

    // Auth users last.
    const authResults: Record<string, string> = {};
    for (const u of toDeleteUsers) {
      const { error } = await admin.auth.admin.deleteUser(u.id);
      if (!error) {
        authResults[u.id] = "deleted";
      } else if (
        // Belt-and-braces for the race the collection-time check can't
        // cover: the user existed a moment ago and is gone now. Deleting
        // an already-absent user is a no-op, not a failure — treating it
        // as one would flip erasure_complete to false and warn about an
        // email address that does not exist, making a real failure
        // indistinguishable from noise.
        (error as { status?: number }).status === 404 ||
        /not found/i.test(error.message)
      ) {
        authResults[u.id] = "already absent (no-op)";
      } else {
        authResults[u.id] = `FAILED: ${error.message}`;
      }
    }
    for (const a of absentUsers) {
      authResults[a.id] = `skipped — ${a.note}`;
    }

    // Only a REAL deletion error counts. "Already absent" means the
    // email is gone, which is the outcome erasure_complete describes.
    const authFailures = Object.values(authResults).filter((v) =>
      v.startsWith("FAILED")
    ).length;

    // Confirm the audit row actually landed. The SQL writes it inside an
    // exception handler so an audit failure can never block a lawful
    // erasure — but that means a failure would otherwise be invisible,
    // which is exactly how revision 1's wrong column names would have
    // gone unnoticed. Report it rather than assume it.
    const { count: auditCount } = await admin
      .from("audit_log")
      .select("id", { count: "exact", head: true })
      .eq("entity_id", orgId)
      .eq("action", "delete_org");

    return json({
      dry_run: false,
      org: { id: org.id, name: org.name, slug: org.slug },
      database_rows: sqlResult,
      storage: storageResults,
      auth_users: authResults,
      auth_users_kept: keptUsers,
      audit_rows_for_this_org: auditCount ?? 0,
      audit_row_written: (auditCount ?? 0) > 0,
      // Stated explicitly rather than implied by an "ok": if any auth
      // user survived, the erasure is NOT complete and someone has to
      // act on that.
      erasure_complete: authFailures === 0,
      warning: authFailures > 0
        ? `${authFailures} auth user(s) could not be deleted — the email ` +
          `address still exists. Retry or remove them via the Dashboard.`
        : undefined,
    });
  } catch (e) {
    console.error("admin-delete-org unhandled:", e);
    return json({ error: String(e) }, 500);
  }
});
