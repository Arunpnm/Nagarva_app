// Shared by the `whatsapp` and `whatsapp-webhook` functions. Kept in its
// own file so the security-critical pieces — the webhook signature check
// and phone normalising — are tested (wa_util_test.ts), not trusted.

/** Indian mobile to Meta's wa_id form: digits only, country code first. */
export function normalisePhone(raw: string): string | null {
  let d = String(raw ?? "").replace(/\D/g, "");
  if (d.startsWith("00")) d = d.slice(2);
  if (d.length === 11 && d.startsWith("0")) d = d.slice(1);
  if (d.length === 10) {
    // An Indian mobile starts 6-9. A 10-digit number that does not is a
    // landline with its trunk 0 (044 …), and WhatsApp cannot reach it.
    if (!/^[6-9]/.test(d)) return null;
    d = "91" + d;
  }
  if (d.startsWith("91") && d.length === 12 && !/^91[6-9]/.test(d)) return null;
  return d.length >= 11 && d.length <= 15 ? d : null;
}

/** Lower-case hex HMAC-SHA256 of [raw] under [secret]. */
export async function hmacHex(secret: string, raw: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, raw));
  return Array.from(sig).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * True only when [header] is exactly `sha256=<hex>` and the hex is the
 * HMAC of [raw] under [secret]. Constant-time compare; an empty secret,
 * an empty or malformed header, or any other prefix is a refusal.
 */
export async function signatureValid(
  secret: string | null | undefined,
  header: string | null | undefined,
  raw: Uint8Array,
): Promise<boolean> {
  if (!secret || !header || !header.startsWith("sha256=")) return false;
  const given = header.slice(7).toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(given)) return false;
  const want = await hmacHex(secret, raw);
  let d = 0;
  for (let i = 0; i < want.length; i++) d |= want.charCodeAt(i) ^ given.charCodeAt(i);
  return d === 0;
}
