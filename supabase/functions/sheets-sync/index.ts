// Drains the sheet_sync_queue into the Google Sheet.
//   * Scheduled (pg_cron every 30 s): header x-cron-secret, no body. Handles every household
//     that has rows waiting longer than the 30 s debounce.
//   * "Sync now": a signed-in owner or admin sends { household_id }. Skips the debounce.
import { corsHeaders, json, requiredEnv, serviceClient, userFromRequest } from "../_shared/common.ts";
import { GoogleTokens, HttpSheetsApi } from "../_shared/sheets/google.ts";
import { SupabaseSheetStore } from "../_shared/sheets/store.ts";
import { syncHousehold } from "../_shared/sheets/worker.ts";

function timingSafeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const db = serviceClient();
  const deps = {
    store: new SupabaseSheetStore(db),
    tokens: new GoogleTokens(requiredEnv("GOOGLE_CLIENT_ID"), requiredEnv("GOOGLE_CLIENT_SECRET")),
    sheets: (accessToken: string) => new HttpSheetsApi(accessToken),
  };

  const cron = req.headers.get("x-cron-secret");
  if (cron) {
    if (!timingSafeEqual(cron, requiredEnv("SHEETS_CRON_SECRET"))) return json({ error: "unauthorized" }, 401);
    const { data, error } = await db.rpc("sheet_due_households");
    if (error) return json({ error: "server_error" }, 500);
    const results: Record<string, unknown> = {};
    for (const household of (data ?? []) as string[]) {
      results[household] = await syncHousehold(household, { ...deps, budgetMs: 20_000 });
    }
    return json({ households: Object.keys(results).length });
  }

  const user = await userFromRequest(req);
  if (!user) return json({ error: "unauthorized" }, 401);
  let body: { household_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!body.household_id) return json({ error: "bad_request" }, 400);

  const { data: member } = await db
    .from("members")
    .select("role")
    .eq("household_id", body.household_id)
    .eq("user_id", user.id)
    .maybeSingle();
  // Owner and admins may press Sync now; editors and viewers may not.
  if (member?.role !== "owner" && member?.role !== "admin") return json({ error: "forbidden" }, 403);

  const result = await syncHousehold(body.household_id, { ...deps, budgetMs: 45_000 }, true);
  // Never echo error details from Google to the client beyond a short message.
  return json({ status: result.status, processed: result.processed });
});
