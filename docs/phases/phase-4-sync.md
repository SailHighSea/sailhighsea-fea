# Phase 4: Sync (weeks 6 to 7)

**Status:** Done and merged. Built (2026-10-26) against a fake server. Still to do: run it with two real devices against Supabase.

## Do
1. Sync engine in `lib/core/sync`: push dirty rows, pull changes since last cursor, Supabase Realtime for live updates, exponential backoff, offline queue.
2. Last-write-wins by `updated_at` (server time). Soft deletes propagate. Handle clock skew by trusting server timestamps.
3. First-time household join pulls everything; show progress.
4. Sync status indicator (synced, syncing, offline) in the shell on every size.
5. Tests with a fake backend for conflicts, offline edits, deletes, and role changes mid-session (a demoted member's queued writes are rejected and surfaced clearly).
6. Build to `test/` and report.

7. Prepare for Phase 4b: keep a stable server-side `updated_at` and soft-delete flag on expenses so a database trigger can feed the Google Sheets queue.

## Done when
Edits on two devices appear on each other within seconds online, and offline edits sync after reconnect with no data loss.
