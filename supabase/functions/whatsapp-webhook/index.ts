// ============================================================
// supabase/functions/whatsapp-webhook/index.ts
//
// Meta calls this, not the app. It carries delivery receipts (sent,
// delivered, read, failed) for messages we sent, and customers' replies,
// which land in the Inbox.
//
// One URL serves every vendor: the payload names the phone number ID,
// which picks the org. Each vendor sets this URL and their own verify
// token (shown on the app's WhatsApp screen) in their Meta app.
//
// TRUST: nothing is written unless the X-Hub-Signature-256 header is a
// valid HMAC of the raw body under THAT org's Meta app secret (from
// Vault). A vendor who has not given us their app secret gets sending
// but no inbox — an unsigned webhook would let anyone forge customer
// messages into a vendor's inbox.
//
// Deploy WITHOUT JWT verification (Meta sends no Supabase token):
//   supabase functions deploy whatsapp-webhook --no-verify-jwt
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { signatureValid } from "../_shared/wa_util.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { autoRefreshToken: false, persistSession: false } },
);

// Delivery states only move forward; Meta can deliver them out of order.
const RANK: Record<string, number> = { sent: 1, delivered: 2, read: 3, failed: 4 };

function textOf(m: any): string {
  switch (m?.type) {
    case "text": return m.text?.body ?? "";
    case "button": return m.button?.text ?? "";
    case "interactive":
      return m.interactive?.button_reply?.title ?? m.interactive?.list_reply?.title ?? "";
    case "image": return m.image?.caption ? `[Photo] ${m.image.caption}` : "[Photo]";
    case "document": return `[Document] ${m.document?.filename ?? ""}`.trim();
    case "audio": return "[Voice message]";
    case "video": return "[Video]";
    case "location": return "[Location]";
    default: return `[${m?.type ?? "message"}]`;
  }
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);

  // ---- Meta's one-time subscription check.
  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token") ?? "";
    const challenge = url.searchParams.get("hub.challenge") ?? "";
    if (mode !== "subscribe" || token.length < 16) {
      return new Response("forbidden", { status: 403 });
    }
    const { data } = await admin
      .from("wa_accounts")
      .select("org_id")
      .eq("webhook_verify_token", token)
      .maybeSingle();
    return data
      ? new Response(challenge, { status: 200 })
      : new Response("forbidden", { status: 403 });
  }

  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  const raw = new Uint8Array(await req.arrayBuffer());
  const header = req.headers.get("x-hub-signature-256");
  let payload: any;
  try {
    payload = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return new Response("bad request", { status: 400 });
  }

  // Which orgs does this payload speak for, and does each one's app
  // secret sign it?
  const changes: { orgId: string; value: any }[] = [];
  const verified = new Map<string, boolean>();
  for (const entry of payload?.entry ?? []) {
    for (const ch of entry?.changes ?? []) {
      if (ch?.field !== "messages") continue;
      const phoneId = String(ch?.value?.metadata?.phone_number_id ?? "");
      if (!phoneId) continue;
      const { data: acc } = await admin
        .from("wa_accounts")
        .select("org_id, status")
        .eq("phone_number_id", phoneId)
        .maybeSingle();
      if (!acc || acc.status === "disconnected") continue;
      if (!verified.has(acc.org_id)) {
        const { data: secret } = await admin.rpc("wa_vault_get", {
          p_org: acc.org_id,
          p_kind: "app_secret",
        });
        verified.set(acc.org_id, await signatureValid(secret as string | null, header, raw));
      }
      if (verified.get(acc.org_id)) changes.push({ orgId: acc.org_id, value: ch.value });
    }
  }
  if (verified.size > 0 && changes.length === 0) {
    return new Response("signature mismatch", { status: 401 });
  }

  for (const { orgId, value } of changes) {
    // ---- Delivery receipts for what we sent.
    for (const s of value?.statuses ?? []) {
      const id = String(s?.id ?? "");
      const st = String(s?.status ?? "");
      if (!id || !RANK[st]) continue;
      const { data: msg } = await admin
        .from("wa_messages")
        .select("id, status")
        .eq("org_id", orgId)
        .eq("wa_message_id", id)
        .maybeSingle();
      if (!msg || (RANK[msg.status] ?? 0) >= RANK[st]) continue;
      const err = s?.errors?.[0];
      await admin.from("wa_messages").update({
        status: st,
        ...(err ? { error_code: String(err.code ?? ""), error_message: err.title ?? err.message ?? null } : {}),
      }).eq("id", msg.id);
    }

    // ---- Customers writing in.
    const names = new Map<string, string>();
    for (const c of value?.contacts ?? []) {
      if (c?.wa_id) names.set(String(c.wa_id), c?.profile?.name ?? "");
    }
    for (const m of value?.messages ?? []) {
      const from = String(m?.from ?? "").replace(/\D/g, "");
      const id = String(m?.id ?? "");
      if (!from || !id) continue;
      const at = m?.timestamp
        ? new Date(Number(m.timestamp) * 1000).toISOString()
        : new Date().toISOString();
      const text = textOf(m);

      const { data: existing } = await admin
        .from("wa_contacts")
        .select("id, unread_count, display_name")
        .eq("org_id", orgId)
        .eq("phone_normalized", from)
        .maybeSingle();
      let contactId = existing?.id as string | undefined;

      const { data: dup } = await admin
        .from("wa_messages")
        .select("id")
        .eq("org_id", orgId)
        .eq("wa_message_id", id)
        .maybeSingle();
      if (dup) continue; // Meta retries; never count a message twice.

      if (!contactId) {
        const { data: created, error } = await admin
          .from("wa_contacts")
          .insert({
            org_id: orgId,
            phone: "+" + from,
            phone_normalized: from,
            display_name: names.get(from) || null,
            last_message_at: at,
            last_message_text: text.slice(0, 200),
            unread_count: 1,
          })
          .select("id")
          .single();
        if (error) {
          console.error("contact insert:", error.message);
          continue;
        }
        contactId = created.id;
      } else {
        await admin.from("wa_contacts").update({
          last_message_at: at,
          last_message_text: text.slice(0, 200),
          unread_count: (existing?.unread_count ?? 0) + 1,
          ...(!existing?.display_name && names.get(from) ? { display_name: names.get(from) } : {}),
        }).eq("id", contactId);
      }

      const { error: mErr } = await admin.from("wa_messages").insert({
        org_id: orgId,
        contact_id: contactId,
        wa_message_id: id,
        direction: "in",
        msg_type: String(m?.type ?? "text"),
        body: text,
        status: "received",
        sent_at: at,
      });
      if (mErr) console.error("message insert:", mErr.message);
    }
  }

  // Meta retries anything that is not 200, so accept what we could
  // attribute and verify.
  return new Response("ok", { status: 200 });
});
