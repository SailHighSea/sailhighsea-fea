/** PKCE (RFC 7636) and the Google OAuth URLs. Pure helpers so they can be tested. */

const URL_SAFE = /[+/=]/g;

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(URL_SAFE, (c) => (c === "+" ? "-" : c === "/" ? "_" : ""));
}

export function randomToken(bytes = 32, source: (n: number) => Uint8Array = (n) => crypto.getRandomValues(new Uint8Array(n))): string {
  return base64Url(source(bytes));
}

/** code_challenge = BASE64URL(SHA256(verifier)) */
export async function challengeFor(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64Url(new Uint8Array(digest));
}

/** Only files this app created, plus the Sheets API. No access to the rest of Drive. */
export const SCOPES = [
  "https://www.googleapis.com/auth/drive.file",
  "https://www.googleapis.com/auth/spreadsheets",
];

export async function authUrl(opts: { clientId: string; redirectUri: string; state: string; verifier: string }): Promise<string> {
  const params = new URLSearchParams({
    client_id: opts.clientId,
    redirect_uri: opts.redirectUri,
    response_type: "code",
    scope: SCOPES.join(" "),
    access_type: "offline",
    // Always show consent so Google returns a refresh token even on a repeat connect.
    prompt: "consent",
    code_challenge: await challengeFor(opts.verifier),
    code_challenge_method: "S256",
    state: opts.state,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}

export interface TokenResponse {
  refresh_token?: string;
  access_token: string;
  scope?: string;
}

export async function exchangeCode(
  opts: { clientId: string; clientSecret: string; redirectUri: string; code: string; verifier: string },
  doFetch: typeof fetch = fetch,
): Promise<TokenResponse> {
  const res = await doFetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: opts.clientId,
      client_secret: opts.clientSecret,
      redirect_uri: opts.redirectUri,
      grant_type: "authorization_code",
      code: opts.code,
      code_verifier: opts.verifier,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error_description ?? body.error ?? `token exchange failed (${res.status})`);
  return body as TokenResponse;
}

/** Tells Google to forget the token. Failures are not fatal: disconnect still goes ahead. */
export async function revokeToken(token: string, doFetch: typeof fetch = fetch): Promise<boolean> {
  try {
    const res = await doFetch("https://oauth2.googleapis.com/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token }),
    });
    await res.body?.cancel();
    return res.ok;
  } catch {
    return false;
  }
}

/** The scopes Google actually granted must include both; the person can untick them. */
export function hasRequiredScopes(granted: string | undefined): boolean {
  const set = new Set((granted ?? "").split(" "));
  return SCOPES.every((s) => set.has(s));
}
