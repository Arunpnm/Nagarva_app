-- BUG-013 (full test, 1 Nov 2026): the authorised signatory's signature PNG
-- was stored in the PUBLIC `org-logos` bucket — anyone with the URL could
-- download a company's signature.
--
-- New private bucket `org-private`, one folder per company
-- (`<org_id>/signature.png`), readable/writable only by members of that
-- company (current_org_ids()) or a platform admin — the same rule the
-- private `job-photos` bucket already uses.
--
-- App side (3 Nov 2026, lib/backend/private_files.dart): a newly drawn
-- signature is uploaded here and `settings.signature_url` stores the
-- reference `org-private:<org_id>/signature.png`; PDFs download it with
-- the user's own rights. Old values (public URLs) keep working until the
-- owner draws the signature again, at which point the old public copy is
-- deleted. The 5 existing public signature files are NOT moved by this
-- script (storage files can't be copied from SQL): ask each owner to
-- re-draw once, or delete them from org-logos after they have.
--
-- NOT APPLIED — Arun runs this.

begin;

insert into storage.buckets (id, name, public)
values ('org-private', 'org-private', false)
on conflict (id) do update set public = false;

drop policy if exists org_private_select on storage.objects;
drop policy if exists org_private_insert on storage.objects;
drop policy if exists org_private_update on storage.objects;
drop policy if exists org_private_delete on storage.objects;

create policy org_private_select on storage.objects
  for select to authenticated
  using (bucket_id = 'org-private'
         and ((storage.foldername(name))[1] in (select current_org_ids()::text)
              or public.is_platform_admin()));

create policy org_private_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'org-private'
              and (storage.foldername(name))[1] in (select current_org_ids()::text));

create policy org_private_update on storage.objects
  for update to authenticated
  using (bucket_id = 'org-private'
         and (storage.foldername(name))[1] in (select current_org_ids()::text))
  with check (bucket_id = 'org-private'
              and (storage.foldername(name))[1] in (select current_org_ids()::text));

create policy org_private_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'org-private'
         and (storage.foldername(name))[1] in (select current_org_ids()::text));

commit;

-- Check: select id, public from storage.buckets where id = 'org-private';
--   → org-private | false
