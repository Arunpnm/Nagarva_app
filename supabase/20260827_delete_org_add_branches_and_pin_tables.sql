-- =====================================================================
-- 20260827_delete_org_add_branches_and_pin_tables.sql
--
-- delete_org()'s orphan guard refused a dry run:
--
--   P0001: delete_org() is out of date: 3 org-scoped table(s) it does
--   not know about (branches, pin_ip_attempts, pin_lockout_events).
--
-- THE GUARD WORKING AS DESIGNED. Without it the wipe would have left
-- rows in three tables, in a database where only 15 of 121 org-scoped
-- tables have an FK to organizations at all.
--
-- `branches` was created by 20260825_branches_table.sql and extended by
-- 20260827_branches_management.sql — i.e. THIS GAP WAS CREATED THE SAME
-- DAY by our own branch work. See the standing obligation recorded in
-- NAGARVA_MODULE_STATUS.md: delete_org's list needs updating whenever an
-- org-scoped table is added.
--
-- Written against the CURRENT live body (read with pg_get_functiondef
-- 27 Aug 2026), which already has the APC guard removed by
-- 20260827_delete_org_drop_apc_guard.sql. Signature unchanged, so
-- CREATE OR REPLACE is correct and no ACL is lost.
--
-- =====================================================================
-- PLACEMENT DECISIONS, WITH THE EVIDENCE
-- =====================================================================
--
-- branches -> v_order, LAST. Not a guess:
--   * 22 tables hold `(org_id, branch) REFERENCES branches(org_id, name)`
--     with ON DELETE RESTRICT — attendance, bank_accounts, customers,
--     grn, journal_entries, journal_lines, leads, lr_register, lr_series,
--     marketing_spend, materials, number_series, orders, payroll_runs,
--     purchase_orders, rate_cards, reviews, staff, stock_movements,
--     tasks, trips, warehouses. Deleting a branch while ANY of them
--     still holds a row is refused by Postgres, so branches must come
--     after all 22. All 22 are already in v_order (they have org_id by
--     construction — the FK is composite on it), so placing branches at
--     the very END is the position that cannot be wrong.
--   * There is NO reverse dependency: branches.manager_staff_id
--     REFERENCES staff(id) ON DELETE SET NULL, so deleting staff first
--     nulls that column instead of blocking. No FK cycle, so no entry is
--     needed in the cycle-breaking update block.
--
-- pin_ip_attempts -> v_order. Two reasons, the first decisive:
--   * Its FK is `org_id REFERENCES organizations(id) ON DELETE CASCADE`.
--     It CANNOT survive the org: the final `delete from organizations`
--     destroys its rows whichever list it appears in. Putting it in
--     v_keep would be a lie the code tells about itself.
--   * Semantically it is live rate-limit STATE (failed_attempts,
--     lock_level, locked_until), not a historical record. Operational
--     state for an org that no longer exists is meaningless.
--
-- pin_lockout_events -> v_order, but this one is genuinely arguable and
-- the reasoning should not be lost:
--   * It IS a security audit trail — scope, pool, staff_id, client_ip,
--     lock_level, failed_attempts, created_at. A record that an account
--     was locked out has real value beyond the tenant's lifetime, and
--     the same argument that keeps audit_log applies to it.
--   * BUT its FK is also ON DELETE CASCADE, so it cannot survive TODAY.
--     audit_log survives only because its FK is ON DELETE SET NULL with
--     a nullable org_id. Making pin_lockout_events survivable is
--     therefore a SCHEMA change (nullable org_id + SET NULL + denormalise
--     enough context to stay meaningful), not a list edit.
--   * Listing it in v_order is the honest option: the rows die either
--     way, and being listed means they are counted and reported in the
--     result set instead of vanishing silently via cascade.
--   * FLAGGED, NOT DECIDED: if these lockout records should outlive an
--     org, that needs its own migration. Not smuggled in here.
-- =====================================================================

begin;

do $preflight$
declare v_def text;
begin
  if to_regprocedure('public.delete_org(uuid,uuid,boolean,boolean)') is null then
    raise exception 'PREFLIGHT: delete_org(uuid,uuid,boolean,boolean) not found.';
  end if;
  v_def := pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure);
  if position('Refusing to delete APC' in v_def) > 0 then
    raise exception 'PREFLIGHT: the APC guard is still present — run 20260827_delete_org_drop_apc_guard.sql first, or this migration will silently reinstate the removal out of order.';
  end if;
  -- All three tables must actually exist, or we would be adding names
  -- that make the orphan guard pass while deleting nothing.
  if to_regclass('public.branches') is null
     or to_regclass('public.pin_ip_attempts') is null
     or to_regclass('public.pin_lockout_events') is null then
    raise exception 'PREFLIGHT: one of branches / pin_ip_attempts / pin_lockout_events does not exist.';
  end if;
end
$preflight$;

create or replace function public.delete_org(p_org_id uuid, p_actor uuid, p_dry_run boolean DEFAULT true, p_force boolean DEFAULT false)
returns TABLE(table_name text, rows_affected bigint)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_org         record;
  v_actor_name  text;
  v_unknown     text[];
  v_tbl         text;
  v_n           bigint;
  v_total       bigint := 0;
  v_audit_id    uuid;

  v_order constant text[] := array[
    'account_transfers','activities','tasks','addons','app_settings',
    'attendance','backup_registry','bank_statement_lines','bank_statements',
    'claim_items','claims','complaints','credit_notes','customer_addresses',
    'customer_contacts','discount_policies','document_signatures','documents',
    'eway_consolidated','eway_vehicle_updates','expenses','export_jobs',
    'follow_up_logs','reminders','gst_returns','job_expense_float_entries',
    'job_expense_floats','job_photos','order_status_history','journal_lines',
    'journal_entries','chart_of_accounts','account_groups','ledger_entries',
    'lr_copies','lr_series','marketing_spend','notification_log',
    'notification_tokens','notification_prefs','notifications','number_series',
    'onboarding_progress','order_item_counts','order_staff','order_tracking',
    'order_vendors','org_members',
    -- PIN throttling: org-scoped state and lockout history. Both have
    -- ON DELETE CASCADE on org_id, so they cannot outlive the org —
    -- listed here so their removal is counted rather than silent.
    'org_pin_attempts','pin_ip_attempts','pin_lockout_events',
    'payment_entries',
    'receipts','pod_records','pricing_config','purchase_order_items',
    'quote_approvals','quote_outcomes','quote_versions','rate_card_charges',
    'rate_card_floor_charges','rate_card_multipliers','rate_card_rules',
    'referrals','retention_policies','reviews','salary_payments',
    'saved_reports','settings','sla_events','staff_advance_entries',
    'payslips','payroll_runs','staff_advances','staff_invites',
    'stock_movements','grn','purchase_orders','materials',
    'storage_billing_cycles','storage_items','storage_jobs','warehouses',
    'surveys','tds_entries','vendor_payments','bank_accounts','vendor_bills',
    'transactions','trip_expenses','trip_orders','vehicle_service_logs',
    'vehicle_trips','customer_surveys','eway_bills','insurance_policies',
    'lr_register','orders','quotations','staff','trips','vehicles','vendors',
    'contracts','wa_messages','wa_contacts','leads','customers','rate_cards',
    'lead_sources','wage_rate_defaults',
    -- MUST BE LAST. 22 tables reference branches(org_id, name) with
    -- ON DELETE RESTRICT; every one of them is above this line. See the
    -- header for why this position is derived, not guessed.
    'branches'
  ];

  v_keep constant text[] := array[
    'audit_log','consent_records','data_requests','erasure_log',
    'breach_incidents','billing_events','platform_invoices',
    'org_subscriptions','org_usage'
  ];
begin
  if p_actor is null then
    raise exception 'p_actor is required — it is the verified platform '
                    'admin performing this deletion. Call through the '
                    'admin-delete-org Edge Function, which supplies it.'
      using errcode = 'P0001';
  end if;

  select coalesce(u.email, p_actor::text) into v_actor_name
    from auth.users u where u.id = p_actor;

  if not exists (select 1 from platform_admins pa where pa.user_id = p_actor) then
    raise exception 'Actor % is not a platform admin.', coalesce(v_actor_name, p_actor::text)
      using errcode = 'P0001';
  end if;

  -- APC guard removed 27 Aug 2026 by
  -- 20260827_delete_org_drop_apc_guard.sql. The p_force requirement
  -- below remains the brake.

  select * into v_org from organizations where id = p_org_id;
  if not found then
    raise exception 'No organization with id %', p_org_id using errcode = 'P0001';
  end if;

  if coalesce(v_org.plan_status, '') = 'active' and not p_force then
    raise exception 'Organization "%" is on an ACTIVE plan. Pass p_force => true '
                    'if you really mean to delete a paying tenant.', v_org.name
      using errcode = 'P0001';
  end if;

  select array_agg(t.table_name order by t.table_name)
    into v_unknown
  from information_schema.tables t
  join information_schema.columns c
    on c.table_schema = t.table_schema and c.table_name = t.table_name
  where t.table_schema = 'public'
    and t.table_type = 'BASE TABLE'
    and c.column_name = 'org_id'
    and t.table_name <> all(v_order)
    and t.table_name <> all(v_keep);

  if v_unknown is not null then
    raise exception
      'delete_org() is out of date: % org-scoped table(s) it does not know '
      'about (%). Add each to v_order (in dependency position) or to '
      'v_keep, then re-derive the ordering. Refusing to run rather than '
      'leave orphaned rows.',
      array_length(v_unknown, 1), array_to_string(v_unknown, ', ')
      using errcode = 'P0001';
  end if;

  if p_dry_run then
    foreach v_tbl in array v_order loop
      execute format('select count(*) from public.%I where org_id = $1', v_tbl)
        into v_n using p_org_id;
      if v_n > 0 then
        table_name := v_tbl; rows_affected := v_n; v_total := v_total + v_n;
        return next;
      end if;
    end loop;

    table_name := 'organizations'; rows_affected := 1; return next;
    table_name := 'TOTAL'; rows_affected := v_total + 1; return next;
    table_name := '-- DRY RUN by ' || coalesce(v_actor_name, '?') ||
                  '. Nothing deleted, including no audit row.';
    rows_affected := 0; return next;
    table_name := '-- Auth users and Storage are NOT covered here — the '
                  'Edge Function handles those.';
    rows_affected := 0; return next;
    return;
  end if;

  begin
    insert into audit_log (org_id, entity_type, entity_id, action,
                           actor, actor_name, actor_role, reason, new_value)
    values (p_org_id, 'organizations', p_org_id::text, 'delete_org',
            p_actor, v_actor_name, 'platform_admin',
            format('Deleted tenant "%s" (slug %s, plan_status %s)%s',
                   v_org.name, v_org.slug, coalesce(v_org.plan_status, '-'),
                   case when p_force then ' [FORCED: active plan]' else '' end),
            jsonb_build_object('org_id', p_org_id, 'org_name', v_org.name,
                               'slug', v_org.slug,
                               'plan_status', v_org.plan_status,
                               'forced', p_force, 'at', now()))
    returning id into v_audit_id;
  exception when others then
    raise warning 'audit_log insert FAILED (deletion continuing): %', sqlerrm;
  end;

  if v_audit_id is null then
    raise warning 'No audit row was written for the deletion of % (%).',
                  v_org.name, p_org_id;
  end if;

  update orders set quotation_id = null, lr_id = null, eway_bill_id = null,
                    insurance_policy_id = null, contract_id = null, trip_id = null
   where org_id = p_org_id;
  update quotations         set survey_id = null             where org_id = p_org_id;
  update customer_surveys   set converted_to_order_id = null where org_id = p_org_id;
  update lr_register        set order_id = null              where org_id = p_org_id;
  update eway_bills         set order_id = null              where org_id = p_org_id;
  update insurance_policies set order_id = null              where org_id = p_org_id;
  update claims             set complaint_id = null          where org_id = p_org_id;
  update complaints         set claim_id = null              where org_id = p_org_id;
  update customers          set rate_card_id = null          where org_id = p_org_id;
  update rate_cards         set customer_id = null           where org_id = p_org_id;

  foreach v_tbl in array v_order loop
    execute format('delete from public.%I where org_id = $1', v_tbl) using p_org_id;
    get diagnostics v_n = row_count;
    if v_n > 0 then
      table_name := v_tbl; rows_affected := v_n; v_total := v_total + v_n;
      return next;
    end if;
  end loop;

  update invite_codes set used_by_org_id = null where used_by_org_id = p_org_id;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    table_name := 'invite_codes (used_by_org_id nulled, rows kept)';
    rows_affected := v_n; return next;
  end if;

  delete from organizations where id = p_org_id;
  get diagnostics v_n = row_count;
  table_name := 'organizations'; rows_affected := v_n;
  v_total := v_total + v_n; return next;

  if v_audit_id is not null then
    if exists (select 1 from audit_log where id = v_audit_id) then
      table_name := '-- audit row SURVIVED (id ' || v_audit_id || ', org_id now NULL)';
    else
      table_name := '-- WARNING: audit row was DESTROYED by the deletion. '
                    'The ON DELETE SET NULL fix is not in place.';
    end if;
    rows_affected := 0; return next;
  end if;

  table_name := 'TOTAL'; rows_affected := v_total; return next;
  table_name := '-- Auth users and Storage still remain. The Edge Function '
                'removes those next.';
  rows_affected := 0; return next;
end;
$function$;

do $postflight$
declare
  v_def text;
  v_unknown text[];
begin
  v_def := pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure);

  -- The three new tables are known.
  if position('''branches''' in v_def) = 0 then
    raise exception 'POSTFLIGHT: branches missing from v_order.';
  end if;
  if position('''pin_ip_attempts''' in v_def) = 0 then
    raise exception 'POSTFLIGHT: pin_ip_attempts missing from v_order.';
  end if;
  if position('''pin_lockout_events''' in v_def) = 0 then
    raise exception 'POSTFLIGHT: pin_lockout_events missing from v_order.';
  end if;

  -- branches must come AFTER every branch-FK holder. Asserted via the
  -- last non-branches entry: if branches is not after it, the ordering
  -- was disturbed by an edit.
  if position('''branches''' in v_def) < position('''wage_rate_defaults''' in v_def) then
    raise exception 'POSTFLIGHT: branches is not last in v_order — ON DELETE RESTRICT would block it.';
  end if;

  -- EVERY pre-existing guard must have survived the rewrite.
  if position('is not a platform admin' in v_def) = 0 then
    raise exception 'POSTFLIGHT: the platform_admin check is missing.';
  end if;
  if position('Refusing to run rather than' in v_def) = 0 then
    raise exception 'POSTFLIGHT: the unknown-table orphan guard is missing.';
  end if;
  if position('p_force => true' in v_def) = 0 then
    raise exception 'POSTFLIGHT: the ACTIVE-plan force requirement is missing.';
  end if;
  if position('insert into audit_log' in v_def) = 0 then
    raise exception 'POSTFLIGHT: the audit_log write is missing.';
  end if;
  if position('set quotation_id = null' in v_def) = 0 then
    raise exception 'POSTFLIGHT: the FK-cycle-breaking updates are missing.';
  end if;
  if position('Refusing to delete APC' in v_def) > 0 then
    raise exception 'POSTFLIGHT: the APC guard was reinstated by this rewrite.';
  end if;

  -- And prove the gap is actually closed: no org-scoped table is
  -- unknown any more. This is the same query the function runs.
  select array_agg(t.table_name order by t.table_name) into v_unknown
  from information_schema.tables t
  join information_schema.columns c
    on c.table_schema = t.table_schema and c.table_name = t.table_name
  where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
    and c.column_name = 'org_id'
    and t.table_name not in (
      select unnest from unnest(string_to_array(
        replace(replace(substring(v_def from 'v_order constant text\[\] := array\[(.*?)\]'),
                        E'\n',''), '''', ''), ',')) as unnest
      where trim(unnest) <> ''
    )
    and t.table_name <> all(array[
      'audit_log','consent_records','data_requests','erasure_log',
      'breach_incidents','billing_events','platform_invoices',
      'org_subscriptions','org_usage']);
  if v_unknown is not null then
    raise warning 'POSTFLIGHT: still-unknown org-scoped table(s): %. The literal check above may be imprecise — run a dry run to confirm.',
                  array_to_string(v_unknown, ', ');
  end if;

  raise notice 'POSTFLIGHT OK — 3 tables added, branches last, all guards intact.';
end
$postflight$;

commit;
