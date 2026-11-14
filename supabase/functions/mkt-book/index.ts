// mkt-book: a customer books a move in the Nagarva customer app and pays
// the advance online (14 Nov 2026, list item 27).
//
// POST, with the signed-in customer's token:
//   { input: <mkt_quote input>, name, pickup_address, drop_address,
//     move_date: "YYYY-MM-DD", slot }
// Returns { booking_id, pay_url } or { error }.
//
// The price is worked out HERE, again, by mkt_quote(): whatever the app
// shows, the customer pays what Nagarva's own rates say. The payment is a
// Razorpay payment link for the advance; Razorpay's page takes the money,
// and razorpay-webhook (event payment_link.paid) turns the paid booking
// into a marketplace job. See supabase/20261114_customer_booking.sql.
//
// Secrets (already set for plan-billing): RAZORPAY_KEY_ID,
// RAZORPAY_KEY_SECRET. Test keys (rzp_test_...) give test payments.

import { createClient } from "npm:@supabase/supabase-js@2";
import { keyMode, RazorpayError, rzp } from "../_shared/razorpay.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const KEY_ID = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";
const RETURN_URL = Deno.env.get("MKT_PAID_RETURN_URL") ?? "https://link.nagarva.in/paid/";

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
const refuse = (message: string, status = 400) => json({ error: message }, status);

const QUOTE_WORDS: Record<string, string> = {
  no_price: "We are not taking bookings for this move yet.",
  city_not_served: "We do not serve this city yet.",
  no_items: "Add at least one item.",
  no_address: "Set the pickup and drop locations.",
  outside_city: "One of the locations is outside this city.",
  too_far: "This is too far for a within-city move.",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return refuse("Use POST.", 405);
  if (!keyMode(KEY_ID) || !KEY_SECRET) {
    console.error("mkt-book: Razorpay keys missing");
    return refuse("Online payment is not set up yet. Please try again later.", 503);
  }

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who } = jwt ? await admin.auth.getUser(jwt) : ({ data: null } as any);
  const user = who?.user;
  if (!user?.id) return refuse("Please sign in again.", 401);
  const phone = String(user.phone ?? "").replace(/\D/g, "").slice(-10);
  if (phone.length !== 10) return refuse("Please sign in with your mobile number.", 401);

  let body: any;
  try {
    body = await req.json();
  } catch {
    return refuse("Something was missing. Please try again.");
  }
  const name = String(body?.name ?? "").trim().slice(0, 80);
  const pickup = String(body?.pickup_address ?? "").trim().slice(0, 400);
  const drop = String(body?.drop_address ?? "").trim().slice(0, 400);
  const date = String(body?.move_date ?? "");
  const slot = String(body?.slot ?? "").trim().slice(0, 40) || null;
  const input = body?.input;
  if (name.length < 2) return refuse("Please enter your name.");
  if (pickup.length < 8 || drop.length < 8) return refuse("Please enter both full addresses.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || new Date(date + "T23:59:59+05:30").getTime() < Date.now()) {
    return refuse("Please pick a moving date.");
  }
  if (!input || typeof input !== "object") return refuse("Something was missing. Please try again.");

  // One open (unpaid) booking at a time per customer is plenty; older
  // unpaid ones are retired so "My moves" does not fill with them.
  await admin.from("mkt_bookings").update({ status: "expired" })
    .eq("customer_user_id", user.id).eq("status", "awaiting_payment")
    .lt("created_at", new Date(Date.now() - 30 * 60_000).toISOString());

  // The price, from Nagarva's rates.
  const { data: q, error: qErr } = await admin.rpc("mkt_quote", { p: input });
  if (qErr) {
    console.error("mkt-book: mkt_quote", qErr.message);
    return refuse("Could not price this move. Please try again.", 500);
  }
  if (!q?.ok) return refuse(QUOTE_WORDS[q?.reason] ?? "Could not price this move.");
  const total = Number(q.total);
  const advance = Number(q.advance);
  if (!(advance > 0) || !(total >= advance)) return refuse("Could not price this move.", 500);

  const { data: booking, error: bErr } = await admin.from("mkt_bookings").insert({
    customer_user_id: user.id,
    customer_name: name,
    customer_phone: phone,
    input,
    quote: q,
    pickup_address: pickup,
    drop_address: drop,
    move_date: date,
    slot,
    total_inr: total,
    advance_inr: advance,
  }).select("id").single();
  if (bErr || !booking) {
    console.error("mkt-book: insert", bErr?.message);
    return refuse("Could not save your booking. Please try again.", 500);
  }

  try {
    const link = await rzp(KEY_ID, KEY_SECRET, "POST", "/payment_links", {
      amount: Math.round(advance * 100),
      currency: "INR",
      accept_partial: false,
      description: `Advance for your move ${input.from_city ?? ""} to ${input.to_city ?? input.from_city ?? ""} on ${date}`,
      customer: { name, contact: "+91" + phone },
      notify: { sms: false, email: false },
      reminder_enable: false,
      expire_by: Math.floor(Date.now() / 1000) + 24 * 3600,
      notes: { booking_id: booking.id, kind: "mkt_booking" },
      callback_url: RETURN_URL,
      callback_method: "get",
    });
    await admin.from("mkt_bookings").update({
      rzp_link_id: link.id,
      rzp_link_url: link.short_url,
    }).eq("id", booking.id);
    return json({ booking_id: booking.id, pay_url: link.short_url, advance, total });
  } catch (e) {
    console.error("mkt-book: payment link", e instanceof RazorpayError ? e.message : String(e));
    await admin.from("mkt_bookings").update({ status: "cancelled" }).eq("id", booking.id);
    return refuse("Could not open the payment page. Please try again.", 502);
  }
});
