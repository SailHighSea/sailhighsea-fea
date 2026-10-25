import { RevokedError, type SheetsApi, type TokenApi } from "./google.ts";
import { type SheetExpense, expenseToRow } from "./layout.ts";

export interface QueueItem {
  expense_id: string;
  op: "upsert" | "delete";
  enqueued_at: string;
}

export interface Connection {
  household_id: string;
  spreadsheet_id: string | null;
  status: "pending" | "active" | "error" | "revoked";
}

/** Everything the worker needs from the database. The edge function backs it with Supabase. */
export interface SheetStore {
  connection(household: string): Promise<Connection | null>;
  claim(household: string, limit: number, force: boolean): Promise<QueueItem[]>;
  /** Expenses (with category and member names) that still exist; missing ids are deleted ones. */
  expenses(household: string, ids: string[]): Promise<SheetExpense[]>;
  readToken(household: string): Promise<string | null>;
  ack(household: string, items: { expense_id: string; enqueued_at: string }[]): Promise<void>;
  release(household: string): Promise<void>;
  setStatus(household: string, status: "active" | "error" | "revoked", error?: string | null): Promise<void>;
}

export interface WorkerDeps {
  store: SheetStore;
  tokens: TokenApi;
  /** Builds the Sheets client for a fresh access token. */
  sheets: (accessToken: string) => SheetsApi;
  batchSize?: number;
  /** Stops starting new batches after this many ms (the function has a time limit). */
  budgetMs?: number;
  now?: () => number;
}

export interface RunResult {
  processed: number;
  batches: number;
  status: "idle" | "ok" | "revoked" | "error" | "no_connection";
  error?: string;
}

/**
 * Writes the queued expenses of one household to its Sheet. Safe to run twice: rows are
 * found by expense_id, so a second run updates instead of adding.
 */
export async function syncHousehold(household: string, deps: WorkerDeps, force = false): Promise<RunResult> {
  const { store } = deps;
  const batchSize = deps.batchSize ?? 500;
  const now = deps.now ?? Date.now;
  const deadline = now() + (deps.budgetMs ?? 45_000);

  const conn = await store.connection(household);
  if (!conn || !conn.spreadsheet_id) return { processed: 0, batches: 0, status: "no_connection" };
  if (conn.status === "revoked") return { processed: 0, batches: 0, status: "revoked" };

  let processed = 0;
  let batches = 0;
  let accessToken: string | null = null;

  try {
    while (now() < deadline) {
      const batch = await store.claim(household, batchSize, force);
      if (batch.length === 0) break;
      batches++;
      if (accessToken === null) {
        const refresh = await store.readToken(household);
        if (!refresh) throw new RevokedError("no saved Google token");
        accessToken = await deps.tokens.accessToken(refresh);
      }
      const api = deps.sheets(accessToken);
      await writeBatch(api, conn.spreadsheet_id, batch, await store.expenses(household, batch.map((b) => b.expense_id)));
      await store.ack(household, batch.map((b) => ({ expense_id: b.expense_id, enqueued_at: b.enqueued_at })));
      processed += batch.length;
    }
    if (batches > 0) await store.setStatus(household, "active", null);
    return { processed, batches, status: batches === 0 ? "idle" : "ok" };
  } catch (e) {
    await store.release(household);
    const message = e instanceof Error ? e.message : String(e);
    if (e instanceof RevokedError) {
      await store.setStatus(household, "revoked", message);
      return { processed, batches, status: "revoked", error: message };
    }
    await store.setStatus(household, "error", message);
    return { processed, batches, status: "error", error: message };
  }
}

/** One batch: update rows that exist, append new ones, remove deleted ones. */
export async function writeBatch(
  api: SheetsApi,
  spreadsheetId: string,
  batch: QueueItem[],
  existing: SheetExpense[],
): Promise<void> {
  const byId = new Map(existing.map((e) => [e.id, e]));
  const rowOf = await api.idRows(spreadsheetId);

  const updates: { row: number; values: (string | number)[] }[] = [];
  const appends: (string | number)[][] = [];
  const removals: number[] = [];

  for (const item of batch) {
    const expense = byId.get(item.expense_id);
    const row = rowOf.get(item.expense_id);
    if (item.op === "delete" || !expense) {
      if (row !== undefined) removals.push(row);
      continue;
    }
    const values = expenseToRow(expense);
    if (row !== undefined) updates.push({ row, values });
    else appends.push(values);
  }

  // Order matters: updates and appends never move existing rows, deletes do, so they go last.
  await api.updateRows(spreadsheetId, updates);
  await api.appendRows(spreadsheetId, appends);
  await api.deleteRows(spreadsheetId, removals);
}
