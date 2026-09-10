-- delete_org: drop the dead 'surveys' name, drop the converted_to_order_id
-- detach, and make the function refuse to run when v_order names a table
-- that no longer exists.
--
-- Arun, 10 Sept 2026. Follow-up to
-- 20260909_consolidate_survey_tables.sql, which renamed `surveys` to
-- `customer_surveys` and dropped the old empty `customer_surveys`.
--
-- **This file now does the job of two.** The first draft fixed only the two
-- survey lines and asserted the result by matching strings in
-- `pg_get_functiondef`. That assertion was wrong — see below — and the
-- correct fix subsumes it, so the completeness-guard change that was going
-- to be its own migration is folded in here instead.
--
-- ==========================================================================
-- WHY THE FIRST DRAFT REFUSED ITSELF
-- ==========================================================================
--
-- The first draft's postflight ran
--
--     if position('''surveys''' in v_def) > 0 then raise ...
--
-- reasoning that the quotes stop it matching inside `'customer_surveys'`.
-- They do. It still failed, because `pg_get_functiondef` returns the body
-- INCLUDING comments, and the draft had added a tombstone comment at the
-- removal site naming the very thing it removed. The check could not tell a
-- comment from code. The array was correct; the migration did exactly what
-- it was specified to do and its own assertion rolled it back.
--
-- The shape is the one this file's neighbours keep recording: a true test of
-- a NEIGHBOURING question. `pg_constraint` for uniqueness,
-- `pg_available_extensions` for installation, single-target for fragment
-- danger, and now "does this string appear in the text" for "is this table
-- listed in v_order". Quoting the string was a real improvement to the wrong
-- half.
--
-- The tombstone comment stays. It is worth more than the check that tripped
-- on it.
--
-- ==========================================================================
-- SEVERITY: delete_org IS BROKEN RIGHT NOW, INCLUDING DRY RUNS
-- ==========================================================================
--
-- Both loops iterate v_order through dynamic SQL:
--
--     execute format('select count(*) from public.%I where org_id = $1', v_tbl)
--     execute format('delete  from public.%I where org_id = $1', v_tbl)
--
-- `v_order` still contains 'surveys', which no longer names anything, so the
-- FIRST call raises `42P01 relation "public.surveys" does not exist` — and
-- that includes `p_dry_run => true`, the safe inspection path an operator
-- reaches for first. delete_org is not degraded; it is unusable.
--
-- ==========================================================================
-- THE THIRD CHANGE: A RESOLVE GUARD, WHICH IS THE REAL FIX
-- ==========================================================================
--
-- delete_org already refuses to run when it finds an org-scoped table it
-- does NOT know about. That guard scans `information_schema` for tables that
-- EXIST and are unlisted — so it catches a table ADDED. It is structurally
-- incapable of catching a table LISTED that stopped existing, because a
-- table that no longer exists cannot appear in a scan of tables that do.
-- That blind spot is exactly how 'surveys' survived a rename here, and why
-- the failure surfaced as a raw 42P01 from inside dynamic SQL instead of as
-- a sentence naming the cause.
--
-- The new guard closes it: every element of v_order must resolve via
-- `to_regclass` before either loop runs. It is also the assertion the
-- postflight needs, which is why the string matching is gone — a successful
-- dry run now PROVES every listed table resolves, including that 'surveys'
-- is no longer among them. Behaviour, not text.
--
-- ==========================================================================
-- ORDERING: CHECKED AGAINST THE FK GRAPH, AND NOTHING MOVES
-- ==========================================================================
--
--   OUTBOUND  surveys_lead_id_fkey   -> leads           confdeltype 'a' (NO ACTION)
--   OUTBOUND  surveys_org_id_fkey    -> organizations   confdeltype 'a'
--   INBOUND   quotations_survey_id_fkey <- quotations   confdeltype 'n' (SET NULL)
--
-- The constraining one is the OUTBOUND NO ACTION to `leads`: survey rows
-- must be deleted BEFORE leads. `'customer_surveys'` sits after
-- `'vehicle_trips'`; `'leads'` sits far later, between `'wa_contacts'` and
-- `'customers'`. Already satisfied. The old `'surveys'` entry — between
-- `'warehouses'` and `'tds_entries'` — satisfied it too. Both positions were
-- valid; neither was load-bearing relative to the other. The inbound FK
-- constrains nothing, because the detach block above the loop already runs
-- `update quotations set survey_id = null` before any delete.
--
-- **So nothing moves.** A dead name is deleted and `'customer_surveys'`
-- stays exactly where it already sits.
--
-- ==========================================================================
-- THE converted_to_order_id LINE
-- ==========================================================================
--
-- Removed, not re-created:
--   * Dart never reads or writes it — only the getter declaration at
--     `tables/customer_surveys.dart:131` and two comments, one of which
--     says the convert path does NOT write it.
--   * Its only job was FK detachment for
--     `customer_surveys_converted_to_order_id_fkey -> orders(id)`, and that
--     FK died with the dropped table.
--   * The link already exists and is populated:
--     `orders.quotation_id -> quotations.survey_id -> customer_surveys.id`,
--     verified on all three 9 Sept flow-test orders.
--
-- Everything else is byte-for-byte from `pg_get_functiondef`. The return
-- type is unchanged, so CREATE OR REPLACE is correct and no DROP is needed.

begin;

-- ==========================================================================
-- PREFLIGHT
-- ==========================================================================
do $pre$
begin
  if to_regclass('public.customer_surveys') is null then
    raise exception 'PREFLIGHT: public.customer_surveys does not exist. Run 20260909_consolidate_survey_tables.sql first.';
  end if;

  if to_regclass('public.surveys') is not null then
    raise exception 'PREFLIGHT: public.surveys still exists, so the rename has not happened. This migration assumes it has.';
  end if;

  if exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='customer_surveys'
       and column_name='converted_to_order_id'
  ) then
    raise exception 'PREFLIGHT: customer_surveys has a converted_to_order_id column. This migration removes the line that maintains it — re-check the decision before running.';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='delete_org'
  ) then
    raise exception 'PREFLIGHT: delete_org does not exist.';
  end if;
end
$pre$;

-- ==========================================================================
-- THE FUNCTION
-- ==========================================================================
CREATE OR REPLACE FUNCTION public.delete_org(p_org_id uuid, p_actor uuid, p_dry_run boolean DEFAULT true, p_force boolean DEFAULT false)
 RETURNS TABLE(table_name text, rows_affected bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_org         record;
  v_actor_name  text;
  v_unknown     text[];
  v_missing     text[];
  v_tbl         text;
  v_n           bigint;
  v_total       bigint := 0;
  v_audit_id    uuid;

  v_order constant text[] := array[
    'account_transfers','activities','tasks','addons','app_settings',
    'attendance','backup_registry','bank_statement_lines','bank_statements',
    'claim_items','claims','complaints','credit_notes','customer_addresses',
    'customer_contacts','discount_policies','document_signatures','documents',
    'eway_consolidated','eway_vehicle_updates',
    -- Both of these must precede 'expenses', and that is what fixes their
    -- position — not tidiness. Parent positions in the pre-fix array:
    -- expenses 21, orders 97, staff 99, vehicles 101, vendors 102. The
    -- earliest parent binds, and for both of these it is expenses.
    --   expense_splits -> expenses (CASCADE), orders (a), staff (a)
    --   fuel_fills     -> expenses (a), orders (a), staff (a),
    --                     vehicles (a), vendors (a)
    -- fuel_fills is the constrained one — five parents, all NO ACTION, and
    -- sitting anywhere after position 21 would fail against expenses.
    -- Neither references the other (both are leaves, zero inbound FKs), so
    -- their order relative to each other is free.
    --
    -- expense_splits would be removed by the CASCADE from expenses even if
    -- it were not listed. It is listed anyway so the dry run REPORTS it: a
    -- row deleted by a cascade that no line accounts for is silent
    -- behaviour, and listing it here means it is deleted explicitly first,
    -- so the cascade never fires and the count is honest.
    'expense_splits','fuel_fills',
    'expenses','export_jobs',
    'follow_up_logs','reminders','gst_returns','job_expense_float_entries',
    'job_expense_floats','job_photos','order_status_history','journal_lines',
    'journal_entries','chart_of_accounts','account_groups','ledger_entries',
    'lr_copies','lr_series','marketing_spend','notification_log',
    'notification_tokens','notification_prefs','notifications','number_series',
    -- Its only FK is doc_prefix_reservations -> organizations, and that is
    -- ON DELETE SET NULL against a row this function deletes AFTER the loop
    -- finishes. So position is genuinely unconstrained here — this sits
    -- beside number_series because that is what it is about (it holds a
    -- document prefix for an org that may not exist yet), not because the
    -- graph demands it. Saying so explicitly: if a future edit needs to
    -- move it, nothing breaks.
    -- It must be LISTED though. Without a line here the SET NULL fires
    -- instead of a delete, and the reservation survives its org as an
    -- orphan with a null org_id.
    'doc_prefix_reservations',
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
    -- One parent: staff_session_events -> staff (NO ACTION), at position 99.
    -- Anywhere before that satisfies it, so it goes in the staff cluster
    -- (positions 71-75) where a reader looking for staff-scoped tables will
    -- find it, rather than at the first legal slot.
    'staff_session_events',
    'stock_movements','grn','purchase_orders','materials',
    'storage_billing_cycles','storage_items','storage_jobs','warehouses',
    -- The old survey table was removed from this list on 10 Sept 2026. It
    -- was renamed by 20260909_consolidate_survey_tables.sql and is already
    -- listed below under its new name, in a position that satisfies its
    -- ON DELETE NO ACTION reference to leads. Nothing moved.
    'tds_entries','vendor_payments','bank_accounts','vendor_bills',
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

  -- Added 10 Sept 2026. The guard above scans tables that EXIST and are
  -- unlisted, so it catches a table ADDED. It cannot catch a table LISTED
  -- that stopped existing — a missing table cannot appear in a scan of
  -- present ones. That blind spot let a renamed table sit in this array
  -- until the first call died on a raw 42P01 from inside the dynamic SQL
  -- below, dry runs included. Check it here, where the message can name
  -- the cause.
  -- The test is deliberately the EXACT MIRROR of the guard above — public
  -- schema, BASE TABLE, carries org_id — not merely `to_regclass(...) is
  -- not null`. A bare existence check leaves two holes the loop would still
  -- fall into: a listed name that now resolves to a VIEW (to_regclass
  -- resolves any relation, and `delete from` a view is not the same
  -- statement), and a listed base table that lost its org_id column, which
  -- fails with 42703 rather than 42P01. Matching the other guard's criteria
  -- means the two together cover exactly one property between them —
  -- "the set of org-scoped base tables equals v_order plus v_keep" — from
  -- both directions.
  v_missing := array[]::text[];
  foreach v_tbl in array v_order loop
    if not exists (
      select 1
        from information_schema.tables t
        join information_schema.columns c
          on c.table_schema = t.table_schema and c.table_name = t.table_name
       where t.table_schema = 'public'
         and t.table_type   = 'BASE TABLE'
         and t.table_name   = v_tbl
         and c.column_name  = 'org_id'
    ) then
      v_missing := v_missing || v_tbl;
    end if;
  end loop;

  if array_length(v_missing, 1) > 0 then
    raise exception
      'delete_org() lists % entr(ies) that are not org-scoped base tables '
      'in public (%). Each was renamed, dropped, turned into a view, or '
      'lost its org_id column without v_order being updated. Refusing to '
      'run rather than failing partway through the loop.',
      array_length(v_missing, 1), array_to_string(v_missing, ', ')
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
  -- The detach for the old survey table's converted_to_order_id column stood
  -- here and was removed on 10 Sept 2026. That column belonged to the table
  -- dropped by 20260909_consolidate_survey_tables.sql; the surviving table
  -- has no such column and the line raised 42703. The survey-to-order link
  -- it was meant to break lives on orders.quotation_id -> quotations, and
  -- the line above already nulls that side.
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

-- ==========================================================================
-- POSTFLIGHT — assert the PROPERTY, not the text
-- ==========================================================================
-- No check here asks whether a string appears in the body. The first draft
-- did, and matched its own comment.
do $post$
declare
  v_code      text;
  v_admin     uuid;
  v_org       uuid;
  v_expected  bigint;
  v_got       bigint;
begin
  select user_id into v_admin from platform_admins limit 1;

  -- Pick the org that actually HAS survey rows. The dry run only emits a
  -- line for a table with a non-zero count, so asserting against an org with
  -- no surveys would prove nothing and pass.
  select org_id into v_org
    from public.customer_surveys
   group by org_id order by count(*) desc limit 1;

  if v_admin is null or v_org is null then
    raise exception
      'POSTFLIGHT: need a platform admin and an org holding survey rows to assert this behaviourally. admin=%, org=%.',
      v_admin, v_org;
  end if;

  select count(*) into v_expected
    from public.customer_surveys where org_id = v_org;

  -- THE ASSERTION. A dry run walks every element of v_order, and the resolve
  -- guard added above raises before it if any element names nothing — so a
  -- dry run that completes proves every listed table exists, which is the
  -- property "'surveys' is no longer listed" restated as something testable.
  -- Reading back the count for customer_surveys proves the surviving table
  -- is still listed AND still org-scoped correctly: if it had been dropped
  -- from v_order, no row would come back and v_got would be null.
  --
  -- Safe to call: p_dry_run returns before the audit insert and before every
  -- update and delete. It writes nothing.
  select rows_affected into v_got
    from public.delete_org(v_org, v_admin, true, false)
   where table_name = 'customer_surveys';

  if v_got is null then
    raise exception
      'POSTFLIGHT: the dry run returned no customer_surveys line for an org holding % survey row(s). The table is missing from v_order and its rows would be orphaned on delete.',
      v_expected;
  end if;

  if v_got <> v_expected then
    raise exception
      'POSTFLIGHT: dry run counted % customer_surveys row(s), the table holds % for that org.',
      v_got, v_expected;
  end if;

  -- converted_to_order_id is a COLUMN, so no runtime guard covers it without
  -- performing a real delete. Text is the right instrument for a code-shape
  -- question — but only over code. Comment lines are stripped first, because
  -- the tombstone above deliberately names the thing it removed, and that is
  -- exactly what tripped the first draft.
  select string_agg(ln, E'\n')
    into v_code
    from (
      select ln from unnest(string_to_array(
               pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure),
               E'\n')) as t(ln)
       where ltrim(ln) not like '--%'
    ) s;

  if position('converted_to_order_id' in v_code) > 0 then
    raise exception 'POSTFLIGHT: delete_org still writes converted_to_order_id outside a comment.';
  end if;

  -- And the new guard is present as CODE, not merely described in prose.
  if position('v_missing' in v_code) = 0 then
    raise exception 'POSTFLIGHT: the resolve guard is not in the function body.';
  end if;
end
$post$;

commit;

-- ==========================================================================
-- ROLLBACK
-- ==========================================================================
-- Restoring the previous body would put back a dead table name and a write
-- to a dropped column — a delete_org that raises 42P01 on its first call,
-- dry runs included. There is no reason to want that. Fix forward.
