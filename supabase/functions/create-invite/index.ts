// POST { household_id, role: "editor" | "viewer" }
// Owner or admin only (checked inside create_invite_record, which the client cannot call).
// Returns the plain code once; only its HMAC is stored. The code expires in 24 hours.
import { corsHeaders, invitePepper, json, serviceClient, userFromRequest } from "../_shared/common.ts";
import { formatCode, generateCode, hashCode } from "../_shared/code.ts";

const ROLES = new Set(["editor", "viewer"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const user = await userFromRequest(req);
  if (!user) return json({ error: "unauthorized" }, 401);

  let body: { household_id?: string; role?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!body.household_id || !body.role || !ROLES.has(body.role)) {
    return json({ error: "bad_request" }, 400);
  }

  const db = serviceClient();
  const pepper = invitePepper();
  // A collision on the unique hash is astronomically unlikely; retry a few times anyway.
  for (let attempt = 0; attempt < 3; attempt++) {
    const code = generateCode();
    const { data, error } = await db.rpc("create_invite_record", {
      p_household: body.household_id,
      p_user_id: user.id,
      p_role: body.role,
      p_code_hash: await hashCode(code, pepper),
    });
    if (error) {
      if (error.code === "23505") continue;
      console.error("create_invite_record failed", error.message);
      return json({ error: "server_error" }, 500);
    }
    switch (data.status) {
      case "ok":
        return json({
          code,
          display: formatCode(code),
          role: body.role,
          expires_at: data.expires_at,
        });
      case "forbidden":
        return json({ error: "forbidden" }, 403);
      case "rate_limited":
        return json({ error: "rate_limited" }, 429);
      default:
        return json({ error: "bad_request" }, 400);
    }
  }
  return json({ error: "server_error" }, 500);
});
