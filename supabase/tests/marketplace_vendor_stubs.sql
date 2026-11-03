-- Local test kit for 20261030_marketplace_vendor.sql. NOT for Supabase.
--
-- Runs against a throwaway local Postgres 16 with stand-ins for what
-- Supabase provides (auth.uid(), organizations, org_members,
-- platform_admins and the four helper functions), matching the live
-- signatures as read on 30 Oct 2026.
--
--   createdb mkt_test
--   psql -d mkt_test -f supabase/tests/marketplace_vendor_stubs.sql
--   psql -d mkt_test -f supabase/20261030_marketplace_vendor.sql
--   psql -d mkt_test -f supabase/tests/marketplace_vendor_behaviour.sql
--
-- Expected: the migration prints nothing and commits; the behaviour
-- script's only ERRORs are the eight deliberate refusals it labels.
-- (Drop the `create role` line if the roles already exist locally.)
-- Minimal stand-ins for what Supabase provides, matching live signatures.
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
grant usage on schema public to anon, authenticated;
create table public.organizations (id uuid primary key, name text);
create table public.org_members (org_id uuid, user_id uuid, role text);
create table public.platform_admins (user_id uuid primary key, note text, created_at timestamptz default now());
create function public.current_org_ids() returns setof uuid language sql stable security definer set search_path=public
  as $$ select org_id from org_members where user_id = auth.uid() $$;
create function public.is_org_owner(p_org_id uuid) returns boolean language sql stable security definer set search_path=public
  as $$ select exists(select 1 from org_members where org_id=p_org_id and user_id=auth.uid() and role='owner') $$;
create function public.is_org_manager(p_org_id uuid) returns boolean language sql stable security definer set search_path=public
  as $$ select exists(select 1 from org_members where org_id=p_org_id and user_id=auth.uid() and role in ('owner','admin','manager')) $$;
create function public.is_platform_admin() returns boolean language sql stable security definer set search_path=public
  as $$ select exists(select 1 from platform_admins where user_id=auth.uid()) $$;
