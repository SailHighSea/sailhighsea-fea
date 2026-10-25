import { assertEquals } from "jsr:@std/assert@1";
import { RevokedError, type SheetsApi, type TokenApi } from "./google.ts";
import { type Cell, FIRST_DATA_ROW, type SheetExpense, expenseToRow, sheetDateSerial } from "./layout.ts";
import { type Connection, type QueueItem, type SheetStore, syncHousehold } from "./worker.ts";

const H = "h1";

function expense(id: string, cents: number, note = ""): SheetExpense {
  return {
    id,
    amount_cents: cents,
    spent_on: "2026-10-23",
    note,
    category_name: "Food",
    added_by: "Maya",
    currency: "SGD",
    receipt_path: null,
    created_at: "2026-10-23T04:00:00Z",
    updated_at: "2026-10-23T04:00:00Z",
  };
}

/** A Sheet in memory: row 3 and below, last column is the expense id. */
class FakeSheet implements SheetsApi {
  rows: Cell[][] = [];
  calls: string[] = [];
  failNext = 0;
  async createSpreadsheet() {
    return { id: "sheet1", url: "https://docs.google.com/spreadsheets/d/sheet1" };
  }
  private maybeFail() {
    if (this.failNext > 0) {
      this.failNext--;
      throw new Error("Sheets API 503");
    }
  }
  async idRows() {
    const m = new Map<string, number>();
    this.rows.forEach((r, i) => m.set(String(r[10]), FIRST_DATA_ROW + i));
    return m;
  }
  async updateRows(_: string, rows: { row: number; values: Cell[] }[]) {
    this.maybeFail();
    this.calls.push(`update:${rows.length}`);
    for (const r of rows) this.rows[r.row - FIRST_DATA_ROW] = r.values;
  }
  async appendRows(_: string, values: Cell[][]) {
    this.maybeFail();
    this.calls.push(`append:${values.length}`);
    this.rows.push(...values);
  }
  async deleteRows(_: string, rows: number[]) {
    this.maybeFail();
    this.calls.push(`delete:${rows.length}`);
    for (const r of [...rows].sort((a, b) => b - a)) this.rows.splice(r - FIRST_DATA_ROW, 1);
  }
  ids() {
    return this.rows.map((r) => String(r[10]));
  }
}

class FakeStore implements SheetStore {
  queue = new Map<string, QueueItem & { claimed: boolean }>();
  expensesById = new Map<string, SheetExpense>();
  conn: Connection = { household_id: H, spreadsheet_id: "sheet1", status: "pending" };
  token: string | null = "refresh-1";
  statuses: string[] = [];
  lastError: string | null = null;
  tick = 0;

  enqueue(id: string, op: "upsert" | "delete") {
    this.queue.set(id, { expense_id: id, op, enqueued_at: `t${++this.tick}`, claimed: false });
  }
  async connection() {
    return this.conn;
  }
  async claim(_: string, limit: number) {
    const due = [...this.queue.values()].filter((q) => !q.claimed).slice(0, limit);
    due.forEach((q) => (q.claimed = true));
    return due.map(({ claimed: _c, ...item }) => item);
  }
  async expenses(_: string, ids: string[]) {
    return ids.flatMap((id) => (this.expensesById.has(id) ? [this.expensesById.get(id)!] : []));
  }
  async readToken() {
    return this.token;
  }
  async ack(_: string, items: { expense_id: string; enqueued_at: string }[]) {
    for (const i of items) {
      const q = this.queue.get(i.expense_id);
      if (q && q.enqueued_at === i.enqueued_at) this.queue.delete(i.expense_id);
    }
  }
  async release() {
    this.queue.forEach((q) => (q.claimed = false));
  }
  async setStatus(_: string, status: "active" | "error" | "revoked", error?: string | null) {
    this.conn.status = status;
    this.statuses.push(status);
    this.lastError = error ?? null;
  }
}

const tokens: TokenApi = { accessToken: async () => "access-1" };

function setup() {
  const store = new FakeStore();
  const sheet = new FakeSheet();
  const run = (force = false, extra: Partial<Parameters<typeof syncHousehold>[1]> = {}) =>
    syncHousehold(H, { store, tokens, sheets: () => sheet, ...extra }, force);
  return { store, sheet, run };
}

Deno.test("a new expense is appended", async () => {
  const { store, sheet, run } = setup();
  store.expensesById.set("e1", expense("e1", 1250, "Lunch"));
  store.enqueue("e1", "upsert");
  const r = await run();
  assertEquals(r.status, "ok");
  assertEquals(sheet.ids(), ["e1"]);
  assertEquals(sheet.rows[0][1], 12.5);
  assertEquals(sheet.rows[0][0], sheetDateSerial("2026-10-23"));
  assertEquals(store.queue.size, 0);
  assertEquals(store.conn.status, "active");
});

Deno.test("an edit updates the same row (found by expense_id)", async () => {
  const { store, sheet, run } = setup();
  store.expensesById.set("e1", expense("e1", 1250, "Lunch"));
  store.expensesById.set("e2", expense("e2", 300, "Coffee"));
  store.enqueue("e1", "upsert");
  store.enqueue("e2", "upsert");
  await run();
  store.expensesById.set("e1", expense("e1", 1500, "Lunch and dessert"));
  store.enqueue("e1", "upsert");
  await run();
  assertEquals(sheet.ids(), ["e1", "e2"]);
  assertEquals(sheet.rows[0][1], 15);
  assertEquals(sheet.rows[0][4], "Lunch and dessert");
});

Deno.test("a soft delete removes the row; deleting something never added is harmless", async () => {
  const { store, sheet, run } = setup();
  for (const id of ["e1", "e2", "e3"]) {
    store.expensesById.set(id, expense(id, 100));
    store.enqueue(id, "upsert");
  }
  await run();
  store.expensesById.delete("e2");
  store.enqueue("e2", "delete");
  store.enqueue("never-added", "delete");
  await run();
  assertEquals(sheet.ids(), ["e1", "e3"]);
});

Deno.test("deleting several rows in one batch keeps the right ones", async () => {
  const { store, sheet, run } = setup();
  for (const id of ["a", "b", "c", "d", "e"]) {
    store.expensesById.set(id, expense(id, 100));
    store.enqueue(id, "upsert");
  }
  await run();
  for (const id of ["b", "d"]) store.enqueue(id, "delete");
  await run();
  assertEquals(sheet.ids(), ["a", "c", "e"]);
});

Deno.test("re-running is idempotent: no duplicate rows", async () => {
  const { store, sheet, run } = setup();
  store.expensesById.set("e1", expense("e1", 1250));
  store.enqueue("e1", "upsert");
  await run();
  // The same change is queued again (for example after a crash before the ack).
  store.enqueue("e1", "upsert");
  await run();
  store.enqueue("e1", "upsert");
  await run();
  assertEquals(sheet.ids(), ["e1"]);
});

Deno.test("a change made while the run is going stays queued", async () => {
  const { store, sheet, run } = setup();
  store.expensesById.set("e1", expense("e1", 100));
  store.enqueue("e1", "upsert");
  const original = sheet.appendRows.bind(sheet);
  sheet.appendRows = async (id, values) => {
    await original(id, values);
    store.enqueue("e1", "upsert"); // edited again mid-run: newer enqueued_at
  };
  await run();
  assertEquals(store.queue.size, 1, "the newer change is not acknowledged");
});

Deno.test("backfill is chunked and resumes after a failure", async () => {
  const { store, sheet, run } = setup();
  for (let i = 0; i < 25; i++) {
    store.expensesById.set(`e${i}`, expense(`e${i}`, 100 + i));
    store.enqueue(`e${i}`, "upsert");
  }
  sheet.failNext = 0;
  // Fail on the second batch's append.
  let appends = 0;
  const original = sheet.appendRows.bind(sheet);
  sheet.appendRows = async (id, values) => {
    if (++appends === 2) throw new Error("Sheets API 503");
    await original(id, values);
  };
  const first = await run(false, { batchSize: 10 });
  assertEquals(first.status, "error");
  assertEquals(sheet.rows.length, 10, "the first chunk made it");
  assertEquals(store.queue.size, 15, "the rest is still queued");
  assertEquals(store.conn.status, "error");

  const second = await run(false, { batchSize: 10 });
  assertEquals(second.status, "ok");
  assertEquals(sheet.rows.length, 25);
  assertEquals(new Set(sheet.ids()).size, 25, "no duplicates after resuming");
  assertEquals(store.queue.size, 0);
  assertEquals(store.conn.status, "active");
});

Deno.test("a revoked token marks the connection revoked and keeps the queue", async () => {
  const { store, sheet, run } = setup();
  store.expensesById.set("e1", expense("e1", 100));
  store.enqueue("e1", "upsert");
  const r = await run(false, {
    tokens: {
      accessToken: async () => {
        throw new RevokedError("Token has been expired or revoked.");
      },
    },
  });
  assertEquals(r.status, "revoked");
  assertEquals(store.conn.status, "revoked");
  assertEquals(store.lastError, "Token has been expired or revoked.");
  assertEquals(store.queue.size, 1);
  assertEquals(sheet.rows.length, 0);
  // Once revoked it does nothing until the owner reconnects.
  assertEquals((await run()).status, "revoked");
});

Deno.test("a missing token counts as revoked", async () => {
  const { store, run } = setup();
  store.token = null;
  store.expensesById.set("e1", expense("e1", 100));
  store.enqueue("e1", "upsert");
  assertEquals((await run()).status, "revoked");
});

Deno.test("no connection or no sheet: nothing happens", async () => {
  const { store, run } = setup();
  store.conn = { household_id: H, spreadsheet_id: null, status: "pending" };
  assertEquals((await run()).status, "no_connection");
});

Deno.test("an empty queue is idle and does not touch Google", async () => {
  const { sheet, run } = setup();
  assertEquals((await run()).status, "idle");
  assertEquals(sheet.calls, []);
});

Deno.test("an expense that vanished before the run is treated as deleted", async () => {
  const { store, sheet, run } = setup();
  store.expensesById.set("e1", expense("e1", 100));
  store.enqueue("e1", "upsert");
  await run();
  store.expensesById.delete("e1"); // hard-deleted or household lost it
  store.enqueue("e1", "upsert");
  await run();
  assertEquals(sheet.ids(), []);
});

Deno.test("expenseToRow: columns, number amount, hidden id last", () => {
  const row = expenseToRow({ ...expense("abc", 5, "Gum"), receipt_path: "r/1.jpg" });
  assertEquals(row.length, 11);
  assertEquals(row[1], 0.05);
  assertEquals(row[2], "SGD");
  assertEquals(row[4], "Gum");
  assertEquals(row[7], "r/1.jpg");
  assertEquals(row[8], "2026-10-23 04:00:00");
  assertEquals(row[10], "abc");
});

Deno.test("sheetDateSerial matches Google's day numbers", () => {
  assertEquals(sheetDateSerial("1899-12-30"), 0);
  assertEquals(sheetDateSerial("1970-01-01"), 25569);
  assertEquals(sheetDateSerial("2026-10-23"), 46318);
});
