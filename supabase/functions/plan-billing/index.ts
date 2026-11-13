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
//   { action: "change", org_id, plan_code }    -> { short_url }: move to
//                                              another plan from the end
//                                              of the month already paid
//                                              for (13 Nov 2026)
//
// Change plan (Arun, 13 Nov 2026: "every upgrade or downgrade will apply
// at the end of the month, not in between"). Razorpay cannot change the
// plan of a UPI Autopay, so a change is two steps done together: a NEW
// Autopay for the new plan whose first charge is the day the paid month
// ends (is_next = true, replaces_id = the old one), and the old one told
// to stop at that same day. Nothing is charged in between and nothing is
// refunded. If the vendor never approves the new Autopay, the old one
// still stops on that day and the company goes to grace, as with Stop.
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
    // Autopay set up during a trial: the first charge waits for the trial
    // to end. Only meaningful before the first payment.
    starts_at: ["created", "authenticated"].includes(sub.status)
      ? sub.current_period_start
      : null,
    ends_at_period_end: ["cancelled_by_vendor", "changing_plan"].includes(sub.cancel_reason) &&
      RUNNING.includes(sub.status),
    test_mode: sub.gateway_mode === "test",
  };
}

/** Live Autopays for a company, oldest first: at most the current one
 *  and one waiting to take over from it (is_next). */
async function liveSubs(orgId: string): Promise<{ current: any; next: any }> {
  const { data } = await admin
    .from("org_subscriptions")
    .select("*, subscription_plans(code, name)")
    .eq("org_id", orgId)
    .in("status", LIVE)
    .order("created_at", { ascending: true });
  const rows = data ?? [];
  const current = rows.find((r: any) => !r.is_next) ?? null;
  const next = rows.find((r: any) => r.is_next) ?? null;
  // A waiting one with nothing left to wait for is simply the current one.
  return current ? { current, next } : { current: next, next: null };
}

function describeNext(sub: any) {
  if (!sub) return null;
  return {
    status: sub.status,
    plan_code: sub.subscription_plans?.code ?? null,
    plan_name: sub.subscription_plans?.name ?? null,
    amount_inr: sub.amount_inr != null ? Number(sub.amount_inr) : null,
    starts_at: sub.current_period_start,
    short_url: sub.status === "created" ? sub.short_url : null,
  };
}

async function buyablePlan(code: string) {
  const { data: plan } = await admin
    .from("subscription_plans")
    .select("id, code, name, price_inr, billing_period, active")
    .eq("code", code)
    .maybeSingle();
  if (!plan || !plan.active || Number(plan.price_inr) <= 0 ||
      plan.code === "trial" || plan.code === "free") {
    return null;
  }
  return plan;
}

/** Stop an Autopay that has not charged yet (or a waiting one) at once. */
async function cancelNow(sub: any) {
  try {
    await call("POST", `/subscriptions/${sub.gateway_sub_id}/cancel`, {
      cancel_at_cycle_end: false,
    });
  } catch (e) {
    console.error("plan-billing: could not cancel", sub.gateway_sub_id, String(e));
  }
  await rpc.setStatus({ sub: sub.gateway_sub_id, status: "cancelled", periodEnd: null });
}

/** Our plan + today's price + GST -> one Razorpay plan (made once), then
 *  a Razorpay subscription for it. `startAt` = first charge day, or null
 *  to charge on approval. `replaces` = the Autopay this one takes over
 *  from. Returns the approval link, or null when another start won. */
async function createSubscription(a: {
  orgId: string;
  plan: any;
  userId: string;
  mode: string;
  startAt: Date | null;
  replaces: any | null;
}): Promise<string | null> {
  const { orgId, plan, userId, mode, startAt, replaces } = a;
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
    ...(startAt ? { start_at: Math.floor(startAt.getTime() / 1000) } : {}),
    notes: { org_id: orgId, plan_code: plan.code },
  });
  const ins = await admin.from("org_subscriptions").insert({
    org_id: orgId,
    plan_id: plan.id,
    status: "created",
    billing_period: plan.billing_period,
    amount_inr: amount / 100,
    current_period_start: startAt ? startAt.toISOString() : null,
    gateway: "razorpay",
    gateway_sub_id: sub.id,
    gateway_mode: mode,
    gateway_plan_ref: gp.id,
    short_url: sub.short_url,
    created_by: userId,
    auto_renew: true,
    ...(replaces ? { replaces_id: replaces.id, is_next: true } : {}),
  });
  if (ins.error) {
    // Another start won the race: do not leave a second one open.
    try {
      await call("POST", `/subscriptions/${sub.id}/cancel`, { cancel_at_cycle_end: false });
    } catch { /* best effort */ }
    console.error("plan-billing: insert failed", ins.error.message);
    return null;
  }
  await event(orgId, replaces ? "plan_change_started" : "autopay_started", {
    plan: plan.code,
    amount_inr: amount / 100,
    subscription: sub.id,
    starts_at: startAt ? startAt.toISOString() : null,
    replaces: replaces?.gateway_sub_id ?? null,
    mode,
    requested_by: userId,
    source: "plan-billing",
  });
  return sub.short_url;
}

/** The first charge of a new Autopay waits for a trial that still has
 *  more than a day left (Arun, 12 Nov 2026). */
async function trialStart(orgId: string): Promise<Date | null> {
  const { data: org } = await admin
    .from("organizations")
    .select("plan_status, trial_ends_at")
    .eq("id", orgId)
    .maybeSingle();
  const trialEnd = org?.plan_status === "trial" && org?.trial_ends_at
    ? new Date(org.trial_ends_at)
    : null;
  return trialEnd && trialEnd.getTime() > Date.now() + 86_400_000 ? trialEnd : null;
}

const BUSY =
  "A payment is already being set up for this company. Please wait a minute and check again.";

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
  if (!["status", "start", "cancel", "change"].includes(action) || !/^[0-9a-f-]{36}$/i.test(orgId)) {
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
      let { current, next } = await liveSubs(orgId);
      for (const sub of [current, next]) {
        if (sub?.gateway_sub_id && sub.gateway_mode === mode) {
          await syncSubscription(sub.gateway_sub_id, call, rpc);
        }
      }
      ({ current, next } = await liveSubs(orgId));
      return json({
        subscription: describe(current ?? await latestSubscription(orgId)),
        next: describeNext(next),
        plans: await plansWithGst(),
        test_mode: mode === "test",
      });
    }

    // ------------------------------------------------------------ start
    if (action === "start") {
      const plan = await buyablePlan(String(body?.plan_code ?? ""));
      if (!plan) return refuse("This plan cannot be bought online.");

      const { current: live } = await liveSubs(orgId);
      if (live && RUNNING.includes(live.status)) {
        return refuse(
          "Autopay is already on for this company. Use Change plan to move to another plan.",
          409,
        );
      }
      if (live && live.status === "created") {
        // An approval page that was opened but never finished.
        if (live.plan_id === plan.id && live.short_url && live.gateway_mode === mode) {
          return json({ short_url: live.short_url });
        }
        await cancelNow(live);
      }
      const url = await createSubscription({
        orgId, plan, userId, mode, startAt: await trialStart(orgId), replaces: null,
      });
      return url ? json({ short_url: url }) : refuse(BUSY, 409);
    }

    // ------------------------------------------------------------ change
    if (action === "change") {
      const plan = await buyablePlan(String(body?.plan_code ?? ""));
      if (!plan) return refuse("This plan cannot be bought online.");

      const { current, next } = await liveSubs(orgId);
      if (!current || !RUNNING.includes(current.status)) {
        return refuse("Autopay is not on yet. Pay with Autopay to choose this plan.", 409);
      }
      const ending = ["cancelled_by_vendor", "changing_plan"].includes(current.cancel_reason);

      // Not charged yet (Autopay set up during the trial): nothing is
      // paid for, so swap it for the new plan with the same first day.
      if (current.status === "authenticated") {
        if (current.plan_id === plan.id) {
          return refuse("Autopay is already set up for this plan.", 409);
        }
        if (next) await cancelNow(next);
        await cancelNow(current);
        const url = await createSubscription({
          orgId, plan, userId, mode, startAt: await trialStart(orgId), replaces: null,
        });
        return url ? json({ short_url: url }) : refuse(BUSY, 409);
      }
      if (current.status !== "active") {
        return refuse(
          "The last payment has not gone through yet. Please change the plan after it is paid.",
          409,
        );
      }
      if (current.plan_id === plan.id && !ending && !next) {
        return refuse("Your company is already on this plan.", 409);
      }
      const end = current.current_period_end ? new Date(current.current_period_end) : null;
      if (!end || end.getTime() < Date.now() + 3_600_000) {
        return refuse("Your plan renews very soon. Please change the plan tomorrow.", 409);
      }

      if (next) {
        // The same change, approval page not finished: hand it back.
        if (next.plan_id === plan.id && next.status === "created" &&
            next.short_url && next.gateway_mode === mode) {
          return json({ short_url: next.short_url });
        }
        await cancelNow(next);
      }
      // Back to the plan already paid for, before any stop was asked:
      // dropping the waiting change is all that is needed.
      if (current.plan_id === plan.id && !ending) {
        return json({ subscription: describe(current), next: null });
      }

      // New Autopay first: if Razorpay refuses, nothing has changed.
      const url = await createSubscription({
        orgId, plan, userId, mode, startAt: end, replaces: current,
      });
      if (!url) return refuse(BUSY, 409);

      // Then the old one stops on the day the new one starts.
      if (!ending) {
        try {
          await call("POST", `/subscriptions/${current.gateway_sub_id}/cancel`, {
            cancel_at_cycle_end: true,
          });
        } catch (e) {
          // Two Autopays must never both charge: undo the new one.
          console.error("plan-billing: could not stop the old Autopay", String(e));
          const { next: made } = await liveSubs(orgId);
          if (made) await cancelNow(made);
          throw e;
        }
        await admin
          .from("org_subscriptions")
          .update({ cancel_reason: "changing_plan", auto_renew: false, updated_at: new Date().toISOString() })
          .eq("id", current.id);
      }
      return json({ short_url: url });
    }

    // ------------------------------------------------------------ cancel
    const { current: live, next: waiting } = await liveSubs(orgId);
    if (!live) return refuse("There is no Autopay to stop.", 404);
    // A plan change that is waiting stops too: Stop means no more payments.
    if (waiting) await cancelNow(waiting);
    if (live.status === "created" || live.status === "authenticated") {
      // Nothing charged yet: stop it at once.
      await cancelNow(live);
    } else if (["cancelled_by_vendor", "changing_plan"].includes(live.cancel_reason)) {
      // Already stopping at the end of the paid month.
      await admin
        .from("org_subscriptions")
        .update({ cancel_reason: "cancelled_by_vendor", updated_at: new Date().toISOString() })
        .eq("id", live.id);
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
    const after = await liveSubs(orgId);
    return json({
      subscription: describe(after.current ?? await latestSubscription(orgId)),
      next: describeNext(after.next),
    });
  } catch (e) {
    if (e instanceof RazorpayError) {
      console.error("plan-billing: Razorpay", e.status, e.message);
      return refuse("The payment service did not answer. Please try again in a minute.", 502);
    }
    console.error("plan-billing:", String(e));
    return refuse("Something went wrong. Please try again.", 500);
  }
});
