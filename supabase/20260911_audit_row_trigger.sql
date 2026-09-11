-- =====================================================================
-- 20260911_audit_row_trigger.sql          PART 3, step 1 of 2
--
-- A generic row-level audit trigger, installed once and attached to TWO
-- tables. NOT six. The widening migration comes after this one is proven
-- against real writes.
--
-- WHY ONLY TWO
--   quotations    -- the proving ground. Real writes, low volume, and
--                    Part 2 is about to put a status transition through
--                    it, which is the cheapest possible end-to-end test.
--   app_settings  -- included from the start per instruction, and it is
--                    free: the app has ZERO writers for this table today
--                    (every AppSettingsTable reference in lib/ is a read),
--                    so attaching a trigger adds no live write path to
--                    risk. Part 4's policy attribution comes from here,
--                    and there is no reason to touch the table twice.
--
-- DEFERRED to the widening migration, deliberately:
--   orders, payment_entries, addons, rate_cards, rate_card_rules, staff
-- Those are the high-traffic ones. This is the first thing in the project
-- that fires on every write to a table; it gets proven before it reaches
-- the tables that carry the business.
--
-- WHAT THIS IS FOR, AND WHAT IT IS NOT
-- The audit log is the SAFETY NET, not the story. A manager reads the
-- quote version history (Part 1, quote_versions); audit_log is what gets
-- opened when someone says they never changed it. Nothing in the UI reads
-- audit_log today and nothing should start.
--
-- COEXISTENCE WITH AuditLogService -- read this before "simplifying"
-- After this lands, a covered write produces TWO audit rows: the app's
-- semantic row (action 'payment_recorded', carrying `reason`) and this
-- trigger's mechanical row. That IS the two-sources shape, so it is
-- resolved by design rather than left to be discovered:
--   * trigger actions are MECHANICAL -- row_insert / row_update /
--     row_delete. The app never writes those three strings.
--   * app actions stay SEMANTIC and keep `reason`, which a trigger
--     cannot infer.
--   * a reader must NEVER sum or merge the two. Free to guarantee today,
--     because nothing reads the table.
--
-- NOT RUN. File only, per instruction.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
-- ---------------------------------------------------------------------
do $$
declare
  v_missing text[] := array[]::text[];
  v_col     text;
begin
  if to_regclass('public.audit_log') is null then
    raise exception 'public.audit_log is missing; nothing to write to.';
  end if;
  if to_regclass('public.quotations') is null then
    raise exception 'public.quotations is missing.';
  end if;
  if to_regclass('public.app_settings') is null then
    raise exception 'public.app_settings is missing.';
  end if;

  -- Every column this trigger writes must exist, with audit_log's
  -- migration-005 shape. Assert the columns, not the migration name.
  foreach v_col in array array[
    'org_id','entity_type','entity_id','action','actor','actor_name',
    'actor_role','old_value','new_value','changed_fields','created_at'
  ] loop
    if not exists (
      select 1 from information_schema.columns
       where table_schema='public' and table_name='audit_log'
         and column_name = v_col
    ) then
      v_missing := v_missing || v_col;
    end if;
  end loop;
  if array_length(v_missing,1) is not null then
    raise exception 'audit_log is missing column(s): %', array_to_string(v_missing, ', ');
  end if;

  -- Both target tables must expose an `id`, because entity_id is NOT NULL
  -- and is read generically as to_jsonb(row)->>'id'. quotations.id is
  -- text and app_settings.id is uuid -- which is exactly why it is read
  -- through jsonb rather than typed per table.
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='quotations'
                    and column_name='id') then
    raise exception 'quotations has no id column.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='app_settings'
                    and column_name='id') then
    raise exception 'app_settings has no id column.';
  end if;

  if not exists (select 1 from public.organizations limit 1) then
    raise exception
      'no organizations exist; the behavioural postflight needs one to probe with.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- THE FUNCTION
--
-- SECURITY DEFINER, and that is load-bearing twice over:
--   1. audit_log is RLS'd (org_isolation FOR ALL). Without DEFINER, a
--      staff session's own audit row could be refused by the policy and
--      -- since this trigger deliberately does NOT swallow errors -- that
--      refusal would block their legitimate write.
--   2. A caller must not be able to suppress their own audit row. The
--      whole point of a trigger over an app-level call is that it cannot
--      be forgotten or opted out of.
-- search_path is pinned, as every SECURITY DEFINER function here must be.
--
-- IT DOES NOT SWALLOW ERRORS, unlike AuditLogService. That is deliberate:
-- a log with silent holes is worse than no log, and it would have holes
-- exactly when something is wrong. This is only safe BECAUSE of DEFINER
-- above -- with RLS bypassed, the realistic failure modes are gone, and
-- the one that remains (a row with no id) is caught with a real sentence.
-- ---------------------------------------------------------------------
create or replace function public.audit_row()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_old       jsonb;
  v_new       jsonb;
  v_entity_id text;
  v_org       uuid;
  v_action    text;
  v_changed   text[];
  v_actor     uuid;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new);
    v_action := 'row_insert';
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    v_action := 'row_update';
    -- A no-op UPDATE writes nothing. Postgres fires the trigger whether
    -- or not any value actually changed (a save button pressed twice, a
    -- framework re-writing an unchanged row); logging those buries the
    -- real changes and inflates a table that already has no retention
    -- policy. See the retention open item in CLAUDE.md.
    if v_old = v_new then
      return null;
    end if;
  else
    v_old := to_jsonb(old);
    v_action := 'row_delete';
  end if;

  v_entity_id := coalesce(v_new ->> 'id', v_old ->> 'id');
  if v_entity_id is null then
    raise exception
      'audit_row: %.% has no id value; audit_log.entity_id is NOT NULL.',
      tg_table_schema, tg_table_name;
  end if;

  begin
    v_org := coalesce(v_new ->> 'org_id', v_old ->> 'org_id')::uuid;
  exception when others then
    v_org := null;   -- a table with no org_id, or an unparseable one
  end;

  -- Field-level diff, computed here rather than accepted from a caller.
  -- A client-supplied diff is a second account of the same event that can
  -- disagree with the values it describes.
  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into v_changed
      from (
        select coalesce(n.key, o.key) as k
          from jsonb_each(v_new) n
          full outer join jsonb_each(v_old) o on o.key = n.key
         where n.value is distinct from o.value
      ) d;
  end if;

  -- ACTOR IDENTITY -- and the honest limit of it.
  -- auth.uid() is all a trigger can trust. actor_name and actor_role are
  -- left NULL ON PURPOSE, not forgotten:
  --   * all 5 staff rows carry auth_user_id = NULL (counted 11 Sept
  --     2026), so auth.uid() cannot be resolved to a person server-side;
  --   * taking a name from a client-supplied header or GUC would be
  --     forgeable, and a forgeable actor is worthless in precisely the
  --     dispute this table exists for.
  -- A guessed name is worse than a blank. Populating staff.auth_user_id
  -- at PIN login is the prerequisite that lights this up retroactively
  -- for every row already written -- it is its own piece of work.
  begin
    v_actor := auth.uid();
  exception when others then
    v_actor := null;   -- no JWT (e.g. running as postgres in the editor)
  end;

  insert into public.audit_log (
    org_id, entity_type, entity_id, action, actor,
    actor_name, actor_role, old_value, new_value, changed_fields
  ) values (
    v_org, tg_table_name, v_entity_id, v_action, v_actor,
    null, null, v_old, v_new, v_changed
  );

  return null;   -- AFTER trigger; return value is ignored
end;
$function$;

comment on function public.audit_row() is
  'Generic row-level audit trigger. Writes mechanical row_insert/row_update/'
  'row_delete rows to audit_log. actor_name/actor_role are deliberately NULL '
  'until staff.auth_user_id is populated at PIN login -- a guessed or '
  'client-supplied actor is worse than a blank. Does not swallow errors.';

-- ---------------------------------------------------------------------
-- ATTACH -- two tables only.
-- drop-then-create so re-running this file is safe.
-- ---------------------------------------------------------------------
drop trigger if exists trg_audit_quotations on public.quotations;
create trigger trg_audit_quotations
  after insert or update or delete on public.quotations
  for each row execute function public.audit_row();

drop trigger if exists trg_audit_app_settings on public.app_settings;
create trigger trg_audit_app_settings
  after insert or update or delete on public.app_settings
  for each row execute function public.audit_row();

-- ---------------------------------------------------------------------
-- POSTFLIGHT
--
-- Structural checks, then a BEHAVIOURAL probe that actually exercises the
-- trigger and then unwinds itself. "The construct, not the flag" -- a
-- catalogue check proves a trigger is attached, not that it writes a
-- correct row. The probe inserts and updates one throwaway app_settings
-- row, asserts the audit rows are right, then raises a sentinel so the
-- inner block's work (probe row AND its audit rows) is rolled back.
-- Nothing survives the block.
-- ---------------------------------------------------------------------
do $$
declare
  v_prosecdef boolean;
  v_cfg       text[];
  v_enabled   text;
  v_org       uuid;
  v_id        uuid;
  v_ins_n     int;
  v_upd_act   text;
  v_upd_old   jsonb;
  v_upd_new   jsonb;
  v_upd_flds  text[];
  v_ok        boolean := false;
begin
  -- 1. The function is SECURITY DEFINER with a pinned search_path.
  select p.prosecdef, p.proconfig into v_prosecdef, v_cfg
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'audit_row';
  if v_prosecdef is null then
    raise exception 'audit_row() was not created.';
  end if;
  if not v_prosecdef then
    raise exception
      'audit_row() is not SECURITY DEFINER; a staff audit write would be '
      'refused by audit_log RLS and would block their real write.';
  end if;
  if v_cfg is null or not exists (
       select 1 from unnest(v_cfg) c where c like 'search_path=%') then
    raise exception 'audit_row() has no pinned search_path.';
  end if;

  -- 2. Both triggers exist and are ENABLED. tgenabled 'O' = origin.
  foreach v_enabled in array array['trg_audit_quotations','trg_audit_app_settings'] loop
    if not exists (
      select 1 from pg_trigger t
       where t.tgname = v_enabled and not t.tgisinternal
         and t.tgenabled = 'O'
    ) then
      raise exception 'trigger % is missing or not enabled.', v_enabled;
    end if;
  end loop;

  -- 3. BEHAVIOURAL PROBE, self-unwinding.
  select id into v_org from public.organizations order by created_at limit 1;

  begin
    insert into public.app_settings (org_id, category, key, value)
    values (v_org, '__audit_probe__', 'probe', '1'::jsonb)
    returning id into v_id;

    select count(*) into v_ins_n
      from public.audit_log
     where entity_type = 'app_settings' and entity_id = v_id::text
       and action = 'row_insert';
    if v_ins_n <> 1 then
      raise exception 'probe: expected 1 row_insert audit row, found %.', v_ins_n;
    end if;

    update public.app_settings set value = '2'::jsonb where id = v_id;

    select action, old_value, new_value, changed_fields
      into v_upd_act, v_upd_old, v_upd_new, v_upd_flds
      from public.audit_log
     where entity_type = 'app_settings' and entity_id = v_id::text
       and action = 'row_update'
     order by created_at desc limit 1;

    if v_upd_act is null then
      raise exception 'probe: no row_update audit row was written.';
    end if;
    if v_upd_old is null or v_upd_new is null then
      raise exception 'probe: row_update wrote a null old_value or new_value.';
    end if;
    if v_upd_old ->> 'value' = v_upd_new ->> 'value' then
      raise exception 'probe: old_value and new_value are identical.';
    end if;
    if v_upd_flds is null or not ('value' = any(v_upd_flds)) then
      raise exception
        'probe: changed_fields did not name "value" (got %).',
        coalesce(v_upd_flds::text, '<null>');
    end if;

    -- A second UPDATE that changes nothing must write NOTHING.
    update public.app_settings set value = '2'::jsonb where id = v_id;
    select count(*) into v_ins_n
      from public.audit_log
     where entity_type = 'app_settings' and entity_id = v_id::text
       and action = 'row_update';
    if v_ins_n <> 1 then
      raise exception
        'probe: a no-op UPDATE was logged; expected 1 row_update row, found %.',
        v_ins_n;
    end if;

    -- Everything above passed. Unwind the whole block -- the probe row
    -- and every audit row it generated go with it.
    raise exception 'AUDIT_PROBE_OK';
  exception
    when others then
      if sqlerrm <> 'AUDIT_PROBE_OK' then
        raise;                     -- a real failure: propagate and roll back
      end if;
      v_ok := true;
  end;

  if not v_ok then
    raise exception 'probe did not run to completion.';
  end if;

  -- 4. Nothing survived the probe.
  if exists (select 1 from public.app_settings where category = '__audit_probe__') then
    raise exception 'probe row survived; it must not.';
  end if;

  raise notice
    'audit_row() installed; trg_audit_quotations + trg_audit_app_settings '
    'attached and behaviourally verified. actor_name/actor_role are NULL '
    'by design until staff.auth_user_id is populated.';
end $$;

commit;

-- =====================================================================
-- AFTER THIS RUNS -- the verification that only real use can give
-- ---------------------------------------------------------------------
-- The probe proves the mechanism. It does not prove it against a real
-- app write through PostgREST as a real session, which is where actor
-- and org_id come from. Part 2's status transition is the intended first
-- real exercise. Then check:
--
--   select entity_type, action, entity_id, actor, changed_fields, created_at
--     from audit_log
--    where action in ('row_insert','row_update','row_delete')
--    order by created_at desc limit 20;
--
-- Expect: actor = the session's auth uid (NOT null), org_id populated,
-- changed_fields naming only the columns that really moved. actor_name
-- and actor_role WILL be null -- that is the documented limit, not a bug.
--
-- WIDENING (next migration, only after the above reads correctly):
--   orders, payment_entries, addons, rate_cards, rate_card_rules, staff
-- orders and payment_entries are the volume. Before attaching those,
-- re-read the retention open item in CLAUDE.md -- the write rate they
-- produce is the measurement that decides the retention policy, and it
-- cannot be measured until they are attached.
--
-- ROLLBACK
--   drop trigger if exists trg_audit_quotations  on public.quotations;
--   drop trigger if exists trg_audit_app_settings on public.app_settings;
--   drop function if exists public.audit_row();
-- Audit rows already written are left alone -- deleting an audit trail
-- to undo a deployment is the one thing this table must never allow.
-- =====================================================================
