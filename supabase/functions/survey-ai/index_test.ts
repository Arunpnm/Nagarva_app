// deno test --allow-env --allow-net supabase/functions/survey-ai/index_test.ts
//
// Runs the REAL function with the network replaced: Supabase REST and the
// AI provider are answered from memory, so the gates, the caps and the
// "record before calling" rule are exercised without an account or a key.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "https://stub.supabase.test");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");
Deno.env.set("AI_SURVEY_PROVIDER", "anthropic");
Deno.env.set("ANTHROPIC_API_KEY", "sk-test");
Deno.env.set("AI_SURVEY_LINK_CAP", "2");
Deno.env.set("AI_SURVEY_ORG_DAY_CAP", "3");

const TOKEN = "t".repeat(48);
const ORG = "11111111-1111-1111-1111-111111111111";
const USER = "22222222-2222-2222-2222-222222222222";
const cats = {
  Living: [{ name: "Sofa", subs: [{ label: "3 Seater", cft: 40 }] }],
  Bedroom: [{ name: "Bed", subs: [{ label: "King", cft: 70 }] }],
};
const JPEG = "/9j/" + "A".repeat(400);

const state = {
  usage: [] as Record<string, unknown>[],
  usageBroken: false,
  providerCalls: 0,
  providerReply: '{"items":[{"n":1,"qty":1},{"n":2,"qty":2}],"other":["Treadmill"]}',
  providerStatus: 200,
  providerQueue: [] as number[], // statuses for the next calls, then providerStatus
  surveyOk: true,
  plan: "pro" as "pro" | "other" | "broken",
  lastProviderBody: "" as string,
  monthCap: -1 as number | null | "broken",
  locked: false,
};

const realFetch = globalThis.fetch;
globalThis.fetch = async (input: Request | URL | string, init?: RequestInit) => {
  const req = input instanceof Request ? input : new Request(String(input), init);
  const url = new URL(req.url);
  const j = (b: unknown, status = 200, headers: Record<string, string> = {}) =>
    new Response(b === null ? null : JSON.stringify(b), {
      status,
      headers: { "content-type": "application/json", ...headers },
    });

  if (url.host === "api.anthropic.com") {
    state.providerCalls++;
    state.lastProviderBody = await req.text();
    const status = state.providerQueue.length ? state.providerQueue.shift()! : state.providerStatus;
    if (status !== 200) return j({ error: "x" }, status);
    return j({ content: [{ type: "text", text: state.providerReply }] });
  }
  if (url.host !== "stub.supabase.test") return realFetch(input, init);

  if (url.pathname === "/rest/v1/rpc/public_get_survey") {
    return j(state.surveyOk
      ? { ok: true, survey_cats: cats }
      : { ok: false, reason: "expired" });
  }
  if (url.pathname === "/rest/v1/rpc/org_effective_plan") {
    const b = await req.json();
    if (state.plan === "broken" || state.monthCap === "broken") return j({ message: "boom" }, 500);
    if (b.p_org_id !== ORG) return j([]);
    return j([{
      plan_code: state.plan,
      features: { ai_survey: state.plan === "pro" },
      limits: state.monthCap === null ? {} : { max_ai_survey_per_month: state.monthCap },
      is_locked: state.locked,
    }]);
  }
  if (url.pathname === "/rest/v1/customer_surveys") return j({ org_id: ORG });
  if (url.pathname === "/rest/v1/org_members") return j([{ org_id: ORG }]);
  if (url.pathname === "/auth/v1/user") {
    const ok = req.headers.get("authorization") === "Bearer good-jwt";
    return ok ? j({ id: USER, aud: "authenticated" }) : j({ msg: "bad" }, 401);
  }
  if (url.pathname === "/rest/v1/ai_survey_usage") {
    if (state.usageBroken) return j({ message: "relation does not exist" }, 404);
    if (req.method === "HEAD") {
      const byLink = url.searchParams.get("link_hash");
      const monthly = url.searchParams.get("or"); // only the monthly count
      const fresh = monthly ? Date.parse(monthly.match(/created_at\.gte\.([^)]+)\)/)![1]) : 0;
      const n = state.usage.filter((u) =>
        byLink
          ? `eq.${u.link_hash}` === byLink
          : u.org_id === ORG && (!monthly || u.ok === true ||
            ((u.ok === null || u.ok === undefined) &&
              Date.parse(String(u.created_at ?? new Date().toISOString())) >= fresh))
      ).length;
      return j(null, 200, { "content-range": `*/${n}` });
    }
    if (req.method === "POST") {
      const row = { id: `u${state.usage.length + 1}`, ...(await req.json()) };
      state.usage.push(row);
      return j(row, 201);
    }
    if (req.method === "PATCH") {
      const id = (url.searchParams.get("id") ?? "").replace("eq.", "");
      Object.assign(state.usage.find((u) => u.id === id) ?? {}, await req.json());
      return j(null, 204);
    }
  }
  return j({ message: "unexpected " + req.method + " " + url.pathname }, 500);
};

let handler!: (req: Request) => Promise<Response> | Response;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: typeof handler) => { handler = h; return {} as never; };
await import("./index.ts");

async function call(body: unknown, headers: Record<string, string> = {}) {
  const res = await handler(
    new Request("https://fn.test/survey-ai", {
      method: "POST",
      headers: { "content-type": "application/json", ...headers },
      body: JSON.stringify(body),
    }),
  );
  return await res.json();
}
function reset() {
  state.usage = [];
  state.usageBroken = false;
  state.providerCalls = 0;
  state.providerStatus = 200;
  state.providerQueue = [];
  state.surveyOk = true;
  state.plan = "pro";
  state.monthCap = -1;
  state.locked = false;
  state.providerReply =
    '{"items":[{"n":1,"qty":1},{"n":2,"qty":2}],"other":["Treadmill"]}';
}

Deno.test("status answers for the company asking; naming none is off", async () => {
  reset();
  const on = { ok: true, enabled: true };
  const offR = { ok: true, enabled: false };
  assertEquals(await call({ action: "status", token: TOKEN }), on);
  assertEquals(
    await call({ action: "status", org_id: ORG }, { authorization: "Bearer good-jwt" }),
    on,
  );
  assertEquals(await call({ action: "status" }), offR); // no company named
  assertEquals(await call({ action: "status", org_id: ORG }), offR); // not signed in
  state.surveyOk = false;
  assertEquals(await call({ action: "status", token: TOKEN }), offR); // dead link
  assertEquals(state.usage.length, 0); // asking never costs or counts
  assertEquals(state.providerCalls, 0);
});

Deno.test("Pro only: a company without the feature is refused on the server", async () => {
  reset();
  state.plan = "other";
  const offR = { ok: true, enabled: false };
  assertEquals(await call({ action: "status", token: TOKEN }), offR);
  assertEquals(
    await call({ action: "status", org_id: ORG }, { authorization: "Bearer good-jwt" }),
    offR,
  );
  // Skipping the status call and sending photos anyway changes nothing.
  assertEquals(
    await call({ token: TOKEN, room: "Bedroom", images: [JPEG] }),
    { ok: false, reason: "not_in_plan" },
  );
  assertEquals(
    await call(
      { org_id: ORG, room: "Bedroom", images: [JPEG], catalogue: cats },
      { authorization: "Bearer good-jwt" },
    ),
    { ok: false, reason: "not_in_plan" },
  );
  // If the plan cannot be read, photos are off — never on by accident.
  state.plan = "broken";
  assertEquals(await call({ action: "status", token: TOKEN }), offR);
  assertEquals(
    await call({ token: TOKEN, room: "Bedroom", images: [JPEG] }),
    { ok: false, reason: "unavailable" },
  );
  assertEquals(state.usage.length, 0);
  assertEquals(state.providerCalls, 0);
});

Deno.test("customer link: items come back from the catalogue, usage recorded", async () => {
  reset();
  const r = await call({ token: TOKEN, room: "Living room", images: [JPEG] });
  assertEquals(r, {
    ok: true,
    room: "Living room",
    items: [
      { cat: "Living", item: "Sofa", sub: "3 Seater", cft: 40, qty: 1 },
      { cat: "Bedroom", item: "Bed", sub: "King", cft: 70, qty: 2 },
    ],
    other: ["Treadmill"],
  });
  assertEquals(state.providerCalls, 1);
  assertEquals(state.usage.length, 1);
  assertEquals(state.usage[0].ok, true);
  assertEquals(state.usage[0].items_found, 2);
  assertEquals(state.usage[0].photos, 1);
  // The usage row holds a hash, never the working link.
  assertEquals(String(state.usage[0].link_hash).length, 64);
  assertEquals(JSON.stringify(state.usage).includes(TOKEN), false);
  // The provider was sent the photo and the numbered catalogue.
  assertEquals(state.lastProviderBody.includes("1. Sofa - 3 Seater [Living]"), true);
  assertEquals(state.lastProviderBody.includes('"media_type":"image/jpeg"'), true);
});

Deno.test("an expired or sent link never reaches the provider", async () => {
  reset();
  state.surveyOk = false;
  assertEquals(await call({ token: TOKEN, room: "x", images: [JPEG] }), {
    ok: false,
    reason: "expired",
  });
  assertEquals(state.providerCalls, 0);
  assertEquals(state.usage.length, 0);
});

Deno.test("bad input is refused before any cost", async () => {
  reset();
  assertEquals((await call({ token: TOKEN, images: [] })).reason, "no_photos");
  assertEquals(
    (await call({ token: TOKEN, images: [JPEG, JPEG, JPEG, JPEG, JPEG] })).reason,
    "too_many_photos",
  );
  assertEquals((await call({ token: TOKEN, images: ["hello"] })).reason, "bad_photo");
  assertEquals((await call({ token: "short", images: [JPEG] })).reason, "invalid");
  assertEquals(state.providerCalls, 0);
  assertEquals(state.usage.length, 0);
});

Deno.test("per-link cap stops the third check on one link", async () => {
  reset();
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).ok, true);
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).ok, true);
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "link_limit");
  assertEquals(state.providerCalls, 2);
});

Deno.test("per-company daily cap", async () => {
  reset();
  state.usage = [1, 2, 3].map((i) => ({ id: `x${i}`, org_id: ORG, link_hash: `other${i}` }));
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "busy_today");
  assertEquals(state.providerCalls, 0);
});

Deno.test("monthly plan allowance: failed checks are not charged, unreadable plan refuses", async () => {
  reset();
  state.monthCap = 1;
  state.usage = [
    { id: "b", org_id: ORG, link_hash: "o2", ok: false }, // provider failed
  ];
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).ok, true); // 0 of 1 used
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "month_limit");
  assertEquals(state.providerCalls, 1);
  state.monthCap = 0; // a plan with the feature but no allowance
  state.usage = [];
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "month_limit");
  state.monthCap = null; // plan does not mention the limit = no monthly limit
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).ok, true);
  state.monthCap = "broken";
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "unavailable");
  assertEquals(state.providerCalls, 2);
});

Deno.test("a locked company (trial and grace over) gets nothing that costs money", async () => {
  reset();
  state.locked = true;
  assertEquals(await call({ action: "status", token: TOKEN }), { ok: true, enabled: false });
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "not_in_plan");
  assertEquals(state.providerCalls, 0);
  assertEquals(state.usage.length, 0);
});

Deno.test("a check cut off long ago (no result) is not charged to the month", async () => {
  reset();
  state.monthCap = 1;
  state.usage = [{ id: "c", org_id: ORG, link_hash: "o3", ok: null,
    created_at: new Date(Date.now() - 3600_000).toISOString() }];
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).ok, true);
  assertEquals(state.providerCalls, 1);
});

Deno.test("a check really in flight still counts towards the month", async () => {
  reset();
  state.monthCap = 1;
  state.usage = [{ id: "d", org_id: ORG, link_hash: "o4", ok: null,
    created_at: new Date().toISOString() }];
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "month_limit");
  assertEquals(state.providerCalls, 0);
});

Deno.test("provider busy: one retry, then a plain refusal; a wrong request is not retried", async () => {
  reset();
  state.providerQueue = [503];
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).ok, true);
  assertEquals(state.providerCalls, 2);
  assertEquals(state.usage.length, 1); // one check, one row
  assertEquals(state.usage[0].ok, true);

  reset();
  state.providerQueue = [503, 503];
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "try_again");
  assertEquals(state.providerCalls, 2); // never a third

  reset();
  state.providerQueue = [400];
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "try_again");
  assertEquals(state.providerCalls, 1);
});

Deno.test("no usage table = no calls (fail closed)", async () => {
  reset();
  state.usageBroken = true;
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "unavailable");
  assertEquals(state.providerCalls, 0);
});

Deno.test("provider failure and unreadable answers are recorded, plain reason returned", async () => {
  reset();
  state.providerStatus = 500;
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "try_again");
  assertEquals(state.usage[0].ok, false);
  assertEquals(state.usage[0].error, "provider");
  state.providerStatus = 200;
  state.providerReply = "Sorry, I can't help with that.";
  assertEquals((await call({ token: TOKEN, images: [JPEG] })).reason, "try_again");
  assertEquals(state.usage[1].error, "unreadable");
});

Deno.test("staff: needs a real session and membership of the company named", async () => {
  reset();
  const body = { org_id: ORG, room: "Bedroom", images: [JPEG], catalogue: cats };
  assertEquals((await call(body)).reason, "not_signed_in");
  assertEquals(
    (await call(body, { authorization: "Bearer anon-or-forged" })).reason,
    "not_signed_in",
  );
  assertEquals(
    (await call({ ...body, org_id: "33333333-3333-3333-3333-333333333333" }, {
      authorization: "Bearer good-jwt",
    })).reason,
    "not_allowed",
  );
  assertEquals(state.providerCalls, 0);
  const ok = await call(body, { authorization: "Bearer good-jwt" });
  assertEquals(ok.ok, true);
  assertEquals(state.usage[0].user_id, USER);
  assertEquals(state.usage[0].link_hash, null);
  assertEquals(
    (await call({ ...body, catalogue: {} }, { authorization: "Bearer good-jwt" })).reason,
    "no_catalogue",
  );
});
