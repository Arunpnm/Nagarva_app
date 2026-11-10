// deno test --allow-env --allow-net supabase/functions/survey-ai/model_check_test.ts
// Which AI_SURVEY_MODEL values are accepted. A pasted key must never be.
import { assertEquals } from "jsr:@std/assert@1";
Deno.env.set("SUPABASE_URL", "https://stub.supabase.test");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");
// deno-lint-ignore no-explicit-any
(Deno as any).serve = () => ({});
const { modelLooksRight, geminiBody } = await import("./index.ts");

Deno.test("real model names pass", () => {
  assertEquals(modelLooksRight("gemini", "gemini-3.8-flash"), true);
  assertEquals(modelLooksRight("gemini", "gemini-3.6-flash-lite"), true);
  assertEquals(modelLooksRight("anthropic", "claude-haiku-5-5"), true);
  assertEquals(modelLooksRight("openai", "gpt-5.2-mini"), true);
  assertEquals(modelLooksRight("openai", "o4-mini"), true);
});

Deno.test("keys, provider names and junk are refused", () => {
  // shapes of real keys (made up here, never real values)
  assertEquals(modelLooksRight("gemini", "AQ.Ab8xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"), false);
  assertEquals(modelLooksRight("gemini", "AIzaSyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"), false);
  assertEquals(modelLooksRight("openai", "sk-proj-xxxxxxxxxxxxxxxxxxxx"), false);
  assertEquals(modelLooksRight("openai", "sk-abc"), false);
  assertEquals(modelLooksRight("anthropic", "sk-ant-api03-xxxxxxxx"), false);
  // the provider's own name typed into the model box
  assertEquals(modelLooksRight("gemini", "gemini"), false);
  assertEquals(modelLooksRight("anthropic", "anthropic"), false);
  // wrong family for the provider, spaces, quotes, too long
  assertEquals(modelLooksRight("gemini", "claude-haiku-5-5"), false);
  assertEquals(modelLooksRight("gemini", "gemini 3.8 flash"), false);
  assertEquals(modelLooksRight("gemini", '"gemini-3.8-flash"'), false);
  assertEquals(modelLooksRight("gemini", "gemini-" + "a".repeat(60)), false);
  assertEquals(modelLooksRight("nobody", "gemini-3.8-flash"), false);
});

Deno.test("gemini 3+ is asked to think LOW; older models get no thinking setting", () => {
  const img = [{ data: "/9j/AAAA", mediaType: "image/jpeg" }];
  const b3 = geminiBody("gemini-3.8-flash", "p", img);
  assertEquals(b3.generationConfig, {
    responseMimeType: "application/json",
    thinkingConfig: { thinkingLevel: "low" },
  });
  assertEquals(geminiBody("gemini-4-flash", "p", img).generationConfig.thinkingConfig,
    { thinkingLevel: "low" });
  assertEquals(geminiBody("gemini-2.5-flash", "p", img).generationConfig,
    { responseMimeType: "application/json" });
  assertEquals(b3.contents[0].parts.length, 2); // photo, then the prompt
});
