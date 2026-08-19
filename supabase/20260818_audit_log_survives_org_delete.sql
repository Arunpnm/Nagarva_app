-- ============================================================
-- supabase/20260818_audit_log_survives_org_delete.sql
--
-- Fixes the third silent failure of the tenant-deletion audit row.
--
-- ---- ROOT CAUSE (18 Aug 2026) --------------------------------------
-- It was never the column names, and never the exception handler. There
-- was no error to catch. The constraint was:
--
--   audit_log_org_id_fkey
--     FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE CASCADE
--   audit_log.org_id NOT NULL
--
-- So inside delete_org()'s transaction:
--   1. the audit row INSERTS successfully — no exception raised;
--   2. the 109 ordered deletes run;
--   3. the final `delete from organizations` CASCADES and destroys the
--      audit row that was just written.
--
-- The record was being deleted by the very operation it existed to
-- record. NOT NULL + CASCADE together mean no audit_log row can ever
-- survive its own org's deletion — the table was structurally incapable
-- of recording a tenant deletion, and no amount of rewriting the
-- function could have fixed it.
--
-- Corroborated before changing anything: `audit_log` had 0 rows whose
-- org_id has no matching organizations row. In a table without a cascade
-- you would expect orphans after two org deletions; zero is what a
-- cascade guarantees.
--
-- ---- THE OTHER EIGHT KEEP-LIST TABLES ARE CLEAN --------------------
-- Checked all foreign keys on every keep-list table before writing this.
-- `audit_log` was the ONLY one with an org_id FK, and the only one with
-- CASCADE anywhere:
--
--   audit_log         org_id -> organizations          ON DELETE CASCADE  <-- the bug
--   erasure_log       request_id -> data_requests      ON DELETE SET NULL (safe)
--   platform_invoices subscription_id -> org_subscriptions ON DELETE SET NULL (safe)
--   org_subscriptions plan_id -> subscription_plans    NO ACTION (safe)
--   consent_records   (no foreign keys)
--   data_requests     (no foreign keys)
--   billing_events    (no foreign keys)
--   org_usage         (no foreign keys)
--   breach_incidents  (no foreign keys)
--
-- **platform_invoices is safe** — it has no org_id FK at all, and its
-- one FK is SET NULL onto a table that is itself never deleted. Nagarva's
-- revenue records do not vanish when a tenant is deleted.
--
-- ---- RLS NEEDS NO CHANGE -------------------------------------------
-- audit_log's policy is already:
--   (org_id IN (SELECT current_org_ids())) OR is_platform_admin()
-- With org_id NULL the first branch cannot match, so the row is visible
-- to platform admins ONLY. That is the intended outcome, not a
-- side effect: a tenant-deletion record should be readable by the
-- platform and by no tenant — least of all the deleted one.
--
-- HANDED BACK UNRUN.
-- ============================================================

begin;

-- ---- 1. Let the audit row outlive the org --------------------------
-- Dropping NOT NULL is non-breaking: every existing row keeps its value.
alter table audit_log alter column org_id drop not null;

alter table audit_log drop constraint if exists audit_log_org_id_fkey;
alter table audit_log
  add constraint audit_log_org_id_fkey
  foreign key (org_id) references organizations(id) on delete set null;

comment on column audit_log.org_id is
  'NULL means the organization has been deleted — the FK is ON DELETE '
  'SET NULL precisely so the audit row survives the deletion it records. '
  'It was ON DELETE CASCADE until 18 Aug 2026, which silently destroyed '
  'every tenant-deletion record. Do NOT restore CASCADE. A NULL here also '
  'makes the row platform-admin-only under the existing org_isolation '
  'policy, which is intended. The org it referred to is recorded in '
  'entity_id, reason and new_value — see delete_org().';

-- ---- 2. Denormalise identity into the row itself -------------------
-- With org_id NULL and the organizations row gone, "an org was deleted"
-- is useless. The function below now writes the name and slug into both
-- `reason` (human-readable, shows in any log viewer) and `new_value`
-- (structured, queryable). No new column needed — audit_log already has
-- both, and adding one would mean every other audit writer has to learn
-- about it.
--
-- Only the audit INSERT block changes; the rest of the function is
-- byte-identical to 20260818_delete_org.sql revision 2. Signature
-- unchanged, so CREATE OR REPLACE is sufficient — no DROP needed.
create or replace function public.delete_org(
  p_org_id uuid,
  p_actor uuid,
  p_dry_run boolean default true,
  p_force boolean default false
)
returns table(table_name text, rows_affected bigint)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  c_apc constant uuid := '11111111-1111-4111-8111-111111111111';

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

  if p_org_id = c_apc then
    raise exception 'Refusing to delete APC (tenant #1). This is guarded '
                    'unconditionally — the force flag does not apply.'
      using errcode = 'P0001';
  end if;

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

  ----------------------------------------------------------------
  -- Audit BEFORE deleting.
  --
  -- org_id is set here and becomes NULL automatically when the
  -- organizations row is deleted below (ON DELETE SET NULL, as of this
  -- migration). Everything needed to identify the tenant afterwards is
  -- therefore denormalised INTO the row: entity_id holds the uuid,
  -- `reason` holds a readable sentence, and `new_value` holds the
  -- structured name/slug. Without this the surviving row would say
  -- "an org was deleted" and nothing more.
  --
  -- The handler stays so an audit problem can never block a lawful
  -- erasure, but it now RAISES WARNING and re-checks below rather than
  -- failing silently — silence is what hid this bug three times.
  ----------------------------------------------------------------
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

  -- Break the three FK cycles. No topological order exists through
  -- these. All 15 columns verified nullable 18 Aug 2026.
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

  -- Prove the audit row survived, in the same transaction that deleted
  -- the org. Three silent failures is enough: this reports rather than
  -- assumes, and the caller sees it in the result set.
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
$fn$;

revoke all on function public.delete_org(uuid, uuid, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.delete_org(uuid, uuid, boolean, boolean)
  to service_role;

commit;

-- ============================================================
-- VERIFY the schema change took (read-only):
--
--   select a.attnotnull as org_id_not_null,
--          pg_get_constraintdef(c.oid) as fk
--     from pg_attribute a
--     join pg_class t on t.oid = a.attrelid
--     left join pg_constraint c on c.conrelid = t.oid and c.contype='f'
--          and a.attnum = any(c.conkey)
--    where t.relname='audit_log' and a.attname='org_id';
--
-- Expect: org_id_not_null = false, and "... ON DELETE SET NULL".
--
-- Then delete TEST 1 through admin-delete-org and confirm the response
-- shows `audit_row_written: true` AND the result set contains the
-- "audit row SURVIVED" line. Both must agree — they are computed
-- independently (one in SQL inside the transaction, one from the Edge
-- Function afterwards), so agreement is meaningful.
--
--   select action, entity_id, org_id, actor_name, reason, new_value
--     from audit_log where action = 'delete_org';
-- ============================================================
