-- 20261110_ai_survey_usage.sql  (10 Nov 2026, AI photo survey)
--
-- One row per AI photo analysis. The survey-ai Edge Function writes a row
-- BEFORE it calls the AI provider and counts its caps from this table
-- (per survey link, per company per day). Without this table the function
-- refuses every request — an unrecorded call would be an uncapped cost.
--
-- No photo is stored here. link_hash is a SHA-256 of the survey token, so
-- the table never holds a working customer link.
--
-- Who can do what:
--   * the Edge Function (service role) inserts and updates;
--   * a company's own members can READ their rows (for a usage screen);
--   * nobody else can see or write anything.
--
-- KNOWN, NOT FIXED HERE: delete_org() refuses to run while any table with
-- an org_id column is missing from its v_order / v_keep lists. Measured
-- 10 Nov 2026: 14 tables are already unlisted (cft_catalogue,
-- crew_checkins, job_checkin_keys, staff_incentives, staff_leaves,
-- wa_accounts, ...), so it is refusing today; this table becomes the 15th.
-- Rows here cascade with the organization, so when delete_org is brought
-- up to date this table belongs in v_order (any position).
--
-- Run the WHOLE file. One transaction; a failed check rolls it all back.

begin;

-- ---------- preflight -------------------------------------------------
do $$
begin
  if to_regclass('public.ai_survey_usage') is not null then
    raise exception 'public.ai_survey_usage already exists -- this file has been run. Nothing to do.';
  end if;
  if to_regclass('public.organizations') is null then
    raise exception 'public.organizations is missing -- wrong database?';
  end if;
  if to_regprocedure('public.current_org_ids()') is null then
    raise exception 'public.current_org_ids() is missing -- the RLS helpers must exist first.';
  end if;
end $$;

-- ---------- table -----------------------------------------------------
create table public.ai_survey_usage (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations(id) on delete cascade,
  user_id     uuid,            -- staff session, null for a customer link
  link_hash   text,            -- sha256 of the survey token, null for staff
  room        text,
  photos      integer not null check (photos between 1 and 4),
  provider    text not null,
  model       text not null,
  ok          boolean,         -- null while the provider is answering
  items_found integer,
  error       text,            -- 'timeout' | 'provider' | 'unreadable'
  created_at  timestamptz not null default now()
);

create index ai_survey_usage_org_day on public.ai_survey_usage (org_id, created_at desc);
create index ai_survey_usage_link    on public.ai_survey_usage (link_hash) where link_hash is not null;

alter table public.ai_survey_usage enable row level security;

revoke all on public.ai_survey_usage from public, anon, authenticated;
grant select on public.ai_survey_usage to authenticated;

create policy org_read on public.ai_survey_usage
  for select to authenticated
  using (org_id in (select public.current_org_ids()));

-- ---------- postflight ------------------------------------------------
do $$
begin
  if not (select relrowsecurity from pg_class
           where oid = 'public.ai_survey_usage'::regclass) then
    raise exception 'RLS is not enabled on ai_survey_usage';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'ai_survey_usage') <> 1 then
    raise exception 'ai_survey_usage should have exactly one policy (org_read)';
  end if;
  if has_table_privilege('anon', 'public.ai_survey_usage', 'select')
     or has_table_privilege('anon', 'public.ai_survey_usage', 'insert')
     or has_table_privilege('authenticated', 'public.ai_survey_usage', 'insert')
     or has_table_privilege('authenticated', 'public.ai_survey_usage', 'update')
     or has_table_privilege('authenticated', 'public.ai_survey_usage', 'delete') then
    raise exception 'ai_survey_usage is writable or readable by a role that must not have it';
  end if;
  if not has_table_privilege('service_role', 'public.ai_survey_usage', 'insert') then
    raise exception 'service_role cannot insert into ai_survey_usage -- the function would refuse every call';
  end if;
end $$;

commit;
