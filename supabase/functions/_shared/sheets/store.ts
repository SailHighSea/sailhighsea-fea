import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { SheetExpense } from "./layout.ts";
import type { Connection, QueueItem, SheetStore } from "./worker.ts";

/** The worker's database access, through the service role (RLS does not apply). */
export class SupabaseSheetStore implements SheetStore {
  constructor(private db: SupabaseClient) {}

  async connection(household: string): Promise<Connection | null> {
    const { data, error } = await this.db
      .from("sheet_connections")
      .select("household_id, spreadsheet_id, status")
      .eq("household_id", household)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data as Connection | null;
  }

  async claim(household: string, limit: number, force: boolean): Promise<QueueItem[]> {
    const { data, error } = await this.db.rpc("sheet_claim_batch", {
      p_household: household,
      p_limit: limit,
      p_force: force,
    });
    if (error) throw new Error(error.message);
    return (data ?? []) as QueueItem[];
  }

  async expenses(household: string, ids: string[]): Promise<SheetExpense[]> {
    if (ids.length === 0) return [];
    const [expenses, categories, members, hh] = await Promise.all([
      this.db
        .from("expenses")
        .select("id, amount_cents, spent_on, note, category_id, created_by, receipt_path, created_at, updated_at, deleted_at")
        .eq("household_id", household)
        .in("id", ids),
      this.db.from("categories").select("id, name").eq("household_id", household),
      this.db.from("members").select("user_id, display_name").eq("household_id", household),
      this.db.from("households").select("currency").eq("id", household).single(),
    ]);
    for (const r of [expenses, categories, members, hh]) if (r.error) throw new Error(r.error.message);
    const categoryName = new Map((categories.data ?? []).map((c) => [c.id as string, c.name as string]));
    const memberName = new Map((members.data ?? []).map((m) => [m.user_id as string, m.display_name as string]));
    const currency = (hh.data?.currency as string) ?? "SGD";
    return (expenses.data ?? [])
      .filter((e) => e.deleted_at === null)
      .map((e) => ({
        id: e.id as string,
        amount_cents: e.amount_cents as number,
        spent_on: e.spent_on as string,
        note: e.note as string,
        category_name: categoryName.get(e.category_id as string) ?? "Other",
        added_by: memberName.get(e.created_by as string) ?? "Former member",
        currency,
        receipt_path: e.receipt_path as string | null,
        created_at: e.created_at as string,
        updated_at: e.updated_at as string,
      }));
  }

  async readToken(household: string): Promise<string | null> {
    const { data, error } = await this.db.rpc("sheet_read_token", { p_household: household });
    if (error) throw new Error(error.message);
    return (data as string | null) ?? null;
  }

  async ack(household: string, items: { expense_id: string; enqueued_at: string }[]) {
    const { error } = await this.db.rpc("sheet_ack", { p_household: household, p_items: items });
    if (error) throw new Error(error.message);
  }

  async release(household: string) {
    await this.db.rpc("sheet_release", { p_household: household });
  }

  async setStatus(household: string, status: "active" | "error" | "revoked", error?: string | null) {
    await this.db.rpc("sheet_set_status", {
      p_household: household,
      p_status: status,
      // Keep the message short and free of anything secret.
      p_error: error ? error.slice(0, 300) : null,
    });
  }
}
