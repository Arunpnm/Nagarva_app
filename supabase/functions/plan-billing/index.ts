// ============================================================
// supabase/functions/plan-billing/index.ts  (11 Nov 2026)
//
// The Plan page's Autopay buttons. A vendor (the company OWNER only)
// pays Nagarva for their plan through Razorpay UPI Autopay; GST is
// charged on top of the plan price (Arun, 11 Nov 2026).
//
//   { action: "status", org_id }               current Autopay + prices
//   { action: "start",  org_id, plan_code }    -> { short_url } to open
//   { action: "cancel", org_id }               stop at the end of the
//                                              month already paid for
//
// The price charged is read here from subscription_plans -- never sent
// by the app -- so a changed app cannot choose its own price.
//
// Company changes (plan, Paid, grace) are made only by the two database
// functions billing_record_charge / billing_set_status, the same ones
// the razorpay-webhook function calls. "status" also pulls from Razorpay
// and applies what it finds, so a payment shows even before the webhook
// is set up, and a missed webhook heals on the next look.
//
// Every refusal is one plain sentence (app rule).
//
// Deploy: npx supabase functions deploy plan-billing --project-ref hqqcapifefsaqvotqvlt
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  amountWithGstPaise,
  BillingRpc,
  GST_PCT,
  keyMode,
  RazorpayError,
  rzp,
  rzpPeriod,
  syncSubscription,
} from "../_shared/razorpay.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const KEY_ID = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
const refuse = (message: string, status = 400) => json({ error: message }, status);

const LIVE = ["created", "authenticated", "active", "pending", "paused"];
const RUNNING = ["authenticated", "active", "pending", "paused"];

const call = (method: "GET" | "POST", path: string, body?: unknown) =>
  rzp(KEY_ID, KEY_SECRET, method, path, body);

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

async function plansWithGst() {
  const { data } = await admin
    .from("subscription_plans")
    .select("code, name, price_inr, billing_period")
    .eq("active", true)
    .gt("price_inr", 0)
    .order("price_inr");
  return (data ?? [])
    .filter((p) => p.code !== "trial" && p.code !== "free")
    .map((p) => ({
      code: p.code,
      name: p.name,
      billing_period: p.billing_period,
      price_inr: Number(p.price_inr),
      gst_pct: GST_PCT,
      total_inr: amountWithGstPaise(Number(p.price_inr)) / 100,
    }));
}

async function latestSubscription(orgId: string) {
  const { data } = await admin
    .from("org_subscriptions")
    .select("*, subscription_plans(code, name)")
    .eq("org_id", orgId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data;
}

function describe(sub: any) {
  if (!sub) return null;
  return {
    status: sub.status,
    plan_code: sub.subscription_plans?.code ?? null,
    plan_name: sub.subscription_plans?.name ?? null,
    amount_inr: sub.amount_inr != null ? Number(sub.amount_inr) : null,
    current_period_end: sub.current_period_end,
    short_url: sub.status === "created" ? sub.short_url : null,
    ends_at_period_end: sub.cancel_reason === "cancelled_by_vendor" &&
      RUNNING.includes(sub.status),
    test_mode: sub.gateway_mode === "test",
  };
}

async function event(orgId: string, type: string, detail: Record<string, unknown>) {
  await admin.from("billing_events").insert({ org_id: orgId, event_type: type, detail });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return refuse("Use POST.", 405);

  const mode = keyMode(KEY_ID);
  if (!mode || !KEY_SECRET) {
    console.error("plan-billing: RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET missing or not a Razorpay key");
    return refuse("Online payment is not set up yet. Please contact Nagarva support.", 503);
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return refuse("Something was missing in the request. Please try again.");
  }
  const action = String(body?.action ?? "");
  const orgId = String(body?.org_id ?? "");
  if (!["status", "start", "cancel"].includes(action) || !/^[0-9a-f-]{36}$/i.test(orgId)) {
    return refuse("Something was missing in the request. Please try again.");
  }

  // ---- the caller must be signed in and OWN this company
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who } = jwt ? await admin.auth.getUser(jwt) : { data: null } as any;
  const userId: string | undefined = who?.user?.id;
  if (!userId) return refuse("Please sign in again.", 401);
  const { data: member } = await admin
    .from("org_members")
    .select("role")
    .eq("org_id", orgId)
    .eq("user_id", userId)
    .maybeSingle();
  if (member?.role !== "owner") {
    return refuse("Only the company owner can manage the plan payment.", 403);
  }

  try {
    // ------------------------------------------------------------ status
    if (action === "status") {
      let sub = await latestSubscription(orgId);
      if (sub?.gateway_sub_id && sub.gateway_mode === mode &&
          !["cancelled", "completed", "expired"].includes(sub.status)) {
        await syncSubscription(sub.gateway_sub_id, call, rpc);
        sub = await latestSubscription(orgId);
      }
      return json({ subscription: describe(sub), plans: await plansWithGst(), test_mode: mode === "test" });
    }

    // ------------------------------------------------------------ start
    if (action === "start") {
      const code = String(body?.plan_code ?? "");
      const { data: plan } = await admin
        .from("subscription_plans")
        .select("id, code, name, price_inr, billing_period, active")
        .eq("code", code)
        .maybeSingle();
      if (!plan || !plan.active || Number(plan.price_inr) <= 0 ||
          plan.code === "trial" || plan.code === "free") {
        return refuse("This plan cannot be bought online.");
      }

      const { data: live } = await admin
        .from("org_subscriptions")
        .select("*")
        .eq("org_id", orgId)
        .in("status", LIVE)
        .maybeSingle();
      if (live && RUNNING.includes(live.status)) {
        return refuse(
          "Autopay is already on for this company. Stop it first to change the plan.",
          409,
        );
      }
      if (live && live.status === "created") {
        // An approval page that was opened but never finished.
        if (live.plan_id === plan.id && live.short_url && live.gateway_mode === mode) {
          return json({ short_url: live.short_url });
        }
        try {
          await call("POST", `/subscriptions/${live.gateway_sub_id}/cancel`, {
            cancel_at_cycle_end: false,
          });
        } catch (e) {
          console.error("plan-billing: could not cancel unfinished subscription", live.gateway_sub_id, String(e));
        }
        await rpc.setStatus({ sub: live.gateway_sub_id, status: "cancelled", periodEnd: null });
      }

      // Our plan + today's price + GST -> one Razorpay plan (made once).
      const price = Number(plan.price_inr);
      const amount = amountWithGstPaise(price);
      const match = {
        plan_id: plan.id,
        billing_period: plan.billing_period,
        price_inr: price,
        gst_pct: GST_PCT,
        gateway: "razorpay",
        gateway_mode: mode,
      };
      let { data: gp } = await admin.from("platform_gateway_plans").select("*").match(match).maybeSingle();
      if (!gp) {
        const made = await call("POST", "/plans", {
          period: rzpPeriod(plan.billing_period),
          interval: 1,
          item: {
            name: `Nagarva ${plan.name}`,
            amount,
            currency: "INR",
            description: `${plan.name} plan, Rs ${price} + ${GST_PCT}% GST`,
          },
          notes: { plan_code: plan.code },
        });
        const ins = await admin
          .from("platform_gateway_plans")
          .insert({ ...match, amount_paise: amount, gateway_plan_id: made.id })
          .select("*")
          .maybeSingle();
        gp = ins.data ??
          (await admin.from("platform_gateway_plans").select("*").match(match).maybeSingle()).data;
        if (!gp) throw new Error("could not save the gateway plan");
      }

      const sub = await call("POST", "/subscriptions", {
        plan_id: gp.gateway_plan_id,
        total_count: plan.billing_period === "annual" ? 10 : 120,
        quantity: 1,
        customer_notify: true,
        notes: { org_id: orgId, plan_code: plan.code },
      });
      const ins = await admin.from("org_subscriptions").insert({
        org_id: orgId,
        plan_id: plan.id,
        status: "created",
        billing_period: plan.billing_period,
        amount_inr: amount / 100,
        current_period_start: null,
        gateway: "razorpay",
        gateway_sub_id: sub.id,
        gateway_mode: mode,
        gateway_plan_ref: gp.id,
        short_url: sub.short_url,
        created_by: userId,
        auto_renew: true,
      });
      if (ins.error) {
        // Another start won the race: do not leave a second one open.
        try {
          await call("POST", `/subscriptions/${sub.id}/cancel`, { cancel_at_cycle_end: false });
        } catch { /* best effort */ }
        console.error("plan-billing: insert failed", ins.error.message);
        return refuse("A payment is already being set up for this company. Please wait a minute and check again.", 409);
      }
      await event(orgId, "autopay_started", {
        plan: plan.code,
        amount_inr: amount / 100,
        subscription: sub.id,
        mode,
        requested_by: userId,
        source: "plan-billing",
      });
      return json({ short_url: sub.short_url });
    }

    // ------------------------------------------------------------ cancel
    const { data: live } = await admin
      .from("org_subscriptions")
      .select("*")
      .eq("org_id", orgId)
      .in("status", LIVE)
      .maybeSingle();
    if (!live) return refuse("There is no Autopay to stop.", 404);
    if (live.status === "created") {
      try {
        await call("POST", `/subscriptions/${live.gateway_sub_id}/cancel`, { cancel_at_cycle_end: false });
      } catch (e) {
        console.error("plan-billing: cancel of unfinished subscription failed", String(e));
      }
      await rpc.setStatus({ sub: live.gateway_sub_id, status: "cancelled", periodEnd: null });
    } else {
      // Stop at the end of the month already paid for; the company keeps
      // its plan until then. Razorpay sends subscription.cancelled then.
      await call("POST", `/subscriptions/${live.gateway_sub_id}/cancel`, { cancel_at_cycle_end: true });
      await admin
        .from("org_subscriptions")
        .update({ cancel_reason: "cancelled_by_vendor", auto_renew: false, updated_at: new Date().toISOString() })
        .eq("id", live.id);
    }
    await event(orgId, "autopay_cancel_requested", {
      subscription: live.gateway_sub_id,
      requested_by: userId,
      source: "plan-billing",
    });
    return json({ subscription: describe(await latestSubscription(orgId)) });
  } catch (e) {
    if (e instanceof RazorpayError) {
      console.error("plan-billing: Razorpay", e.status, e.message);
      return refuse("The payment service did not answer. Please try again in a minute.", 502);
    }
    console.error("plan-billing:", String(e));
    return refuse("Something went wrong. Please try again.", 500);
  }
});
