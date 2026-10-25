// Invite code helpers. Pure functions, no network, so they can be unit tested with `deno test`.

/** 32 characters: no 0, O, 1 or I (docs/SPEC.md section 7). */
export const CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
export const CODE_LENGTH = 8;

/** 8 random characters. 256 is a multiple of 32, so masking a byte has no modulo bias. */
export function generateCode(random: (n: number) => Uint8Array = randomBytes): string {
  const bytes = random(CODE_LENGTH);
  let out = "";
  for (const b of bytes) out += CODE_ALPHABET[b & 31];
  return out;
}

function randomBytes(n: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(n));
}

/** Upper case and drop everything that is not a letter or digit ("k7m-4qx9" becomes "K7M4QX9"). */
export function normalizeCode(input: string): string {
  return input.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export function isValidCodeFormat(code: string): boolean {
  return code.length === CODE_LENGTH && [...code].every((c) => CODE_ALPHABET.includes(c));
}

/** "K7M4QX9X" becomes "K7M4-QX9X": two groups of four. */
export function formatCode(code: string): string {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

/** HMAC-SHA256 (hex) with a server-side secret, so a leaked table cannot be brute forced offline. */
export async function hashCode(code: string, pepper: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(code));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
