// deno test supabase/functions/_shared/wa_util_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { hmacHex, normalisePhone, signatureValid } from "./wa_util.ts";

const body = new TextEncoder().encode('{"object":"whatsapp_business_account"}');

Deno.test("normalisePhone: the formats vendors actually type", () => {
  assertEquals(normalisePhone("98450 11001"), "919845011001");
  assertEquals(normalisePhone("+91 98450-11001"), "919845011001");
  assertEquals(normalisePhone("919845011001"), "919845011001");
  assertEquals(normalisePhone("09845011001"), "919845011001");
  assertEquals(normalisePhone("0091 98450 11001"), "919845011001");
  assertEquals(normalisePhone("+1 415 555 0100"), "14155550100");
});

Deno.test("normalisePhone: refuses what is not a mobile", () => {
  assertEquals(normalisePhone(""), null);
  assertEquals(normalisePhone("12345"), null);
  assertEquals(normalisePhone("044 2345 678"), null); // Chennai landline
  assertEquals(normalisePhone("044 2345 6789"), null); // landline, 11 digits
  assertEquals(normalisePhone("+91 44 2345 6789"), null);
  assertEquals(normalisePhone("5845011001"), null); // not a mobile series
  assertEquals(normalisePhone("1234567890123456"), null);
});

Deno.test("signatureValid: accepts Meta's exact header", async () => {
  const h = "sha256=" + (await hmacHex("app-secret", body));
  assertEquals(await signatureValid("app-secret", h, body), true);
  // Meta sends lower-case; upper-case hex still means the same digest.
  assertEquals(await signatureValid("app-secret", h.toUpperCase().replace("SHA256=", "sha256="), body), true);
});

Deno.test("signatureValid: every forgery shape is refused", async () => {
  const good = await hmacHex("app-secret", body);
  assertEquals(await signatureValid("other-secret", "sha256=" + good, body), false);
  assertEquals(await signatureValid("app-secret", "sha256=" + good, new TextEncoder().encode("{}")), false);
  assertEquals(await signatureValid("app-secret", good, body), false); // no prefix
  assertEquals(await signatureValid("app-secret", "sha1=" + good, body), false);
  assertEquals(await signatureValid("app-secret", "sha256=", body), false);
  assertEquals(await signatureValid("app-secret", "sha256=" + good.slice(0, 63), body), false);
  assertEquals(await signatureValid("app-secret", "sha256=" + good + "00", body), false);
  assertEquals(await signatureValid("", "sha256=" + good, body), false); // no secret stored
  assertEquals(await signatureValid(null, "sha256=" + good, body), false);
  assertEquals(await signatureValid("app-secret", null, body), false);
  // An HMAC of the body under an EMPTY key must not pass for an org with no secret.
  const emptyKey = await hmacHex("", body).catch(() => "");
  assertEquals(await signatureValid("", "sha256=" + emptyKey, body), false);
});
