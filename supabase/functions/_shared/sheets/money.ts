/** Money is integer cents everywhere. These helpers never do float arithmetic on amounts. */

/** 1250 -> "12.50", 5 -> "0.05", -300 -> "-3.00". Integer math and string padding only. */
export function centsToDecimal(cents: number): string {
  if (!Number.isInteger(cents)) throw new Error(`cents must be an integer, got ${cents}`);
  const negative = cents < 0;
  const abs = Math.abs(cents);
  const whole = Math.trunc(abs / 100);
  const part = abs % 100;
  return `${negative ? "-" : ""}${whole}.${String(part).padStart(2, "0")}`;
}

/**
 * The value written to the Sheet cell. Sheets stores numbers as doubles, so the closest
 * double to the decimal text is parsed from the string (a parse, not a calculation); every
 * amount up to 2^31 cents prints back as exactly the same two decimals.
 */
export function centsToCellNumber(cents: number): number {
  return Number(centsToDecimal(cents));
}
