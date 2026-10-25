-- Phase 6: receipt photos. A private bucket; objects live at <household_id>/<expense_id>.<ext>.
-- Writes need the right to edit expenses in that household. Reads follow the expense: you can open
-- a receipt only when you can see the expense that points at it (so an own-only member's receipts
-- stay private), and managers can always see them through the same rule.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy receipts_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'receipts'
    and public.can_edit_expenses(((storage.foldername(name))[1])::uuid)
  );

-- The expenses select policy already applies the member-visibility rules to this subquery.
create policy receipts_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'receipts'
    and exists (
      select 1 from public.expenses e
      where e.receipt_path = storage.objects.name and e.deleted_at is null
    )
  );

-- Owners of the upload can remove it (for example when the expense is discarded); managers can too.
create policy receipts_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'receipts'
    and (
      owner = (select auth.uid())
      or public.is_manager(((storage.foldername(name))[1])::uuid)
    )
  );
