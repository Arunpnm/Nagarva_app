// deno test supabase/functions/_shared/razorpay_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  amountWithGstPaise,
  applyWebhookEvent,
  BillingRpc,
  fromUnix,
  hmacHex,
  keyMode,
  rzpPeriod,
  safeEqual,
  syncSubscription,
  webhookSignatureOk,
} from "./razorpay.ts";

Deno.test("GST on top, in paise, for every plan price", () => {
  assertEquals(amountWithGstPaise(2999), 353882); // Pro  Rs 3,538.82
  assertEquals(amountWithGstPaise(1499), 176882); // Growth Rs 1,768.82
  assertEquals(amountWithGstPaise(799), 94282); //   Basic Rs 942.82
  assertEquals(amountWithGstPaise(29990), 3538820); // an annual price
  assertEquals(amountWithGstPaise(1000, 0), 100000);
});

Deno.test("key mode comes from the key id, nothing else counts", () => {
  assertEquals(keyMode("rzp_test_TyfknHdbX82dRI"), "test");
  assertEquals(keyMode("rzp_live_abc"), "live");
  assertEquals(keyMode("rzp_testx"), null);
  assertEquals(keyMode(""), null);
  assertEquals(keyMode(undefined), null);
});

Deno.test("period names and unix times", () => {
  assertEquals(rzpPeriod("monthly"), "monthly");
  assertEquals(rzpPeriod("annual"), "yearly");
  assertEquals(fromUnix(1794355200), "2026-11-11T00:00:00.000Z");
  assertEquals(fromUnix(null), null);
  assertEquals(fromUnix(0), null);
});

Deno.test("webhook signature: right secret passes, anything else fails", async () => {
  const body = '{"event":"subscription.charged","payload":{}}';
  const sig = await hmacHex("whsec-1", body);
  assert(await webhookSignatureOk(body, sig, "whsec-1"));
  assert(await webhookSignatureOk(body, sig.toUpperCase(), "whsec-1"));
  assert(!(await webhookSignatureOk(body, sig, "whsec-2")));
  assert(!(await webhookSignatureOk(body + " ", sig, "whsec-1"))); // body changed
  assert(!(await webhookSignatureOk(body, null, "whsec-1")));
  assert(!(await webhookSignatureOk(body, sig, ""))); // no secret set = refuse
  assert(!safeEqual("ab", "abc"));
});

function fakeRpc() {
  const calls: string[] = [];
  const rpc: BillingRpc = {
    recordCharge: async (a) => {
      calls.push(`charge ${a.sub} ${a.payment} ${a.amountPaise} ${a.periodEnd}`);
      return "recorded";
    },
    setStatus: async (a) => {
      calls.push(`status ${a.sub} ${a.status} ${a.periodEnd}`);
      return "updated";
    },
  };
  return { rpc, calls };
}

Deno.test("charged event: charge first, then status", async () => {
  const { rpc, calls } = fakeRpc();
  const out = await applyWebhookEvent({
    event: "subscription.charged",
    payload: {
      subscription: { entity: { id: "sub_1", status: "active", current_start: 1794355200, current_end: 1796947200 } },
      payment: { entity: { id: "pay_1", amount: 353882, created_at: 1794355300 } },
    },
  }, rpc);
  assertEquals(calls, [
    "charge sub_1 pay_1 353882 2026-12-11T00:00:00.000Z",
    "status sub_1 active 2026-12-11T00:00:00.000Z",
  ]);
  assertEquals(out, "charge:recorded status:updated");
});

Deno.test("halted event: status only, no charge", async () => {
  const { rpc, calls } = fakeRpc();
  await applyWebhookEvent({
    event: "subscription.halted",
    payload: { subscription: { entity: { id: "sub_1", status: "halted", current_end: 1796947200 } } },
  }, rpc);
  assertEquals(calls, ["status sub_1 halted 2026-12-11T00:00:00.000Z"]);
});

Deno.test("non-subscription and broken events change nothing", async () => {
  const { rpc, calls } = fakeRpc();
  assertEquals(await applyWebhookEvent({ event: "payment.captured", payload: {} }, rpc), "ignored");
  assertEquals(await applyWebhookEvent({ event: "subscription.charged", payload: {} }, rpc), "no_subscription");
  assertEquals(
    await applyWebhookEvent({
      event: "subscription.updated",
      payload: { subscription: { entity: { id: "sub_1", status: "weird" } } },
    }, rpc),
    "nothing",
  );
  assertEquals(calls, []);
});

Deno.test("pull sync: paid invoices oldest first, unpaid skipped, then status", async () => {
  const { rpc, calls } = fakeRpc();
  const call = async (_m: string, path: string) => {
    if (path.startsWith("/subscriptions/")) {
      return { id: "sub_1", status: "active", current_end: 1799625600 };
    }
    return {
      items: [
        { status: "paid", payment_id: "pay_2", amount_paid: 353882, billing_start: 1796947200, billing_end: 1799625600, paid_at: 1796947300 },
        { status: "issued", payment_id: null, amount: 353882, billing_start: 1799625600, billing_end: 1802304000 },
        { status: "paid", payment_id: "pay_1", amount_paid: 353882, billing_start: 1794355200, billing_end: 1796947200, paid_at: 1794355300 },
      ],
    };
  };
  const r = await syncSubscription("sub_1", call as any, rpc);
  assertEquals(r.status, "active");
  assertEquals(calls, [
    "charge sub_1 pay_1 353882 2026-12-11T00:00:00.000Z",
    "charge sub_1 pay_2 353882 2027-01-11T00:00:00.000Z",
    "status sub_1 active 2027-01-11T00:00:00.000Z",
  ]);
});
