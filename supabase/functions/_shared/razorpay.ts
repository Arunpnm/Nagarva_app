// supabase/functions/_shared/razorpay.ts  (11 Nov 2026)
//
// Razorpay Subscriptions (UPI Autopay) for vendors paying Nagarva for
// their plan. Used by plan-billing (the app's buttons) and
// razorpay-webhook (Razorpay telling us about charges and stops).
//
// Secrets (Supabase -> Edge Functions -> Secrets):
//   RAZORPAY_KEY_ID         rzp_test_... or rzp_live_...
//   RAZORPAY_KEY_SECRET
//   RAZORPAY_WEBHOOK_SECRET the secret typed when adding the webhook in
//                           the Razorpay dashboard (webhook only)
//
// Money rule (Arun, 11 Nov 2026): GST ON TOP of the plan price.

export const GST_PCT = 18;
const API = "https://api.razorpay.com/v1";

export class RazorpayError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/** Plan price in rupees + GST, in paise. Integer maths: 2999 -> 353882. */
export function amountWithGstPaise(priceInr: number, gstPct = GST_PCT): number {
  return Math.round(Math.round(priceInr * 100) * (100 + gstPct) / 100);
}

/** 'test' or 'live' from the key id; null if the key is not a Razorpay key. */
export function keyMode(keyId: string | undefined | null): "test" | "live" | null {
  if (!keyId) return null;
  if (keyId.startsWith("rzp_test_")) return "test";
  if (keyId.startsWith("rzp_live_")) return "live";
  return null;
}

/** Razorpay sends unix seconds; null stays null. */
export function fromUnix(sec: number | null | undefined): string | null {
  return typeof sec === "number" && sec > 0
    ? new Date(sec * 1000).toISOString()
    : null;
}

/** Razorpay period name for our billing_period. */
export function rzpPeriod(billingPeriod: string): "monthly" | "yearly" {
  return billingPeriod === "annual" ? "yearly" : "monthly";
}

export async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Constant-time compare of two hex strings. */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** X-Razorpay-Signature = hex HMAC-SHA256 of the RAW body with the webhook secret. */
export async function webhookSignatureOk(
  rawBody: string,
  signature: string | null,
  secret: string,
): Promise<boolean> {
  if (!signature || !secret) return false;
  return safeEqual(await hmacHex(secret, rawBody), signature.trim().toLowerCase());
}

/** Calls the Razorpay API with the key pair; throws RazorpayError on failure. */
export async function rzp(
  keyId: string,
  keySecret: string,
  method: "GET" | "POST",
  path: string,
  body?: unknown,
  fetchImpl: typeof fetch = fetch,
): Promise<any> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 15000);
  try {
    const res = await fetchImpl(`${API}${path}`, {
      method,
      headers: {
        Authorization: "Basic " + btoa(`${keyId}:${keySecret}`),
        "Content-Type": "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: ctrl.signal,
    });
    const text = await res.text();
    let data: any = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = null;
    }
    if (!res.ok) {
      const desc = data?.error?.description ?? `HTTP ${res.status}`;
      throw new RazorpayError(res.status, String(desc));
    }
    return data;
  } finally {
    clearTimeout(t);
  }
}

/** The two database calls, so the logic below can be tested without a database. */
export interface BillingRpc {
  recordCharge(a: {
    sub: string;
    payment: string;
    amountPaise: number;
    periodStart: string | null;
    periodEnd: string | null;
    paidAt: string | null;
  }): Promise<string>;
  setStatus(a: { sub: string; status: string; periodEnd: string | null }): Promise<string>;
}

const STATUSES = new Set([
  "created", "authenticated", "active", "pending",
  "halted", "paused", "cancelled", "completed", "expired",
]);

/**
 * Applies one webhook event. Charges first (they move the company to
 * Paid), then the subscription's status (a stop moves it to grace).
 * Returns a short outcome for the event log.
 */
export async function applyWebhookEvent(evt: any, rpc: BillingRpc): Promise<string> {
  const event = String(evt?.event ?? "");
  if (!event.startsWith("subscription.")) return "ignored";
  const sub = evt?.payload?.subscription?.entity;
  if (!sub?.id) return "no_subscription";

  const out: string[] = [];
  if (event === "subscription.charged") {
    const pay = evt?.payload?.payment?.entity;
    if (pay?.id && typeof pay.amount === "number") {
      out.push(
        "charge:" +
          (await rpc.recordCharge({
            sub: sub.id,
            payment: pay.id,
            amountPaise: pay.amount,
            periodStart: fromUnix(sub.current_start),
            periodEnd: fromUnix(sub.current_end),
            paidAt: fromUnix(pay.created_at),
          })),
      );
    } else {
      out.push("charge:no_payment");
    }
  }
  const status = String(sub.status ?? "");
  if (STATUSES.has(status)) {
    out.push(
      "status:" +
        (await rpc.setStatus({ sub: sub.id, status, periodEnd: fromUnix(sub.current_end) })),
    );
  }
  return out.join(" ") || "nothing";
}

/**
 * Pull version of the same thing, for the app's "check" button and for
 * when no webhook is set up yet: reads the subscription and its paid
 * invoices from Razorpay and applies them. Safe to repeat.
 */
export async function syncSubscription(
  subId: string,
  call: (method: "GET" | "POST", path: string, body?: unknown) => Promise<any>,
  rpc: BillingRpc,
): Promise<{ status: string; currentEnd: string | null }> {
  const sub = await call("GET", `/subscriptions/${encodeURIComponent(subId)}`);
  const inv = await call(
    "GET",
    `/invoices?subscription_id=${encodeURIComponent(subId)}&count=100`,
  );
  const items: any[] = Array.isArray(inv?.items) ? inv.items : [];
  // Oldest first, so the period end only moves forward.
  items.sort((a, b) => (a.billing_start ?? 0) - (b.billing_start ?? 0));
  for (const it of items) {
    if (it?.status !== "paid" || !it.payment_id) continue;
    await rpc.recordCharge({
      sub: subId,
      payment: it.payment_id,
      amountPaise: Number(it.amount_paid ?? it.amount ?? 0),
      periodStart: fromUnix(it.billing_start),
      periodEnd: fromUnix(it.billing_end),
      paidAt: fromUnix(it.paid_at),
    });
  }
  const status = String(sub?.status ?? "");
  const currentEnd = fromUnix(sub?.current_end);
  if (STATUSES.has(status)) {
    await rpc.setStatus({ sub: subId, status, periodEnd: currentEnd });
  }
  return { status, currentEnd };
}
