// ============================================================
// supabase/functions/_shared/survey_ai_util.ts
//
// AI photo survey (10 Nov 2026) — the parts that need no network:
// flattening the vendor's item catalogue, writing the prompt, and reading
// the model's answer back onto the catalogue.
//
// The model is NEVER trusted for a name or a volume. It answers with line
// NUMBERS from the catalogue it was shown; anything else it mentions goes
// to `other` as plain words for a person to read. So a wrong answer can
// suggest the wrong line, but it can never invent an item, a cft or a
// price — those only ever come from the vendor's own catalogue.
//
// deno test supabase/functions/_shared/survey_ai_util_test.ts
// ============================================================

export type CatalogueSub = { label: string; cft: number };
export type CatalogueItem = { name: string; subs?: CatalogueSub[] };
export type Catalogue = Record<string, CatalogueItem[]>;

export type FlatLine = { cat: string; item: string; sub: string; cft: number };

export type Suggestion = FlatLine & { qty: number };

export const MAX_IMAGES = 4;
/** Base64 characters per image (~1.1 MB of JPEG). The page shrinks photos
 *  to 1280 px first, which lands far below this. */
export const MAX_IMAGE_B64 = 1_500_000;
export const MAX_QTY = 30;
export const MAX_CATALOGUE_LINES = 600;

/** One numbered line per selectable catalogue entry, in catalogue order. */
export function flattenCatalogue(cats: unknown): FlatLine[] {
  const out: FlatLine[] = [];
  if (!cats || typeof cats !== "object" || Array.isArray(cats)) return out;
  for (const [cat, items] of Object.entries(cats as Record<string, unknown>)) {
    if (!Array.isArray(items)) continue;
    for (const it of items) {
      const name = String((it as CatalogueItem)?.name ?? "").trim();
      const subs = (it as CatalogueItem)?.subs;
      if (!name || !Array.isArray(subs)) continue;
      for (const s of subs) {
        const label = String(s?.label ?? "").trim();
        const cft = Number(s?.cft);
        if (!label || !Number.isFinite(cft)) continue;
        out.push({ cat, item: name, sub: label, cft });
        if (out.length >= MAX_CATALOGUE_LINES) return out;
      }
    }
  }
  return out;
}

/** Keeps a room name to something safe to put inside a prompt. */
export function cleanRoom(room: unknown): string {
  return String(room ?? "")
    .replace(/[^\p{L}\p{M}\p{N} &/-]/gu, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 40);
}

export function buildPrompt(lines: FlatLine[], room: string): string {
  const list = lines
    .map((l, i) => `${i + 1}. ${l.item} - ${l.sub} [${l.cat}]`)
    .join("\n");
  return [
    "You are helping a household moving company in India list what must be moved.",
    `The photos show one room${room ? ` (${room})` : ""} of a customer's home.`,
    "Count the movable household items you can clearly see: furniture, appliances, electronics, beds, mattresses, cupboards, boxes and similar.",
    "Do not count fixtures that stay with the house (built-in wardrobes fixed to the wall, ceiling fans, lights, doors, sinks, geysers), people, pets, or small loose things.",
    "The same item may appear in more than one photo. Count each real object once.",
    "",
    "Use ONLY this numbered catalogue. Pick the closest line and size for each item you see:",
    list,
    "",
    "Answer with JSON only, no other text, in exactly this shape:",
    '{"items":[{"n":<catalogue number>,"qty":<count>}],"other":["<short name of a large item you saw that is not in the catalogue>"]}',
    "If you are not sure an item is there, leave it out. If nothing movable is visible, answer {\"items\":[],\"other\":[]}.",
  ].join("\n");
}

/** Pulls the first JSON object out of a model reply (it may be wrapped in
 *  a code fence or a sentence, whatever the prompt says). */
export function extractJson(text: string): unknown {
  const s = String(text ?? "");
  const start = s.indexOf("{");
  if (start < 0) return null;
  let depth = 0, inStr = false, escNext = false;
  for (let i = start; i < s.length; i++) {
    const ch = s[i];
    if (inStr) {
      if (escNext) escNext = false;
      else if (ch === "\\") escNext = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) {
        try {
          return JSON.parse(s.slice(start, i + 1));
        } catch {
          return null;
        }
      }
    }
  }
  return null;
}

/** Maps the model's answer back onto the catalogue. Returns null when the
 *  answer is not the agreed shape at all (so the caller can say "try
 *  again" instead of "nothing found"). */
export function readAnswer(
  text: string,
  lines: FlatLine[],
): { items: Suggestion[]; other: string[] } | null {
  const obj = extractJson(text) as Record<string, unknown> | null;
  if (!obj || typeof obj !== "object" || !Array.isArray(obj.items)) return null;

  const byLine = new Map<number, number>();
  for (const raw of obj.items as unknown[]) {
    const n = Number((raw as Record<string, unknown>)?.n);
    const qty = Math.floor(Number((raw as Record<string, unknown>)?.qty));
    if (!Number.isInteger(n) || n < 1 || n > lines.length) continue;
    if (!Number.isFinite(qty) || qty < 1) continue;
    byLine.set(n, Math.min(MAX_QTY, (byLine.get(n) ?? 0) + qty));
  }
  const items: Suggestion[] = [...byLine.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([n, qty]) => ({ ...lines[n - 1], qty }));

  const other: string[] = [];
  if (Array.isArray(obj.other)) {
    for (const o of obj.other as unknown[]) {
      const t = String(o ?? "")
        .replace(/[\u0000-\u001f<>]/g, " ")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 60);
      if (t && !other.includes(t)) other.push(t);
      if (other.length >= 8) break;
    }
  }
  return { items, other };
}

/** Accepts "data:image/jpeg;base64,...." or bare base64. Returns the bare
 *  base64 and its media type, or null when it is not a JPEG/PNG/WebP of a
 *  sane size. Checked by the file's own first bytes, not by its label. */
export function readImage(
  raw: unknown,
): { data: string; mediaType: string } | null {
  let s = String(raw ?? "");
  const comma = s.indexOf(",");
  if (s.startsWith("data:") && comma > 0) s = s.slice(comma + 1);
  s = s.replace(/\s+/g, "");
  if (s.length < 200 || s.length > MAX_IMAGE_B64) return null;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(s)) return null;
  if (s.startsWith("/9j/")) return { data: s, mediaType: "image/jpeg" };
  if (s.startsWith("iVBORw0KGgo")) return { data: s, mediaType: "image/png" };
  if (s.startsWith("UklGR")) return { data: s, mediaType: "image/webp" };
  return null;
}
