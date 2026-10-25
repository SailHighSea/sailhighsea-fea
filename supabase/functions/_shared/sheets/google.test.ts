import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { GoogleError, GoogleTokens, HttpSheetsApi, RevokedError, fetchWithBackoff, type Retry } from "./google.ts";

function scripted(...responses: (Response | Error)[]) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const doFetch = (async (url: string, init?: RequestInit) => {
    calls.push({ url, init });
    const next = responses.shift();
    if (!next) throw new Error("no more scripted responses");
    if (next instanceof Error) throw next;
    return next;
  }) as typeof fetch;
  return { doFetch, calls };
}

function retry(): Retry & { waits: number[] } {
  const waits: number[] = [];
  return {
    attempts: 5,
    baseMs: 1000,
    maxMs: 60_000,
    sleep: async (ms) => void waits.push(ms),
    random: () => 0,
    waits,
  };
}

const ok = (body: unknown = {}) => new Response(JSON.stringify(body), { status: 200 });

Deno.test("backoff doubles on 429 and 5xx, then succeeds", async () => {
  const { doFetch, calls } = scripted(new Response("", { status: 429 }), new Response("", { status: 503 }), ok());
  const r = retry();
  const res = await fetchWithBackoff(doFetch, "https://x", {}, r);
  assertEquals(res.status, 200);
  assertEquals(calls.length, 3);
  assertEquals(r.waits, [1000, 2000]);
});

Deno.test("Retry-After is honoured", async () => {
  const { doFetch } = scripted(new Response("", { status: 429, headers: { "retry-after": "7" } }), ok());
  const r = retry();
  await fetchWithBackoff(doFetch, "https://x", {}, r);
  assertEquals(r.waits, [7000]);
});

Deno.test("gives up after the last attempt", async () => {
  const bad = () => new Response("", { status: 500 });
  const { doFetch, calls } = scripted(bad(), bad(), bad(), bad(), bad());
  await assertRejects(() => fetchWithBackoff(doFetch, "https://x", {}, retry()), GoogleError);
  assertEquals(calls.length, 5);
});

Deno.test("network errors are retried", async () => {
  const { doFetch, calls } = scripted(new TypeError("connection reset"), ok());
  await fetchWithBackoff(doFetch, "https://x", {}, retry());
  assertEquals(calls.length, 2);
});

Deno.test("4xx other than 429 is returned at once", async () => {
  const { doFetch, calls } = scripted(new Response("{}", { status: 403 }));
  const res = await fetchWithBackoff(doFetch, "https://x", {}, retry());
  assertEquals(res.status, 403);
  assertEquals(calls.length, 1);
});

Deno.test("invalid_grant means revoked", async () => {
  const { doFetch } = scripted(
    new Response(JSON.stringify({ error: "invalid_grant", error_description: "Token has been expired or revoked." }), { status: 400 }),
  );
  await assertRejects(() => new GoogleTokens("id", "secret", doFetch, retry()).accessToken("r"), RevokedError);
});

Deno.test("a 401 from the Sheets API means revoked", async () => {
  const { doFetch } = scripted(new Response(JSON.stringify({ error: { message: "bad" } }), { status: 401 }));
  await assertRejects(() => new HttpSheetsApi("t", doFetch, retry()).idRows("s"), RevokedError);
});

Deno.test("idRows maps expense ids to row numbers starting at row 3", async () => {
  const { doFetch } = scripted(ok({ values: [["a"], [], ["c"]] }));
  const rows = await new HttpSheetsApi("t", doFetch, retry()).idRows("s");
  assertEquals([...rows], [["a", 3], ["c", 5]]);
});

Deno.test("deleteRows sends one request, bottom row first", async () => {
  const { doFetch, calls } = scripted(ok());
  await new HttpSheetsApi("t", doFetch, retry()).deleteRows("s", [4, 9, 6]);
  assertEquals(calls.length, 1);
  const body = JSON.parse(calls[0].init!.body as string);
  assertEquals(body.requests.map((r: any) => r.deleteDimension.range.startIndex), [8, 5, 3]);
});

Deno.test("the access token is sent as a bearer header and never in the URL", async () => {
  const { doFetch, calls } = scripted(ok({ values: [] }));
  await new HttpSheetsApi("secret-access", doFetch, retry()).idRows("s");
  assertEquals((calls[0].init!.headers as Record<string, string>).Authorization, "Bearer secret-access");
  assertEquals(calls[0].url.includes("secret-access"), false);
});
