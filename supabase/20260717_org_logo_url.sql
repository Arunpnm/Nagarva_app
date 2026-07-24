-- 20260717_org_logo_url.sql
-- Per-tenant sidebar branding: organizations.logo_url
--
-- The generated Dart class (organizations.dart) already exposes logoUrl, but
-- the column was flagged as "NOT in the owner-confirmed live schema". This
-- migration makes it real. Safe to re-run (IF NOT EXISTS).
--
-- Convention: follow the repo rule — commit this file, then apply it in the
-- Supabase SQL editor (Nagarva project hqqcapifefsaqvotqvlt).

alter table public.organizations
  add column if not exists logo_url text;

comment on column public.organizations.logo_url is
  'Public URL of the org''s logo (Supabase Storage bucket org-logos). '
  'Shown in the app sidebar; null falls back to the default truck icon.';

-- ---------------------------------------------------------------------------
-- One-time setup for the logo storage bucket (run once; harmless if re-run).
-- Public read so <img>/Image.network works without signed URLs; writes stay
-- restricted to authenticated users. Upload path convention: <org_id>/logo.png
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('org-logos', 'org-logos', true)
on conflict (id) do nothing;

drop policy if exists "org-logos public read" on storage.objects;
create policy "org-logos public read"
  on storage.objects for select
  using (bucket_id = 'org-logos');

drop policy if exists "org-logos authenticated write" on storage.objects;
create policy "org-logos authenticated write"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'org-logos');

drop policy if exists "org-logos authenticated update" on storage.objects;
create policy "org-logos authenticated update"
  on storage.objects for update to authenticated
  using (bucket_id = 'org-logos');

-- ---------------------------------------------------------------------------
-- APC (tenant #1): after uploading the APC logo to
--   org-logos/11111111-1111-4111-8111-111111111111/logo.png
-- via Dashboard → Storage, set the URL (copy the file's public URL from the
-- dashboard and paste it below — format shown for reference):
-- ---------------------------------------------------------------------------
-- update public.organizations
-- set logo_url = 'https://hqqcapifefsaqvotqvlt.supabase.co/storage/v1/object/public/org-logos/11111111-1111-4111-8111-111111111111/logo.png'
-- where id = '11111111-1111-4111-8111-111111111111';
