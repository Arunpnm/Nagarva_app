// ============================================================
// supabase/functions/push-send/index.ts  (12 Nov 2026)
//
// Delivers one bell notification to phones through Firebase Cloud
// Messaging (HTTP v1). Called by the notifications_push trigger
// (20261112_push_notifications.sql) with { id } only.
//
// SAFE WITHOUT A LOGIN, BY DESIGN: the caller sends only a notification
// id. The text comes from our own table, the row is claimed once
// (pushed_at), and only rows from the last 10 minutes are sent. So a
// stranger calling this can at most deliver, once, an alert that was
// already going to be delivered.
//
// Who gets it:
//   recipient_staff_id set  -> that staff member's phones
//   recipient_staff_id null -> the company's owners' phones
// (the same rule the bell's RLS uses, notifications_select).
//
// Secret: FCM_SERVICE_ACCOUNT = the Firebase service-account JSON
// (Firebase console -> Project settings -> Service accounts). Never sent
// back in a response or logged.
//
// Deploy: npx supabase functions deploy push-send --no-verify-jwt --project-ref hqqcapifefsaqvotqvlt
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SA_RAW = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ---------------------------------------------------- Google OAuth

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

let cachedToken: { value: string; exp: number } | null = null;

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data instanceof Uint8Array ? data : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.value;

  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
  const jwt = `${header}.${claim}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) {
    throw new Error(`google token ${res.status}: ${body.error ?? "unknown"}`);
  }
  cachedToken = { value: body.access_token, exp: now + Number(body.expires_in ?? 3600) };
  return cachedToken.value;
}

// ---------------------------------------------------------- handler

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  let id = "";
  try {
    id = String((await req.json())?.id ?? "");
  } catch { /* fall through */ }
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: "id required" }, 400);

  if (!SA_RAW) {
    console.error("push-send: FCM_SERVICE_ACCOUNT is not set");
    return json({ skipped: "not_configured" });
  }
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(SA_RAW);
    if (!sa.project_id || !sa.client_email || !sa.private_key) throw new Error();
  } catch {
    console.error("push-send: FCM_SERVICE_ACCOUNT is not a service-account JSON");
    return json({ skipped: "bad_config" });
  }

  // Claim the row: once only, and only fresh alerts.
  const since = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { data: claimed, error: claimErr } = await admin
    .from("notifications")
    .update({ pushed_at: new Date().toISOString() })
    .eq("id", id)
    .is("pushed_at", null)
    .gt("created_at", since)
    .select("id, org_id, recipient_staff_id, type, title, body, ref_lead_id, ref_order_id");
  if (claimErr) {
    console.error("push-send: claim failed", claimErr.message);
    return json({ error: "claim failed" }, 500);
  }
  const n = claimed?.[0];
  if (!n) return json({ skipped: "already_sent_or_old" });

  // Whose phones.
  let q = admin
    .from("notification_tokens")
    .select("id, token")
    .eq("org_id", n.org_id)
    .eq("active", true);
  if (n.recipient_staff_id) {
    q = q.eq("staff_id", n.recipient_staff_id);
  } else {
    const { data: owners } = await admin
      .from("org_members")
      .select("user_id")
      .eq("org_id", n.org_id)
      .eq("role", "owner");
    const ids = (owners ?? []).map((o: any) => o.user_id).filter(Boolean);
    if (ids.length === 0) return json({ sent: 0 });
    q = q.is("staff_id", null).in("user_id", ids);
  }
  const { data: tokens } = await q;
  if (!tokens || tokens.length === 0) return json({ sent: 0 });

  let bearer: string;
  try {
    bearer = await accessToken(sa);
  } catch (e) {
    console.error("push-send:", String(e));
    return json({ error: "auth failed" }, 502);
  }

  let sent = 0;
  const dead: string[] = [];
  const used: string[] = [];
  for (const t of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${bearer}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: t.token,
            notification: {
              title: String(n.title ?? "").slice(0, 120),
              body: String(n.body ?? "").slice(0, 400),
            },
            data: {
              notification_id: String(n.id),
              type: String(n.type ?? ""),
              ref_lead_id: String(n.ref_lead_id ?? ""),
              ref_order_id: String(n.ref_order_id ?? ""),
            },
            android: {
              priority: "high",
              notification: { sound: "default", default_vibrate_timings: true },
            },
          },
        }),
      },
    );
    if (res.ok) {
      sent++;
      used.push(t.id);
      continue;
    }
    const body = await res.json().catch(() => ({}));
    const code = (body?.error?.details ?? []).find((d: any) => d?.errorCode)?.errorCode ??
      body?.error?.status;
    // The app was uninstalled or the token rotated: stop using it.
    if (res.status === 404 || code === "UNREGISTERED") {
      dead.push(t.id);
    } else {
      console.error("push-send: fcm", res.status, code ?? "");
    }
  }
  if (dead.length) {
    await admin.from("notification_tokens").update({ active: false }).in("id", dead);
  }
  if (used.length) {
    await admin.from("notification_tokens")
      .update({ last_used_at: new Date().toISOString() })
      .in("id", used);
  }
  return json({ sent, dropped: dead.length });
});
