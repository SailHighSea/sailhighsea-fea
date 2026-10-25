import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing secret ${name}`);
  return v;
}

/** Server-side client that bypasses RLS. Never leaves the edge function. */
export function serviceClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
}

/** The signed-in user from the request's bearer token, or null. */
export async function userFromRequest(req: Request): Promise<User | null> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data, error } = await serviceClient().auth.getUser(token);
  return error ? null : data.user;
}

/** Set with `supabase secrets set INVITE_PEPPER=<long random string>`. */
export function invitePepper(): string {
  return env("INVITE_PEPPER");
}

export function clientIp(req: Request): string | null {
  const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || req.headers.get("cf-connecting-ip") || null;
}

export function displayNameFor(user: User, requested?: unknown): string {
  const fromBody = typeof requested === "string" ? requested.trim() : "";
  const meta = user.user_metadata ?? {};
  const candidate = fromBody || meta.full_name || meta.name || user.email?.split("@")[0] || "Member";
  return String(candidate).slice(0, 60);
}
