-- 20261021_audit_log_append_only.sql
--
-- SECURITY. audit_log's only policy was `org_isolation FOR ALL`, so any
-- member of an org — any staff PIN session included — could UPDATE or
-- DELETE that org's audit rows over PostgREST. An audit trail the people
-- it records can rewrite is not an audit trail.
--
-- After this: members may READ their org's rows and INSERT new ones
-- (AuditLogService and SoftDeleteService insert from the app). Nobody
-- may UPDATE or DELETE through the API — there is simply no policy for
-- either, so RLS refuses them.
--
-- Unaffected, checked before writing this (21 Oct 2026):
--   * audit_row()  — the trigger function; SECURITY DEFINER, runs as the
--     table owner, so RLS does not apply to its inserts.
--   * delete_org() — SECURITY DEFINER, same reason.
--   * admin-delete-org Edge Function — service role, bypasses RLS.
--   * No code in lib/ updates or deletes audit_log; both call sites are
--     inserts (audit_log_service.dart, soft_delete.dart).
--
-- Handed over unrun. Its own commit, per the security-migration rule.

begin;

do $$
begin
  if to_regclass('public.audit_log') is null then
    raise exception 'public.audit_log does not exist — wrong database?';
  end if;
  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'audit_log'
                    and policyname = 'org_isolation' and cmd = 'ALL') then
    raise exception 'audit_log has no FOR ALL org_isolation policy — already applied, or the table changed; read pg_policies before re-running.';
  end if;
  if to_regprocedure('public.current_org_ids()') is null
     or to_regprocedure('public.is_platform_admin()') is null then
    raise exception 'current_org_ids() or is_platform_admin() is missing.';
  end if;
end $$;

drop policy org_isolation on public.audit_log;

-- Same expression the old policy used, split by command.
create policy audit_log_select on public.audit_log
  for select
  using ((org_id in (select current_org_ids())) or is_platform_admin());

create policy audit_log_insert on public.audit_log
  for insert
  with check ((org_id in (select current_org_ids())) or is_platform_admin());

-- Postflight: the catalogue, then behaviour as a real member.
do $$
declare
  v_uid uuid;
  v_org uuid;
  v_seen int;
  v_upd int;
  v_del int;
begin
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'audit_log') <> 2 then
    raise exception 'audit_log should have exactly 2 policies';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'audit_log'
                and cmd in ('ALL', 'UPDATE', 'DELETE')) then
    raise exception 'audit_log still has an ALL/UPDATE/DELETE policy';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.audit_log'::regclass) then
    raise exception 'RLS is off on audit_log';
  end if;

  -- A probe that finds nobody tests nothing, so refuse instead.
  select m.user_id, m.org_id into v_uid, v_org
    from org_members m
   where exists (select 1 from audit_log a where a.org_id = m.org_id)
   limit 1;
  if v_uid is null then
    raise exception 'No org member with audit rows to probe with — cannot verify; not applying.';
  end if;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text,
                     true);
  set local role authenticated;

  select count(*) into v_seen from audit_log where org_id = v_org;
  update audit_log set reason = reason where org_id = v_org;
  get diagnostics v_upd = row_count;
  delete from audit_log where org_id = v_org;
  get diagnostics v_del = row_count;

  reset role;

  -- Must READ (else the policy set refuses everyone, which breaks the
  -- Activity log) and must NOT update or delete. Before this migration
  -- the same update and delete affected every row, so these checks tell
  -- the two states apart.
  if v_seen = 0 then
    raise exception 'member can no longer read audit_log';
  end if;
  if v_upd <> 0 or v_del <> 0 then
    raise exception 'member could still change audit_log (updated %, deleted %)', v_upd, v_del;
  end if;
end $$;

commit;
