import { type Cell, EXPENSES_TAB, FIRST_DATA_ROW, HEADERS, ID_COLUMN, NOTICE, SUMMARY_TAB, SUMMARY_VALUES } from "./layout.ts";

/** Google no longer accepts the saved token: the owner has to connect again. */
export class RevokedError extends Error {}

/** Google answered with an error that retrying will not fix. */
export class GoogleError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

export interface SheetsApi {
  createSpreadsheet(title: string): Promise<{ id: string; url: string }>;
  /** expense_id -> 1-based row number on the Expenses tab. */
  idRows(spreadsheetId: string): Promise<Map<string, number>>;
  updateRows(spreadsheetId: string, rows: { row: number; values: Cell[] }[]): Promise<void>;
  appendRows(spreadsheetId: string, values: Cell[][]): Promise<void>;
  /** Deletes the rows (1-based) in one request, bottom first so numbers do not shift. */
  deleteRows(spreadsheetId: string, rows: number[]): Promise<void>;
}

export interface TokenApi {
  /** Trades the saved refresh token for a short-lived access token. Throws RevokedError. */
  accessToken(refreshToken: string): Promise<string>;
}

export interface Retry {
  attempts: number;
  baseMs: number;
  maxMs: number;
  sleep: (ms: number) => Promise<void>;
  random: () => number;
}

export const defaultRetry: Retry = {
  attempts: 5,
  baseMs: 1000,
  maxMs: 60_000,
  sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
  random: Math.random,
};

/** fetch with exponential backoff on 429 and 5xx (and on network errors). */
export async function fetchWithBackoff(
  doFetch: typeof fetch,
  input: string,
  init: RequestInit,
  retry: Retry = defaultRetry,
): Promise<Response> {
  let last: unknown;
  for (let attempt = 0; attempt < retry.attempts; attempt++) {
    try {
      const res = await doFetch(input, init);
      if (res.status !== 429 && res.status < 500) return res;
      last = new GoogleError(`Google answered ${res.status}`, res.status);
      const retryAfter = Number(res.headers.get("retry-after"));
      await res.body?.cancel();
      if (attempt < retry.attempts - 1) {
        const backoff = Math.min(retry.maxMs, retry.baseMs * 2 ** attempt);
        const wait = retryAfter > 0 ? Math.min(retry.maxMs, retryAfter * 1000) : backoff;
        await retry.sleep(wait + Math.floor(retry.random() * 250));
      }
    } catch (e) {
      if (e instanceof GoogleError) throw e;
      last = e;
      if (attempt < retry.attempts - 1) {
        await retry.sleep(Math.min(retry.maxMs, retry.baseMs * 2 ** attempt));
      }
    }
  }
  throw last instanceof Error ? last : new Error("request failed");
}

export class GoogleTokens implements TokenApi {
  constructor(
    private clientId: string,
    private clientSecret: string,
    private doFetch: typeof fetch = fetch,
    private retry: Retry = defaultRetry,
  ) {}

  async accessToken(refreshToken: string): Promise<string> {
    const res = await fetchWithBackoff(this.doFetch, "https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.clientId,
        client_secret: this.clientSecret,
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      }),
    }, this.retry);
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      // invalid_grant: the person removed access, the token expired (app still in Testing),
      // or the password changed.
      if (body.error === "invalid_grant" || body.error === "unauthorized_client") {
        throw new RevokedError(body.error_description ?? body.error);
      }
      throw new GoogleError(body.error_description ?? `token request failed (${res.status})`, res.status);
    }
    return body.access_token as string;
  }
}

const SHEETS = "https://sheets.googleapis.com/v4/spreadsheets";

export class HttpSheetsApi implements SheetsApi {
  constructor(
    private accessToken: string,
    private doFetch: typeof fetch = fetch,
    private retry: Retry = defaultRetry,
  ) {}

  private async call(method: string, url: string, body?: unknown): Promise<any> {
    const res = await fetchWithBackoff(this.doFetch, url, {
      method,
      headers: { Authorization: `Bearer ${this.accessToken}`, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    }, this.retry);
    const text = await res.text();
    const data = text ? JSON.parse(text) : {};
    if (res.status === 401) throw new RevokedError("Google rejected the access token");
    if (!res.ok) throw new GoogleError(data.error?.message ?? `Sheets API ${res.status}`, res.status);
    return data;
  }

  async createSpreadsheet(title: string) {
    const created = await this.call("POST", SHEETS, {
      properties: { title },
      sheets: [
        { properties: { sheetId: 0, title: EXPENSES_TAB, gridProperties: { frozenRowCount: 2 } } },
        { properties: { sheetId: 1, title: SUMMARY_TAB } },
      ],
    });
    const id = created.spreadsheetId as string;
    await this.call("POST", `${SHEETS}/${id}/values:batchUpdate`, {
      valueInputOption: "USER_ENTERED",
      data: [
        { range: `${EXPENSES_TAB}!A1:K2`, values: [[NOTICE], [...HEADERS]] },
        { range: `${SUMMARY_TAB}!A1:H2`, values: SUMMARY_VALUES },
      ],
    });
    const protect = (range: object) => ({
      addProtectedRange: { protectedRange: { range, description: "Used by the sync. Do not edit.", warningOnly: false } },
    });
    await this.call("POST", `${SHEETS}/${id}:batchUpdate`, {
      requests: [
        // Dates as yyyy-mm-dd, amounts with two decimals.
        { repeatCell: { range: { sheetId: 0, startRowIndex: 2, startColumnIndex: 0, endColumnIndex: 1 }, cell: { userEnteredFormat: { numberFormat: { type: "DATE", pattern: "yyyy-mm-dd" } } }, fields: "userEnteredFormat.numberFormat" } },
        { repeatCell: { range: { sheetId: 0, startRowIndex: 2, startColumnIndex: 1, endColumnIndex: 2 }, cell: { userEnteredFormat: { numberFormat: { type: "NUMBER", pattern: "0.00" } } }, fields: "userEnteredFormat.numberFormat" } },
        { repeatCell: { range: { sheetId: 0, startRowIndex: 1, endRowIndex: 2 }, cell: { userEnteredFormat: { textFormat: { bold: true } } }, fields: "userEnteredFormat.textFormat.bold" } },
        { repeatCell: { range: { sheetId: 0, startRowIndex: 0, endRowIndex: 1 }, cell: { userEnteredFormat: { textFormat: { italic: true } } }, fields: "userEnteredFormat.textFormat.italic" } },
        { updateDimensionProperties: { range: { sheetId: 0, dimension: "COLUMNS", startIndex: 10, endIndex: 11 }, properties: { hiddenByUser: true }, fields: "hiddenByUser" } },
        protect({ sheetId: 0, startColumnIndex: 10, endColumnIndex: 11 }),
        protect({ sheetId: 0, startRowIndex: 0, endRowIndex: 2 }),
      ],
    });
    return { id, url: created.spreadsheetUrl as string };
  }

  async idRows(spreadsheetId: string) {
    const range = encodeURIComponent(`${EXPENSES_TAB}!${ID_COLUMN}${FIRST_DATA_ROW}:${ID_COLUMN}`);
    const data = await this.call("GET", `${SHEETS}/${spreadsheetId}/values/${range}?majorDimension=ROWS`);
    const map = new Map<string, number>();
    const rows: string[][] = data.values ?? [];
    rows.forEach((r, i) => {
      if (r[0]) map.set(r[0], FIRST_DATA_ROW + i);
    });
    return map;
  }

  async updateRows(spreadsheetId: string, rows: { row: number; values: Cell[] }[]) {
    if (rows.length === 0) return;
    await this.call("POST", `${SHEETS}/${spreadsheetId}/values:batchUpdate`, {
      valueInputOption: "RAW",
      data: rows.map((r) => ({ range: `${EXPENSES_TAB}!A${r.row}:K${r.row}`, values: [r.values] })),
    });
  }

  async appendRows(spreadsheetId: string, values: Cell[][]) {
    if (values.length === 0) return;
    const range = encodeURIComponent(`${EXPENSES_TAB}!A${FIRST_DATA_ROW}`);
    await this.call(
      "POST",
      `${SHEETS}/${spreadsheetId}/values/${range}:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS`,
      { values },
    );
  }

  async deleteRows(spreadsheetId: string, rows: number[]) {
    if (rows.length === 0) return;
    const bottomFirst = [...rows].sort((a, b) => b - a);
    await this.call("POST", `${SHEETS}/${spreadsheetId}:batchUpdate`, {
      requests: bottomFirst.map((row) => ({
        deleteDimension: { range: { sheetId: 0, dimension: "ROWS", startIndex: row - 1, endIndex: row } },
      })),
    });
  }
}
