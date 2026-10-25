// POST { code, display_name? }
// Verifies the code, adds the caller to the household with the invite's role and marks the
// invite used. Wrong guesses are rate limited per user and per IP inside redeem_invite.
import {
  clientIp,
  corsHeaders,
  displayNameFor,
  invitePepper,
  json,
  serviceClient,
  userFromRequest,
} from "../_shared/common.ts";
import { hashCode, isValidCodeFormat, normalizeCode } from "../_shared/code.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const user = await userFromRequest(req);
  if (!user) return json({ error: "unauthorized" }, 401);

  let body: { code?: string; display_name?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const code = normalizeCode(String(body.code ?? ""));
  if (!isValidCodeFormat(code)) return json({ error: "invalid_code" }, 400);

  const { data, error } = await serviceClient().rpc("redeem_invite", {
    p_code_hash: await hashCode(code, invitePepper()),
    p_user_id: user.id,
    p_display_name: displayNameFor(user, body.display_name),
    p_ip: clientIp(req),
  });
  if (error) {
    console.error("redeem_invite failed", error.message);
    return json({ error: "server_error" }, 500);
  }
  switch (data.status) {
    case "ok":
      return json({ household_id: data.household_id, role: data.role });
    case "already_member":
      return json({ error: "already_member" }, 409);
    case "rate_limited":
      return json({ error: "rate_limited" }, 429);
    default:
      return json({ error: "invalid_code" }, 400);
  }
});
