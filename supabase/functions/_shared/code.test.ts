import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import {
  CODE_ALPHABET,
  formatCode,
  generateCode,
  hashCode,
  isValidCodeFormat,
  normalizeCode,
} from "./code.ts";

Deno.test("alphabet has 32 characters and no 0 O 1 I", () => {
  assertEquals(CODE_ALPHABET.length, 32);
  for (const c of "0O1I") assert(!CODE_ALPHABET.includes(c));
});

Deno.test("generated codes are 8 valid characters", () => {
  for (let i = 0; i < 500; i++) assert(isValidCodeFormat(generateCode()));
});

Deno.test("every byte value maps into the alphabet", () => {
  const all = new Uint8Array(256).map((_, i) => i);
  const out = generateCode(() => all.slice(0, 8));
  assert(isValidCodeFormat(out));
  assert(isValidCodeFormat(generateCode(() => all.slice(248, 256))));
});

Deno.test("normalize and format", () => {
  assertEquals(normalizeCode(" k7m-4qx9 "), "K7M4QX9");
  assertEquals(formatCode("K7M4QX9X"), "K7M4-QX9X");
  assert(!isValidCodeFormat("K7M4QX90"));
  assert(!isValidCodeFormat("K7M4QX9"));
});

Deno.test("hash depends on the code and the secret", async () => {
  const a = await hashCode("K7M4QX9X", "pepper");
  assertEquals(a.length, 64);
  assertEquals(a, await hashCode("K7M4QX9X", "pepper"));
  assertNotEquals(a, await hashCode("K7M4QX9Y", "pepper"));
  assertNotEquals(a, await hashCode("K7M4QX9X", "other"));
});
