// ============================================================
// supabase/functions/whatsapp/index.ts
//
// WhatsApp through Meta's Cloud API, one vendor = one WhatsApp number.
// Needs supabase/20261021_whatsapp_cloud_api.sql to have run first.
//
// Every call: { action, org_id, ... } with the caller's JWT.
//
//   status            any member   connection + templates (no secrets)
//   connect           manager      phone_number_id, waba_id, token,
//                                  app_secret? — checks them with Meta,
//                                  stores the secrets in Vault, seeds the
//                                  org's templates from the library
//   disconnect        manager      forgets the token and app secret
//   submit_templates  manager      sends draft/rejected templates to Meta
//                                  for approval on the vendor's WABA
//   sync_templates    manager      reads approval status back from Meta
//   send              any member   key, to, params{}, entity_type?,
//                                  entity_id? — one approved template
//   test              manager      to — Meta's own hello_world template
//
// SECRETS: the access token and app secret are read only here, from
// Vault, with the service role. They never come back in a response.
//
// PLAN: `send` enforces features.whatsapp and
// limits.max_whatsapp_per_month (CLAUDE.md Item 32: the WhatsApp gate
// belongs at the send function, its real chokepoint).
//
// WHITE-LABEL: the business_name variable is filled here from
// organizations.name — never from the client, never the platform's name.
//
// Deploy:  supabase functions deploy whatsapp
// ============================================================

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { normalisePhone } from "../_shared/wa_util.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
// Overridable so a Graph API version retirement is a secret change, not
// a redeploy.
const GRAPH = `https://graph.facebook.com/${
  Deno.env.get("WA_GRAPH_VERSION") ?? "v23.0"
}`;

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

class Refusal extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}

// ------------------------------------------------------------ helpers

/** Meta error -> one sentence a vendor can act on. */
function metaError(body: any, fallback: string): string {
  const e = body?.error;
  if (!e) return fallback;
  if (e.code === 190) {
    return "Meta refused the access token. It may have expired; create a permanent token and connect again.";
  }
  if (e.code === 131030) return "This number is not on the allowed list of your test WhatsApp number.";
  if (e.code === 132001) return "Meta does not have this template in this language yet.";
  if (e.code === 131047) return "More than 24 hours since the customer last wrote; only approved templates can be sent.";
  return e.error_user_msg || e.message || fallback;
}

async function graph(
  token: string,
  path: string,
  init: { method?: string; body?: unknown } = {},
): Promise<any> {
  const res = await fetch(`${GRAPH}/${path}`, {
    method: init.method ?? "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Refusal(metaError(body, `Meta returned ${res.status}`), 502);
  return body;
}

async function vaultGet(orgId: string, kind: "token" | "app_secret") {
  const { data, error } = await admin.rpc("wa_vault_get", {
    p_org: orgId,
    p_kind: kind,
  });
  if (error) throw new Error(`vault read: ${error.message}`);
  return (data as string | null) ?? null;
}

async function vaultPut(orgId: string, kind: "token" | "app_secret", value: string | null) {
  const { error } = await admin.rpc("wa_vault_put", {
    p_org: orgId,
    p_kind: kind,
    p_value: value ?? "",
  });
  if (error) throw new Error(`vault write: ${error.message}`);
}

async function account(orgId: string) {
  const { data, error } = await admin
    .from("wa_accounts")
    .select("*")
    .eq("org_id", orgId)
    .maybeSingle();
  if (error) throw new Error(`account read: ${error.message}`);
  return data;
}

async function connectedToken(orgId: string) {
  const acc = await account(orgId);
  if (!acc || acc.status === "disconnected") {
    throw new Refusal("WhatsApp is not connected for this business yet.");
  }
  const token = await vaultGet(orgId, "token");
  if (!token) throw new Refusal("WhatsApp is not connected for this business yet.");
  return { acc, token };
}

/** Copies any library template the org does not have yet. */
async function seedTemplates(orgId: string) {
  const { data: lib, error } = await admin
    .from("wa_template_library")
    .select("key, name, language");
  if (error) throw new Error(`library read: ${error.message}`);
  const rows = (lib ?? []).map((l: any) => ({
    org_id: orgId,
    key: l.key,
    name: l.name,
    language: l.language,
  }));
  if (rows.length) {
    const { error: e2 } = await admin
      .from("wa_templates")
      .upsert(rows, { onConflict: "org_id,key", ignoreDuplicates: true });
    if (e2) throw new Error(`template seed: ${e2.message}`);
  }
}

async function templatesFor(orgId: string) {
  const { data, error } = await admin
    .from("wa_templates")
    .select("id, key, name, language, status, rejected_reason, enabled, updated_at")
    .eq("org_id", orgId);
  if (error) throw new Error(`templates read: ${error.message}`);
  return data ?? [];
}

function publicAccount(acc: any, hasAppSecret: boolean) {
  if (!acc) return null;
  return {
    phone_number_id: acc.phone_number_id,
    waba_id: acc.waba_id,
    display_phone: acc.display_phone,
    verified_name: acc.verified_name,
    status: acc.status,
    last_error: acc.last_error,
    connected_at: acc.connected_at,
    webhook_verify_token: acc.webhook_verify_token,
    webhook_url: `${SUPABASE_URL}/functions/v1/whatsapp-webhook`,
    inbox_ready: hasAppSecret,
  };
}

function monthStartIst(): string {
  const now = new Date(Date.now() + 5.5 * 3600 * 1000); // IST wall clock
  const start = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1) - 5.5 * 3600 * 1000;
  return new Date(start).toISOString();
}

// ------------------------------------------------------------ handler

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");
    const orgId = String(body.org_id ?? "");
    if (!action || !orgId) throw new Refusal("action and org_id are required");

    // ---- Who is calling, and may they act for this org? Asked of the
    // database AS THE CALLER, so this function and RLS cannot disagree
    // about who a member or a manager is.
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!/^Bearer\s+\S+/i.test(authHeader)) throw new Refusal("Not authorised", 401);
    const asCaller: SupabaseClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: who, error: whoErr } = await asCaller.auth.getUser();
    if (whoErr || !who?.user) throw new Refusal("Not authorised", 401);

    const { data: orgIds, error: idsErr } = await asCaller.rpc("current_org_ids");
    if (idsErr) throw new Error(`membership: ${idsErr.message}`);
    const ids = (Array.isArray(orgIds) ? orgIds : [orgIds]).map((r: any) =>
      typeof r === "string" ? r : r?.current_org_ids ?? Object.values(r ?? {})[0]
    );
    if (!ids.includes(orgId)) throw new Refusal("You are not part of this business.", 403);

    const requireManager = async () => {
      const { data, error } = await asCaller.rpc("is_org_manager", { p_org_id: orgId });
      if (error) throw new Error(`role: ${error.message}`);
      if (data !== true) {
        throw new Refusal("Only the owner or a manager can change WhatsApp settings.", 403);
      }
    };

    switch (action) {
      // -------------------------------------------------------- status
      case "status": {
        const acc = await account(orgId);
        const hasApp = acc ? Boolean(acc.app_secret_id) : false;
        const { count } = await admin
          .from("wa_messages")
          .select("id", { count: "exact", head: true })
          .eq("org_id", orgId)
          .eq("direction", "out")
          .neq("status", "failed") // a refused send costs nothing
          .gte("created_at", monthStartIst());
        const { data: limit } = await admin.rpc("org_limit", {
          p_org_id: orgId,
          p_key: "max_whatsapp_per_month",
        });
        const { data: feature } = await admin.rpc("org_has_feature", {
          p_org_id: orgId,
          p_key: "whatsapp",
        });
        return json({
          ok: true,
          account: publicAccount(acc, hasApp),
          templates: acc ? await templatesFor(orgId) : [],
          sent_this_month: count ?? 0,
          monthly_limit: limit ?? null,
          plan_allows: feature === true,
        });
      }

      // -------------------------------------------------------- connect
      case "connect": {
        await requireManager();
        const phoneId = String(body.phone_number_id ?? "").trim();
        const wabaId = String(body.waba_id ?? "").trim();
        const token = String(body.token ?? "").trim();
        const appSecret = String(body.app_secret ?? "").trim();
        if (!/^\d{6,25}$/.test(phoneId)) throw new Refusal("Enter the phone number ID (digits only) from WhatsApp Manager.");
        if (!/^\d{6,25}$/.test(wabaId)) throw new Refusal("Enter the WhatsApp Business Account ID (digits only).");

        const existing = await account(orgId);
        const useToken = token || (existing ? await vaultGet(orgId, "token") : null);
        if (!useToken) throw new Refusal("Enter the permanent access token.");

        // Prove the three belong together before storing anything.
        const phone = await graph(
          useToken,
          `${phoneId}?fields=display_phone_number,verified_name,quality_rating`,
        );
        const nums = await graph(useToken, `${wabaId}/phone_numbers?fields=id&limit=100`);
        if (!(nums?.data ?? []).some((n: any) => String(n.id) === phoneId)) {
          throw new Refusal("That phone number ID is not under this WhatsApp Business Account.");
        }

        const { data: taken } = await admin
          .from("wa_accounts")
          .select("org_id")
          .eq("phone_number_id", phoneId)
          .neq("org_id", orgId)
          .maybeSingle();
        if (taken) throw new Refusal("This WhatsApp number is already connected to another business.");

        const row = {
          org_id: orgId,
          phone_number_id: phoneId,
          waba_id: wabaId,
          display_phone: phone.display_phone_number ?? null,
          verified_name: phone.verified_name ?? null,
          status: "connected",
          last_error: null,
          updated_at: new Date().toISOString(),
          ...(existing ? {} : { connected_at: new Date().toISOString() }),
        };
        const { error: upErr } = await admin.from("wa_accounts").upsert(row, { onConflict: "org_id" });
        if (upErr) throw new Error(`account write: ${upErr.message}`);
        if (token) await vaultPut(orgId, "token", token);
        if (appSecret) await vaultPut(orgId, "app_secret", appSecret);
        await seedTemplates(orgId);

        const acc = await account(orgId);
        return json({
          ok: true,
          account: publicAccount(acc, Boolean(acc?.app_secret_id)),
          templates: await templatesFor(orgId),
        });
      }

      // -------------------------------------------------------- disconnect
      case "disconnect": {
        await requireManager();
        if (!(await account(orgId))) return json({ ok: true });
        await vaultPut(orgId, "token", null);
        await vaultPut(orgId, "app_secret", null);
        const { error } = await admin
          .from("wa_accounts")
          .update({ status: "disconnected", updated_at: new Date().toISOString() })
          .eq("org_id", orgId);
        if (error) throw new Error(`disconnect: ${error.message}`);
        // Auto-send off, so nothing fires against a missing token.
        await admin.from("wa_templates").update({ enabled: false }).eq("org_id", orgId);
        return json({ ok: true });
      }

      // -------------------------------------------------------- submit
      case "submit_templates": {
        await requireManager();
        const { acc, token } = await connectedToken(orgId);
        const { data: lib } = await admin.from("wa_template_library").select("*");
        const byKey = new Map((lib ?? []).map((l: any) => [l.key, l]));
        const wanted: string[] | null = Array.isArray(body.keys) ? body.keys.map(String) : null;
        const results: any[] = [];
        for (const t of await templatesFor(orgId)) {
          if (wanted && !wanted.includes(t.key)) continue;
          if (!["draft", "rejected"].includes(t.status)) continue;
          const l: any = byKey.get(t.key);
          if (!l) continue;
          try {
            const r = await graph(token, `${acc.waba_id}/message_templates`, {
              method: "POST",
              body: {
                name: t.name,
                language: t.language,
                category: l.category,
                components: [
                  { type: "BODY", text: l.body, example: { body_text: [l.example] } },
                ],
              },
            });
            const status = String(r.status ?? "PENDING").toLowerCase();
            await admin.from("wa_templates").update({
              status: ["approved", "rejected", "pending"].includes(status) ? status : "pending",
              meta_template_id: r.id ?? null,
              rejected_reason: null,
              updated_at: new Date().toISOString(),
            }).eq("id", t.id);
            results.push({ key: t.key, ok: true, status });
          } catch (e) {
            // Already exists on the WABA (e.g. submitted before): pick its
            // status up from Meta instead of failing.
            results.push({ key: t.key, ok: false, error: (e as Error).message });
          }
        }
        await syncTemplates(orgId, acc.waba_id, token);
        return json({ ok: true, results, templates: await templatesFor(orgId) });
      }

      // -------------------------------------------------------- sync
      case "sync_templates": {
        await requireManager();
        const { acc, token } = await connectedToken(orgId);
        await syncTemplates(orgId, acc.waba_id, token);
        return json({ ok: true, templates: await templatesFor(orgId) });
      }

      // -------------------------------------------------------- send
      case "send": {
        const key = String(body.key ?? "");
        const to = normalisePhone(String(body.to ?? ""));
        if (!key) throw new Refusal("key is required");
        if (!to) throw new Refusal("That does not look like a mobile number.");

        const { data: feature } = await admin.rpc("org_has_feature", {
          p_org_id: orgId,
          p_key: "whatsapp",
        });
        if (feature !== true) throw new Refusal("WhatsApp is not part of your current plan.", 402);
        const { data: limit } = await admin.rpc("org_limit", {
          p_org_id: orgId,
          p_key: "max_whatsapp_per_month",
        });
        if (typeof limit === "number" && limit >= 0) {
          const { count } = await admin
            .from("wa_messages")
            .select("id", { count: "exact", head: true })
            .eq("org_id", orgId)
            .eq("direction", "out")
            .neq("status", "failed") // a refused send costs nothing
            .gte("created_at", monthStartIst());
          if ((count ?? 0) >= limit) {
            throw new Refusal(`Your plan allows ${limit} WhatsApp messages a month, and this month's are used.`, 402);
          }
        }

        const { acc, token } = await connectedToken(orgId);
        const { data: tpl } = await admin
          .from("wa_templates")
          .select("key, name, language, status")
          .eq("org_id", orgId)
          .eq("key", key)
          .maybeSingle();
        if (!tpl) throw new Refusal("No such message.");
        if (tpl.status !== "approved") throw new Refusal("Meta has not approved this message yet.");
        const { data: lib } = await admin
          .from("wa_template_library")
          .select("body, params")
          .eq("key", key)
          .single();
        if (!lib) throw new Refusal("No such message.");
        const { data: org } = await admin
          .from("organizations")
          .select("name")
          .eq("id", orgId)
          .single();

        const given = (body.params ?? {}) as Record<string, unknown>;
        const values: string[] = [];
        for (const p of lib.params as string[]) {
          const v = p === "business_name" ? org?.name : given[p];
          const s = String(v ?? "").replace(/\s+/g, " ").trim();
          if (!s) throw new Refusal(`Missing ${p.replace(/_/g, " ")} for this message.`);
          values.push(s.slice(0, 900));
        }
        const rendered = (lib.body as string).replace(
          /\{\{(\d+)\}\}/g,
          (_: string, n: string) => values[Number(n) - 1] ?? "",
        );

        let waId: string | null = null;
        let errMsg: string | null = null;
        let errCode: string | null = null;
        try {
          const r = await graph(token, `${acc.phone_number_id}/messages`, {
            method: "POST",
            body: {
              messaging_product: "whatsapp",
              to,
              type: "template",
              template: {
                name: tpl.name,
                language: { code: tpl.language },
                components: [{
                  type: "body",
                  parameters: values.map((text) => ({ type: "text", text })),
                }],
              },
            },
          });
          waId = r?.messages?.[0]?.id ?? null;
        } catch (e) {
          errMsg = (e as Error).message;
          errCode = "send_failed";
        }

        await logOutbound(orgId, to, String(body.contact_name ?? given.customer_name ?? ""), {
          wa_message_id: waId,
          body: rendered,
          template_name: tpl.name,
          template_key: key,
          status: waId ? "sent" : "failed",
          error_code: errCode,
          error_message: errMsg,
          entity_type: body.entity_type ? String(body.entity_type) : null,
          entity_id: body.entity_id ? String(body.entity_id) : null,
        });
        if (!waId) throw new Refusal(errMsg ?? "Meta did not accept the message.", 502);
        return json({ ok: true, wa_message_id: waId });
      }

      // -------------------------------------------------------- test
      case "test": {
        await requireManager();
        const to = normalisePhone(String(body.to ?? ""));
        if (!to) throw new Refusal("That does not look like a mobile number.");
        const { acc, token } = await connectedToken(orgId);
        // hello_world exists on every WABA from the start, so a test works
        // before any of our templates are approved.
        const r = await graph(token, `${acc.phone_number_id}/messages`, {
          method: "POST",
          body: {
            messaging_product: "whatsapp",
            to,
            type: "template",
            template: { name: "hello_world", language: { code: "en_US" } },
          },
        });
        return json({ ok: true, wa_message_id: r?.messages?.[0]?.id ?? null });
      }

      default:
        throw new Refusal(`Unknown action ${action}`);
    }
  } catch (e) {
    if (e instanceof Refusal) return json({ error: e.message }, e.status);
    console.error("whatsapp:", e);
    return json({ error: "Something went wrong on our side. Please try again." }, 500);
  }
});

async function syncTemplates(orgId: string, wabaId: string, token: string) {
  const r = await graph(
    token,
    `${wabaId}/message_templates?fields=id,name,language,status,rejected_reason&limit=250`,
  );
  const remote = new Map<string, any>();
  for (const t of r?.data ?? []) remote.set(`${t.name}|${t.language}`, t);
  for (const t of await templatesFor(orgId)) {
    const m = remote.get(`${t.name}|${t.language}`);
    if (!m) continue;
    const s = String(m.status ?? "").toLowerCase();
    const status = ["approved", "pending", "rejected", "paused", "disabled"].includes(s)
      ? s
      : "pending";
    await admin.from("wa_templates").update({
      status,
      meta_template_id: m.id ?? null,
      rejected_reason: status === "rejected" ? (m.rejected_reason ?? null) : null,
      // A template Meta pulled cannot keep auto-sending.
      ...(status === "approved" ? {} : { enabled: false }),
      updated_at: new Date().toISOString(),
    }).eq("id", t.id);
  }
}

async function logOutbound(
  orgId: string,
  phone: string,
  name: string,
  msg: Record<string, unknown>,
) {
  const now = new Date().toISOString();
  const { data: contact, error } = await admin
    .from("wa_contacts")
    .upsert({
      org_id: orgId,
      phone: "+" + phone,
      phone_normalized: phone,
      ...(name ? { display_name: name } : {}),
      last_message_at: now,
      last_message_text: String(msg.body ?? "").slice(0, 200),
    }, { onConflict: "org_id,phone_normalized" })
    .select("id")
    .single();
  if (error) {
    console.error("wa_contacts upsert:", error.message);
    return;
  }
  const { error: mErr } = await admin.from("wa_messages").insert({
    org_id: orgId,
    contact_id: contact.id,
    direction: "out",
    msg_type: "template",
    sent_at: now,
    ...msg,
  });
  if (mErr) console.error("wa_messages insert:", mErr.message);
}
