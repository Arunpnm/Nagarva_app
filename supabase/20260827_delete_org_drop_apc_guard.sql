-- =====================================================================
-- 20260827_delete_org_drop_apc_guard.sql
--
-- Removes delete_org()'s unconditional refusal to delete APC.
--
-- WHY THIS IS CORRECT AND NOT A HACK
-- ----------------------------------
-- The guard hardcodes tenant #1's uuid:
--
--     c_apc constant uuid := '11111111-1111-4111-8111-111111111111';
--     if p_org_id = c_apc then
--       raise exception 'Refusing to delete APC (tenant #1) ...'
--
-- That uuid is a hand-assigned seed value from the original single-
-- tenant migration. Step 4 of the wipe (NAGARVA_MODULE_STATUS.md
-- section 11) deletes every org, and the real orgs are then recreated
-- through signup, which generates ids with gen_random_uuid(). No future
-- org can ever hold that literal again, so after the wipe the guard is
-- permanently inert code that reads as if it protects something.
--
-- Keeping it would mean either dead code or, worse, a second deletion
-- path for one org — and using two mechanisms across four orgs is
-- exactly how one of them ends up with orphaned rows in 106 tables that
-- have no FK to organizations.
--
-- EVERYTHING ELSE IS PRESERVED VERBATIM, and that matters:
--   * the platform_admin check on p_actor
--   * the p_force requirement for an ACTIVE plan
--   * the "unknown org-scoped table" guard, which REFUSES TO RUN rather
--     than leave orphans if a new table has appeared
--   * the audit_log write, and the post-delete proof it survived
--   * the FK-cycle-breaking updates
--   * the full 110-table ordered delete list
--
-- Body reproduced from pg_get_functiondef() read live on 27 Aug 2026,
-- with ONLY the guard block and its constant removed.
--
-- Signature is unchanged, so CREATE OR REPLACE is correct (no DROP, so
-- no ACL loss — contrast 20260827_org_intent_and_trial_inheritance.sql).
-- =====================================================================

begin;

do $preflight$
begin
  if to_regprocedure('public.delete_org(uuid,uuid,boolean,boolean)') is null then
    raise exception 'PREFLIGHT: delete_org(uuid,uuid,boolean,boolean) not found.';
  end if;
  if position('Refusing to delete APC' in
        pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure)) = 0 then
    raise exception 'PREFLIGHT: the APC guard is already absent — this migration has run, or the body changed. Re-read it before proceeding.';
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
    'order_vendors','org_members','org_pin_attempts','payment_entries',
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
    'lead_sources','wage_rate_defaults'
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

  -- APC GUARD REMOVED 27 Aug 2026 (see this migration's header). The
  -- p_force requirement below is now the only brake, and it still
  -- applies to APC because its plan_status is 'active'.

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
begin
  if position('Refusing to delete APC' in
        pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure)) > 0 then
    raise exception 'POSTFLIGHT: the APC guard is still present.';
  end if;
  -- The guards that must NOT have been lost in the rewrite.
  if position('is not a platform admin' in
        pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure)) = 0 then
    raise exception 'POSTFLIGHT: the platform_admin check is missing.';
  end if;
  if position('Refusing to run rather than' in
        pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure)) = 0 then
    raise exception 'POSTFLIGHT: the unknown-table orphan guard is missing.';
  end if;
  if position('p_force => true' in
        pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure)) = 0 then
    raise exception 'POSTFLIGHT: the ACTIVE-plan force requirement is missing.';
  end if;
  raise notice 'POSTFLIGHT OK — APC guard removed, all other guards intact.';
end
$postflight$;

commit;
