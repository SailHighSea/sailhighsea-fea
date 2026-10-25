import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { centsToCellNumber, centsToDecimal } from "./money.ts";

Deno.test("cents become decimal text with integer math", () => {
  assertEquals(centsToDecimal(0), "0.00");
  assertEquals(centsToDecimal(5), "0.05");
  assertEquals(centsToDecimal(1250), "12.50");
  assertEquals(centsToDecimal(100), "1.00");
  assertEquals(centsToDecimal(-300), "-3.00");
  assertEquals(centsToDecimal(2_147_483_647), "21474836.47");
});

Deno.test("no float drift for any cent amount up to 10000.00", () => {
  for (let cents = 0; cents <= 1_000_000; cents++) {
    const text = centsToDecimal(cents);
    const parsed = centsToCellNumber(cents);
    // What the Sheet stores, shown with two decimals, is the same text.
    if (parsed.toFixed(2) !== text) throw new Error(`${cents}: ${text} vs ${parsed}`);
  }
});

Deno.test("the classic 0.1 + 0.2 trap is avoided: 10 + 20 cents is 0.30", () => {
  assertEquals(centsToDecimal(10 + 20), "0.30");
  assertEquals(centsToCellNumber(30), 0.3);
});

Deno.test("non-integer cents are refused", () => {
  assertThrows(() => centsToDecimal(12.5));
  assertThrows(() => centsToDecimal(NaN));
});
