-- Prepares a plain Postgres 17 so the public-schema dump of the Supabase
-- database can be restored into it for the nightly restore check
-- (.github/workflows/db-backup.yml). Not used for a real restore -- a real
-- restore goes into a Supabase project, which has all of this already
-- (docs/BACKUP_RESTORE.md).
--
-- Checked 11 Nov 2026: the public schema depends on exactly these outside
-- things -- extensions pgcrypto, uuid-ossp, btree_gist (schema
-- "extensions"), the function auth.uid(), Supabase's roles in policies and
-- grants, and the supabase_realtime publication.

do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role', 'authenticator',
                           'supabase_admin', 'supabase_auth_admin',
                           'supabase_storage_admin', 'dashboard_user',
                           'supabase_realtime_admin', 'pgbouncer'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin', r);
    end if;
  end loop;
end $$;

create schema if not exists extensions;
create extension if not exists pgcrypto   with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists btree_gist with schema extensions;

-- Stand-ins for Supabase's auth helpers: same names and types, no logins.
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text);
create or replace function auth.uid()  returns uuid  language sql stable as 'select null::uuid';
create or replace function auth.role() returns text  language sql stable as 'select null::text';
create or replace function auth.jwt()  returns jsonb language sql stable as 'select null::jsonb';
create or replace function auth.email() returns text language sql stable as 'select null::text';

create schema if not exists vault;
create schema if not exists storage;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

alter database postgres set search_path = "$user", public, extensions;
