import { centsToCellNumber } from "./money.ts";

export const EXPENSES_TAB = "Expenses";
export const SUMMARY_TAB = "Summary";
export const FIRST_DATA_ROW = 3; // row 1 is the notice, row 2 the headers
export const ID_COLUMN = "K";

export const NOTICE =
  "Read-only copy of your Family Expenses app. The app is the source of truth: anything typed here is overwritten on the next sync.";

export const HEADERS = [
  "Date",
  "Amount",
  "Currency",
  "Category",
  "Merchant/Note",
  "Added by",
  "Account",
  "Receipt link",
  "Created",
  "Updated",
  "expense_id",
] as const;

export type Cell = string | number;

/** An expense as the worker loads it, with the names already looked up. */
export interface SheetExpense {
  id: string;
  amount_cents: number;
  spent_on: string; // yyyy-MM-dd
  note: string;
  category_name: string;
  added_by: string;
  currency: string;
  receipt_path: string | null;
  created_at: string | null;
  updated_at: string;
}

/** Days since 1899-12-30 (Google Sheets' day 0) for a yyyy-MM-dd date, integer math only. */
export function sheetDateSerial(day: string): number {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(day);
  if (!m) throw new Error(`bad date ${day}`);
  const ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Math.round(ms / 86_400_000) + 25_569; // 25569 = days from 1899-12-30 to 1970-01-01
}

function stamp(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toISOString().replace("T", " ").slice(0, 19);
}

export function expenseToRow(e: SheetExpense): Cell[] {
  return [
    sheetDateSerial(e.spent_on),
    centsToCellNumber(e.amount_cents),
    e.currency,
    e.category_name,
    e.note,
    e.added_by,
    "", // Account: the app has no accounts yet
    e.receipt_path ?? "",
    stamp(e.created_at),
    stamp(e.updated_at),
    e.id,
  ];
}

/** Formulas only, so the owner can build on this tab without touching the sync. */
export const SUMMARY_VALUES: Cell[][] = [
  ["Month", "Total", "", "Category", "Total", "", "Added by", "Total"],
  [
    `=SORT(UNIQUE(FILTER(TEXT(${EXPENSES_TAB}!A3:A,"yyyy-mm"),${EXPENSES_TAB}!A3:A<>"")))`,
    `=ARRAYFORMULA(IF(A2:A="","",MAP(A2:A,LAMBDA(m,SUMIFS(${EXPENSES_TAB}!$B$3:$B,${EXPENSES_TAB}!$A$3:$A,">="&DATEVALUE(m&"-01"),${EXPENSES_TAB}!$A$3:$A,"<"&EDATE(DATEVALUE(m&"-01"),1))))))`,
    "",
    `=IFERROR(QUERY(${EXPENSES_TAB}!B3:F,"select D, sum(B) where B is not null group by D order by sum(B) desc label D '', sum(B) ''",0),"")`,
    "",
    "",
    `=IFERROR(QUERY(${EXPENSES_TAB}!B3:F,"select F, sum(B) where B is not null group by F order by sum(B) desc label F '', sum(B) ''",0),"")`,
    "",
  ],
];
