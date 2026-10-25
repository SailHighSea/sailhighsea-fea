import { assert, assertEquals } from "jsr:@std/assert@1";
import { authUrl, challengeFor, exchangeCode, hasRequiredScopes, randomToken, revokeToken } from "./oauth.ts";

Deno.test("PKCE challenge matches the RFC 7636 example", async () => {
  assertEquals(
    await challengeFor("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
    "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
  );
});

Deno.test("random tokens are URL safe and different", () => {
  const a = randomToken();
  const b = randomToken();
  assert(/^[A-Za-z0-9_-]{43}$/.test(a));
  assert(a !== b);
});

Deno.test("auth URL asks for offline access, PKCE and only the two narrow scopes", async () => {
  const url = new URL(await authUrl({ clientId: "cid", redirectUri: "https://x/cb", state: "s1", verifier: "v".repeat(43) }));
  const p = url.searchParams;
  assertEquals(p.get("access_type"), "offline");
  assertEquals(p.get("code_challenge_method"), "S256");
  assertEquals(p.get("state"), "s1");
  assertEquals(p.get("scope"), "https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/spreadsheets");
  assert(!p.has("code_verifier"), "the verifier never goes in the URL");
});

Deno.test("code exchange sends the verifier and secret in the body", async () => {
  let seen: URLSearchParams | undefined;
  const fake = (async (_u: string, init?: RequestInit) => {
    seen = init!.body as URLSearchParams;
    return new Response(JSON.stringify({ access_token: "a", refresh_token: "r" }), { status: 200 });
  }) as typeof fetch;
  const t = await exchangeCode(
    { clientId: "cid", clientSecret: "sec", redirectUri: "https://x/cb", code: "c", verifier: "ver" },
    fake,
  );
  assertEquals(t.refresh_token, "r");
  assertEquals(seen!.get("code_verifier"), "ver");
  assertEquals(seen!.get("grant_type"), "authorization_code");
});

Deno.test("revoke reports failure instead of throwing", async () => {
  const boom = (async () => {
    throw new TypeError("offline");
  }) as typeof fetch;
  assertEquals(await revokeToken("t", boom), false);
});

Deno.test("both scopes must be granted", () => {
  assert(hasRequiredScopes("a https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/spreadsheets"));
  assert(!hasRequiredScopes("https://www.googleapis.com/auth/drive.file"));
  assert(!hasRequiredScopes(undefined));
});
