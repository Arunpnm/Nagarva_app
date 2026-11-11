// ============================================================
// supabase/functions/razorpay-webhook/index.ts  (11 Nov 2026)
//
// Razorpay calls this when an Autopay charge succeeds every month, or
// when Autopay stops. Without it the monthly charges still happen at
// Razorpay, but the company's paid-up date would only move when someone
// opens the Plan page.
//
// Set up once, in the Razorpay dashboard (Test mode first):
//   Account & Settings -> Webhooks -> Add new webhook
//     URL:    https://hqqcapifefsaqvotqvlt.supabase.co/functions/v1/razorpay-webhook
//     Secret: any long random text; put the SAME text in the Supabase
//             secret RAZORPAY_WEBHOOK_SECRET
//     Events: subscription.authenticated, subscription.activated,
//             subscription.charged, subscription.pending,
//             subscription.halted, subscription.cancelled,
//             subscription.completed, subscription.paused
//
// No Supabase login: Razorpay cannot send one. The signature on the raw
// body is what proves the call is Razorpay's.
//
// Deploy: npx supabase functions deploy razorpay-webhook --no-verify-jwt --project-ref hqqcapifefsaqvotqvlt
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { applyWebhookEvent, BillingRpc, webhookSignatureOk } from "../_shared/razorpay.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const rpc: BillingRpc = {
  async recordCharge(a) {
    const { data, error } = await admin.rpc("billing_record_charge", {
      p_gateway_sub_id: a.sub,
      p_payment_id: a.payment,
      p_amount_paise: a.amountPaise,
      p_period_start: a.periodStart,
      p_period_end: a.periodEnd,
      p_paid_at: a.paidAt,
    });
    if (error) throw new Error(`billing_record_charge: ${error.message}`);
    return String(data);
  },
  async setStatus(a) {
    const { data, error } = await admin.rpc("billing_set_status", {
      p_gateway_sub_id: a.sub,
      p_status: a.status,
      p_period_end: a.periodEnd,
    });
    if (error) throw new Error(`billing_set_status: ${error.message}`);
    return String(data);
  },
};

const reply = (status: number, text: string) =>
  new Response(text, { status, headers: { "Content-Type": "text/plain" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply(405, "POST only");
  if (!WEBHOOK_SECRET) {
    console.error("razorpay-webhook: RAZORPAY_WEBHOOK_SECRET is not set");
    return reply(500, "not configured");
  }

  const raw = await req.text();
  if (!(await webhookSignatureOk(raw, req.headers.get("x-razorpay-signature"), WEBHOOK_SECRET))) {
    console.warn("razorpay-webhook: bad signature");
    return reply(401, "bad signature");
  }

  let evt: any;
  try {
    evt = JSON.parse(raw);
  } catch {
    return reply(400, "bad body");
  }
  const eventId = req.headers.get("x-razorpay-event-id") ??
    `${evt?.event ?? "?"}:${evt?.created_at ?? ""}:${evt?.payload?.subscription?.entity?.id ?? ""}`;

  // Once only: a retry of an event already applied is acknowledged.
  const claim = await admin
    .from("razorpay_webhook_events")
    .insert({ event_id: eventId, event: String(evt?.event ?? "") });
  if (claim.error) {
    if (claim.error.code === "23505") return reply(200, "already handled");
    console.error("razorpay-webhook: could not log event", claim.error.message);
    return reply(500, "log failed");
  }

  try {
    const outcome = await applyWebhookEvent(evt, rpc);
    await admin.from("razorpay_webhook_events").update({ outcome }).eq("event_id", eventId);
    return reply(200, outcome);
  } catch (e) {
    // Release the claim so Razorpay's retry gets another go.
    await admin.from("razorpay_webhook_events").delete().eq("event_id", eventId);
    console.error("razorpay-webhook: failed", eventId, String(e));
    return reply(500, "failed");
  }
});
