// GET ?code=...&state=...   (Google sends the browser here after the owner agrees)
// No bearer token: the single-use `state` row, created for the signed-in owner, is the proof.
// Trades the code for tokens (PKCE verifier + client secret stay on the server), creates the
// Sheet, saves the refresh token in Vault and queues every expense for the first copy.
import { redirectUri, requiredEnv, serviceClient } from "../_shared/common.ts";
import { HttpSheetsApi } from "../_shared/sheets/google.ts";
import { exchangeCode, hasRequiredScopes } from "../_shared/sheets/oauth.ts";

function page(title: string, message: string, status = 200): Response {
  const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
  const html = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title>
<style>body{font-family:system-ui,sans-serif;max-width:32rem;margin:4rem auto;padding:0 1.5rem;line-height:1.5}</style>
<h1>${esc(title)}</h1><p>${esc(message)}</p>`;
  return new Response(html, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" },
  });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  const denied = url.searchParams.get("error");

  if (!state) return page("Link expired", "Go back to the app and try connecting again.", 400);
  const db = serviceClient();

  // Single use: take the row away whatever happens next.
  const { data: row } = await db
    .from("sheet_oauth_states")
    .delete()
    .eq("state", state)
    .select("household_id, user_id, code_verifier, created_at")
    .maybeSingle();
  if (!row || Date.now() - new Date(row.created_at).getTime() > 10 * 60_000) {
    return page("Link expired", "Go back to the app and try connecting again.", 400);
  }
  if (denied || !code) {
    return page("Not connected", "Google access was not given, so nothing was connected. You can close this window.");
  }

  const { data: member } = await db
    .from("members")
    .select("role")
    .eq("household_id", row.household_id)
    .eq("user_id", row.user_id)
    .maybeSingle();
  if (member?.role !== "owner") return page("Not allowed", "Only the household owner can connect a Google Sheet.", 403);

  try {
    const tokens = await exchangeCode({
      clientId: requiredEnv("GOOGLE_CLIENT_ID"),
      clientSecret: requiredEnv("GOOGLE_CLIENT_SECRET"),
      redirectUri: redirectUri(),
      code,
      verifier: row.code_verifier,
    });
    if (!tokens.refresh_token) {
      return page("Not connected", "Google did not give long-term access. Remove the app under your Google account permissions and try again.", 400);
    }
    if (!hasRequiredScopes(tokens.scope)) {
      return page("Not connected", "Both permissions are needed (create the Sheet and write to it). Please try again and leave both ticked.", 400);
    }

    const { data: existing } = await db
      .from("sheet_connections")
      .select("spreadsheet_id, spreadsheet_url")
      .eq("household_id", row.household_id)
      .maybeSingle();

    let spreadsheetId = existing?.spreadsheet_id as string | null | undefined;
    let spreadsheetUrl = existing?.spreadsheet_url as string | null | undefined;
    if (!spreadsheetId) {
      const { data: hh } = await db.from("households").select("name").eq("id", row.household_id).single();
      const sheet = await new HttpSheetsApi(tokens.access_token).createSpreadsheet(
        `Family Expenses - ${hh?.name ?? "Household"}`,
      );
      spreadsheetId = sheet.id;
      spreadsheetUrl = sheet.url;
    }

    const { error } = await db.from("sheet_connections").upsert({
      household_id: row.household_id,
      owner_id: row.user_id,
      spreadsheet_id: spreadsheetId,
      spreadsheet_url: spreadsheetUrl,
      status: "pending",
      last_error: null,
      updated_at: new Date().toISOString(),
    });
    if (error) throw new Error(error.message);
    await db.rpc("sheet_store_token", { p_household: row.household_id, p_token: tokens.refresh_token });
    // A reconnect also replays deletes that happened while the connection was revoked.
    await db.rpc("sheet_enqueue_backfill", { p_household: row.household_id, p_include_deleted: !!existing });
    return page("Google Sheet connected", "Your expenses are being copied to the Sheet. You can close this window and go back to the app.");
  } catch (e) {
    console.error("sheets-callback failed", e instanceof Error ? e.message : e);
    return page("Not connected", "Something went wrong while connecting. Go back to the app and try again.", 500);
  }
});

