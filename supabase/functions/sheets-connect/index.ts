// POST { action: "start" | "disconnect", household_id }
// Owner only. "start" returns the Google consent URL (the app opens it in a browser).
// "disconnect" revokes the token at Google, deletes it from Vault and forgets the connection;
// the Sheet itself stays in the owner's Drive.
import { corsHeaders, json, redirectUri, requiredEnv, serviceClient, userFromRequest } from "../_shared/common.ts";
import { authUrl, randomToken, revokeToken } from "../_shared/sheets/oauth.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const user = await userFromRequest(req);
  if (!user) return json({ error: "unauthorized" }, 401);

  let body: { action?: string; household_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const household = body.household_id;
  if (!household || (body.action !== "start" && body.action !== "disconnect")) {
    return json({ error: "bad_request" }, 400);
  }

  const db = serviceClient();
  const { data: member } = await db
    .from("members")
    .select("role")
    .eq("household_id", household)
    .eq("user_id", user.id)
    .maybeSingle();
  // Only the owner connects, changes or disconnects the Sheet.
  if (member?.role !== "owner") return json({ error: "forbidden" }, 403);

  if (body.action === "start") {
    const since = new Date(Date.now() - 3600_000).toISOString();
    const { count } = await db
      .from("sheet_oauth_states")
      .select("state", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", since);
    if ((count ?? 0) >= 10) return json({ error: "rate_limited" }, 429);

    const state = randomToken();
    const verifier = randomToken(48);
    const { error } = await db.from("sheet_oauth_states").insert({
      state,
      household_id: household,
      user_id: user.id,
      code_verifier: verifier,
    });
    if (error) {
      console.error("state insert failed", error.message);
      return json({ error: "server_error" }, 500);
    }
    const url = await authUrl({
      clientId: requiredEnv("GOOGLE_CLIENT_ID"),
      redirectUri: redirectUri(),
      state,
      verifier,
    });
    return json({ url });
  }

  // disconnect
  const token = await db.rpc("sheet_read_token", { p_household: household });
  if (typeof token.data === "string" && token.data) {
    const revoked = await revokeToken(token.data);
    if (!revoked) console.warn("Google did not confirm the revoke; removing our copy anyway");
  }
  await db.rpc("sheet_delete_token", { p_household: household });
  await db.from("sheet_sync_queue").delete().eq("household_id", household);
  await db.from("sheet_connections").delete().eq("household_id", household);
  return json({ ok: true });
});
