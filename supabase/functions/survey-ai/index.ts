// ============================================================
// supabase/functions/survey-ai/index.ts
//
// AI photo survey (10 Nov 2026). Room photos in -> a SUGGESTED item list
// out, matched to the vendor's own catalogue. A person always confirms
// the list before it is submitted; this function writes nothing to a
// survey, a lead or a quote.
//
// Two callers, one function:
//   * a customer on the public survey link   body: { token, room, images }
//   * staff inside the app (signed in)       body: { org_id, room, images, catalogue }
//   * either, to ask whether photos are on for THEIR company — the same
//     body with action: "status" and no images.
//
// PRO PLAN ONLY (Arun, 10 Nov 2026). Photos are on for a company only when
// its plan carries the feature `ai_survey` (org_effective_plan — the same
// lookup every other plan gate uses; plan migration:
// supabase/20261110_ai_survey_pro_only.sql; on for Pro and for Trial,
// which is Pro for 30 days). The check is here, on the
// server, for both callers: hiding a button is not a gate. "status"
// answers for the company asking, so a company without the feature never
// sees the button or the card, and a status call that names no company
// answers "off".
//
// The AI key never leaves the server, and the provider is one setting:
//   AI_SURVEY_PROVIDER = anthropic | gemini | openai     (unset = feature off)
//   AI_SURVEY_MODEL    = model id (optional for anthropic, required otherwise)
//   ANTHROPIC_API_KEY / GEMINI_API_KEY / OPENAI_API_KEY
//   AI_SURVEY_LINK_CAP     analyses per survey link      (default 40)
//   AI_SURVEY_ORG_DAY_CAP  analyses per company per day  (default 300)
//
// Every analysis costs money, so every one is recorded in ai_survey_usage
// BEFORE the provider is called, and the caps are counted from that table.
// If the record cannot be written the call is refused — an unrecorded call
// is an uncapped one. (Table: supabase/20261110_ai_survey_usage.sql.)
//
// Photos are sent to the provider for this one answer and are not stored
// by this function.
//
// Deploy:  supabase functions deploy survey-ai
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  buildPrompt,
  cleanRoom,
  flattenCatalogue,
  MAX_IMAGES,
  readAnswer,
  readImage,
} from "../_shared/survey_ai_util.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const PROVIDER = (Deno.env.get("AI_SURVEY_PROVIDER") ?? "").trim().toLowerCase();
const MODEL = (Deno.env.get("AI_SURVEY_MODEL") ?? "").trim();
const LINK_CAP = Number(Deno.env.get("AI_SURVEY_LINK_CAP") ?? "40") || 40;
const ORG_DAY_CAP = Number(Deno.env.get("AI_SURVEY_ORG_DAY_CAP") ?? "300") || 300;

const KEYS: Record<string, string | undefined> = {
  anthropic: Deno.env.get("ANTHROPIC_API_KEY"),
  gemini: Deno.env.get("GEMINI_API_KEY"),
  openai: Deno.env.get("OPENAI_API_KEY"),
};
const DEFAULT_MODEL: Record<string, string> = {
  anthropic: "claude-haiku-5-5",
};

/** A model id, not something else pasted into AI_SURVEY_MODEL (10 Nov
 *  2026: an API key was pasted there once, sent to Google as the model
 *  name and then written into ai_survey_usage.model, where company members
 *  can read it). A value that fails this check switches photos OFF rather
 *  than being sent anywhere or stored. Lower-case letters, digits, dots and
 *  dashes; the provider's own family prefix; at most 64 characters. */
const MODEL_SHAPE: Record<string, RegExp> = {
  anthropic: /^claude-[a-z0-9][a-z0-9.-]{0,56}$/,
  gemini: /^gemini-[a-z0-9][a-z0-9.-]{0,56}$/,
  openai: /^[a-z][a-z0-9.-]{1,63}$/,
};
export function modelLooksRight(provider: string, model: string): boolean {
  const shape = MODEL_SHAPE[provider];
  if (!shape || !shape.test(model)) return false;
  // Key prefixes that happen to fit the lower-case shape.
  return !/^(sk-|aiza|aq\.)/.test(model);
}

let warnedModel = false;
function configured(): { provider: string; model: string; key: string } | null {
  const key = KEYS[PROVIDER];
  // Google's own samples write "models/gemini-…"; the URL adds that part.
  const model = (MODEL || DEFAULT_MODEL[PROVIDER] || "").replace(/^models\//, "");
  if (!key || !model) return null;
  if (!modelLooksRight(PROVIDER, model)) {
    if (!warnedModel) {
      // The value itself is never logged: it may be a key.
      console.error(`survey-ai: AI_SURVEY_MODEL does not look like a ${PROVIDER} model name, photos are off`);
      warnedModel = true;
    }
    return null;
  }
  return { provider: PROVIDER, model, key };
}

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

/** Refusals are 200 + { ok:false, reason } so the page can show its own
 *  plain sentence; the reasons are a fixed list, never provider text. */
const no = (reason: string) => json({ ok: false, reason });

type Img = { data: string; mediaType: string };

/** The provider's own reason for refusing, for the SERVER LOG only (it is
 *  never returned to a page). Without it a refusal is just a number, and
 *  "no credit" looks the same as "bad request". */
async function why(r: Response): Promise<string> {
  try {
    return (await r.text()).replace(/\s+/g, " ").slice(0, 300);
  } catch {
    return "";
  }
}

/** A refusal from the provider, with its HTTP status so the caller can
 *  tell "busy, try again" from "wrong request". */
class ProviderError extends Error {
  constructor(readonly status: number, detail: string) {
    super(`provider ${status} ${detail}`);
  }
}
/** Statuses that mean "not now" rather than "never": overloaded, rate
 *  limited, or a passing server fault. Seen live 10 Nov 2026: Gemini
 *  answered 503 "high demand" twice in a row. */
const RETRYABLE = new Set([429, 500, 502, 503, 504, 529]);
/** Whole budget for one photo check, across both attempts. The page waits
 *  for the answer, so this bounds what a customer sits through. */
const TOTAL_MS = 55_000;
/** A second attempt only starts if at least this much budget is left. */
const RETRY_NEEDS_MS = 20_000;

/** One try, and one more if the provider said "busy" quickly enough to
 *  leave room. Both attempts share one deadline. */
async function askWithRetry(
  cfg: { provider: string; model: string; key: string },
  prompt: string,
  images: Img[],
): Promise<string> {
  const ctl = new AbortController();
  const started = Date.now();
  const timer = setTimeout(() => ctl.abort(), TOTAL_MS);
  try {
    try {
      return await askProvider(cfg, prompt, images, ctl.signal);
    } catch (e) {
      const left = TOTAL_MS - (Date.now() - started);
      if (!(e instanceof ProviderError) || !RETRYABLE.has(e.status) || left < RETRY_NEEDS_MS) {
        throw e;
      }
      console.error("survey-ai provider busy, trying once more:", e.message);
      await new Promise((r) => setTimeout(r, 1500));
      return await askProvider(cfg, prompt, images, ctl.signal);
    }
  } finally {
    clearTimeout(timer);
  }
}

async function askProvider(
  cfg: { provider: string; model: string; key: string },
  prompt: string,
  images: Img[],
  signal: AbortSignal,
): Promise<string> {
  const ctl = { signal };
  {
    if (cfg.provider === "anthropic") {
      const r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        signal: ctl.signal,
        headers: {
          "content-type": "application/json",
          "x-api-key": cfg.key,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: cfg.model,
          max_tokens: 1200,
          messages: [{
            role: "user",
            content: [
              ...images.map((i) => ({
                type: "image",
                source: { type: "base64", media_type: i.mediaType, data: i.data },
              })),
              { type: "text", text: prompt },
            ],
          }],
        }),
      });
      if (!r.ok) throw new ProviderError(r.status, await why(r));
      const j = await r.json();
      return (j.content ?? [])
        .filter((c: { type: string }) => c.type === "text")
        .map((c: { text: string }) => c.text)
        .join("\n");
    }
    if (cfg.provider === "openai") {
      const r = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        signal: ctl.signal,
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${cfg.key}`,
        },
        body: JSON.stringify({
          model: cfg.model,
          response_format: { type: "json_object" },
          messages: [{
            role: "user",
            content: [
              { type: "text", text: prompt },
              ...images.map((i) => ({
                type: "image_url",
                image_url: { url: `data:${i.mediaType};base64,${i.data}` },
              })),
            ],
          }],
        }),
      });
      if (!r.ok) throw new ProviderError(r.status, await why(r));
      const j = await r.json();
      return String(j.choices?.[0]?.message?.content ?? "");
    }
    if (cfg.provider === "gemini") {
      const r = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${
          encodeURIComponent(cfg.model)
        }:generateContent`,
        {
          method: "POST",
          signal: ctl.signal,
          headers: {
            "content-type": "application/json",
            "x-goog-api-key": cfg.key,
          },
          body: JSON.stringify(geminiBody(cfg.model, prompt, images)),
        },
      );
      if (!r.ok) throw new ProviderError(r.status, await why(r));
      const j = await r.json();
      return (j.candidates?.[0]?.content?.parts ?? [])
        .map((p: { text?: string }) => p.text ?? "")
        .join("\n");
    }
    throw new Error("unknown provider");
  }
}

/** Gemini request body. Gemini 3 and 4 models "think" before answering,
 *  at MEDIUM by default (Google's thinking guide, checked 10 Nov 2026), and
 *  a live check with gemini-3.8-flash on one room photo did not answer
 *  within 55 seconds. Counting furniture against a numbered list needs no
 *  deep reasoning, so those models are asked for LOW, which every Gemini 3
 *  and 4 model accepts. Older models (2.x) do not accept the setting at all,
 *  so it is sent only to 3+. */
export function geminiBody(model: string, prompt: string, images: Img[]) {
  const gen: Record<string, unknown> = { responseMimeType: "application/json" };
  const major = Number((/^gemini-(\d+)/.exec(model) ?? [])[1]);
  if (major >= 3) gen.thinkingConfig = { thinkingLevel: "low" };
  return {
    contents: [{
      parts: [
        ...images.map((i) => ({
          inline_data: { mime_type: i.mediaType, data: i.data },
        })),
        { text: prompt },
      ],
    }],
    generationConfig: gen,
  };
}

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const cfg = configured();
  const isStatus = body.action === "status";
  // A status call never gets a reason — only on or off. Anything that
  // would refuse a real request answers "off".
  const off = (reason: string) =>
    isStatus ? json({ ok: true, enabled: false }) : no(reason);
  if (!cfg) return off("not_configured");

  // ---- who is asking, and for which company's catalogue -----------------
  let orgId: string | null = null;
  let userId: string | null = null;
  let linkHash: string | null = null;
  let cats: unknown = null;

  const token = String(body.token ?? "").trim();
  if (token) {
    // Customer: the survey link is the credential. public_get_survey is the
    // same gate the page itself passes (expired / already sent / suspended
    // vendor all refuse here too) and returns the catalogue the customer
    // is shown.
    if (token.length < 20 || token.length > 200) return off("invalid");
    const { data, error } = await admin.rpc("public_get_survey", { p_token: token });
    if (error) return off("unavailable");
    if (!data?.ok) return off(String(data?.reason ?? "invalid"));
    cats = data.survey_cats;
    const { data: row } = await admin
      .from("customer_surveys").select("org_id").eq("token", token).maybeSingle();
    if (!row?.org_id) return off("invalid");
    orgId = row.org_id;
    linkHash = await sha256Hex(token);
  } else {
    // Staff: a real signed-in session that belongs to the company named.
    const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: u } = await admin.auth.getUser(jwt);
    if (!u?.user) return off("not_signed_in");
    userId = u.user.id;
    const wanted = String(body.org_id ?? "");
    const { data: mem } = await admin
      .from("org_members").select("org_id").eq("user_id", userId);
    const mine = (mem ?? []).map((m: { org_id: string }) => m.org_id);
    if (!wanted || !mine.includes(wanted)) return off("not_allowed");
    orgId = wanted;
    cats = body.catalogue;
  }

  // ---- plan: photos are a Pro feature (Trial is Pro for 30 days) --------
  // One read gives the feature, the monthly allowance and whether the
  // company is locked (trial and grace both over). Fails closed: if the
  // plan cannot be read, photos are off. A locked company gets nothing
  // that costs money.
  const planRes = await admin.rpc("org_effective_plan", { p_org_id: orgId });
  if (planRes.error) return off("unavailable");
  const plan = Array.isArray(planRes.data) ? planRes.data[0] : planRes.data;
  if (!plan || typeof plan !== "object") return off("unavailable");
  if (plan.is_locked !== false) return off("not_in_plan");
  if (plan.features?.ai_survey !== true) return off("not_in_plan");
  if (isStatus) return json({ ok: true, enabled: true });

  const lines = flattenCatalogue(cats);
  if (lines.length === 0) return no("no_catalogue");

  const rawImages = Array.isArray(body.images) ? body.images : [];
  if (rawImages.length < 1) return no("no_photos");
  if (rawImages.length > MAX_IMAGES) return no("too_many_photos");
  const images: Img[] = [];
  for (const r of rawImages) {
    const img = readImage(r);
    if (!img) return no("bad_photo");
    images.push(img);
  }
  const room = cleanRoom(body.room);

  // ---- caps, counted from the usage table -------------------------------
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const day = await admin.from("ai_survey_usage")
    .select("id", { count: "exact", head: true })
    .eq("org_id", orgId).gte("created_at", since);
  if (day.error) return no("unavailable");
  if ((day.count ?? 0) >= ORG_DAY_CAP) return no("busy_today");
  if (linkHash) {
    const link = await admin.from("ai_survey_usage")
      .select("id", { count: "exact", head: true })
      .eq("link_hash", linkHash);
    if (link.error) return no("unavailable");
    if ((link.count ?? 0) >= LINK_CAP) return no("link_limit");
  }

  // Monthly allowance from the plan (limits.max_ai_survey_per_month; a
  // missing key or -1 means no monthly limit). Counted per calendar month
  // in India time. A check the provider failed is not charged to the
  // vendor's allowance; one still in flight is.
  const rawCap = plan.limits?.max_ai_survey_per_month;
  const monthCap = rawCap === undefined || rawCap === null ? -1 : Number(rawCap);
  if (!Number.isFinite(monthCap)) return no("unavailable");
  if (monthCap >= 0) {
    const IST = 5.5 * 3600 * 1000;
    const nowIst = new Date(Date.now() + IST);
    const monthStart = new Date(
      Date.UTC(nowIst.getUTCFullYear(), nowIst.getUTCMonth(), 1) - IST,
    ).toISOString();
    const month = await admin.from("ai_survey_usage")
      .select("id", { count: "exact", head: true })
      .eq("org_id", orgId).gte("created_at", monthStart)
      // A row still "in flight" only counts while it could really be in
      // flight. The check gives up after TOTAL_MS, so anything older with
      // no result was cut off (the function was stopped) and was not
      // answered: it must not use up the vendor's allowance for the month.
      .or(`ok.eq.true,and(ok.is.null,created_at.gte.${
        new Date(Date.now() - 10 * 60 * 1000).toISOString()
      })`);
    if (month.error) return no("unavailable");
    if ((month.count ?? 0) >= monthCap) return no("month_limit");
  }

  // Record first: an unrecorded call is an uncapped one.
  const ins = await admin.from("ai_survey_usage").insert({
    org_id: orgId,
    user_id: userId,
    link_hash: linkHash,
    room: room || null,
    photos: images.length,
    provider: cfg.provider,
    model: cfg.model,
  }).select("id").single();
  if (ins.error || !ins.data) return no("unavailable");

  let answer: ReturnType<typeof readAnswer> = null;
  let failed = "";
  try {
    const text = await askWithRetry(cfg, buildPrompt(lines, room), images);
    answer = readAnswer(text, lines);
    if (!answer) failed = "unreadable";
  } catch (e) {
    failed = (e as Error)?.name === "AbortError" ? "timeout" : "provider";
    console.error("survey-ai provider error:", (e as Error)?.message);
  }

  await admin.from("ai_survey_usage").update({
    ok: answer !== null,
    items_found: answer?.items.length ?? null,
    error: failed || null,
  }).eq("id", ins.data.id);

  if (!answer) return no(failed === "timeout" ? "timeout" : "try_again");
  return json({ ok: true, room, items: answer.items, other: answer.other });
});
