-- 20261110_delete_org_complete_list.sql  (10 Nov 2026)
--
-- "Delete company" in Nagarva Admin has been refusing every call. Its
-- completeness guard found 15 company tables it did not know about, all
-- added since the last update on 10 Sept (photo survey usage, CFT
-- catalogue, crew check-in, staff leave and incentives, marketplace,
-- WhatsApp, support tickets, platform audit, vendor signups...).
--
-- What this changes (and nothing else):
--   1. 12 tables added to v_order (deleted with the company). Position
--      checked against every foreign key by the postflight below.
--   2. platform_audit, mkt_job_events and vendor_signups added to v_keep
--      (the platform's own records; kept).
--   3. vendor_signups: link to the company cleared before the company row
--      is deleted. Its NO ACTION key would otherwise have failed the final
--      delete for any company that came in through the signup form, even
--      with the list complete. The signup record itself is kept.
--
-- Built from 20260910_delete_org_after_survey_rename.sql, whose body
-- matches the live function exactly (checked 10 Nov 2026 by md5 of the
-- source with CRs removed). The preflight refuses if the live function has
-- changed since, so this can never overwrite a newer version unseen.
-- Signature and return type unchanged, so CREATE OR REPLACE keeps the
-- existing grants (postgres, service_role only); the postflight asserts it.
--
-- THE PROOF IS BEHAVIOURAL. The postflight really deletes EVERY company,
-- one at a time, inside a savepoint that is then rolled back, so the full
-- ordering is exercised against the real data and nothing is lost. If any
-- delete fails, the whole migration rolls back and names the company and
-- the error. (Dry runs alone cannot prove ordering: they only count.)
--
-- Run the WHOLE file. One transaction.

begin;

-- ---------- preflight -------------------------------------------------
do $pre$
declare
  v_md5 text;
  v_missing text[];
begin
  select md5(replace(prosrc, E'\r', '')) into v_md5
    from pg_proc where oid = to_regprocedure('public.delete_org(uuid,uuid,boolean,boolean)');
  if v_md5 is null then
    raise exception 'public.delete_org(uuid,uuid,boolean,boolean) does not exist -- wrong database?';
  end if;
  if v_md5 <> '31b8eea4d6067c397313a33dd0311311' then
    raise exception 'delete_org has changed since 10 Sept (md5 %). This file was built on the 10 Sept version; rebuild it on the live one rather than overwrite it.', v_md5;
  end if;

  select array_agg(n) into v_missing
    from unnest(array['ai_survey_usage','cft_catalogue','crew_checkins',
      'job_checkin_keys','staff_incentives','staff_leaves','mkt_wallet_entries',
      'mkt_vendors','platform_broadcast_recipients','support_tickets',
      'wa_templates','wa_accounts','platform_audit','mkt_job_events',
      'vendor_signups']) n
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema = 'public' and c.table_name = n
                        and c.column_name = 'org_id');
  if v_missing is not null then
    raise exception 'Expected org-scoped tables are missing: %', array_to_string(v_missing, ', ');
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'vendor_signups'
                    and column_name = 'org_id' and is_nullable = 'YES') then
    raise exception 'vendor_signups.org_id is missing or NOT NULL -- the clear-the-link step cannot run.';
  end if;

  if not exists (select 1 from platform_admins) then
    raise exception 'No platform admin exists, so the postflight cannot run delete_org. Nothing changed.';
  end if;
  if not exists (select 1 from organizations) then
    raise exception 'No company exists, so the postflight would test nothing. Nothing changed.';
  end if;
end $pre$;

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
    -- Added 10 Nov 2026 (20261110_delete_org_complete_list.sql). These were
    -- the 12 org-scoped tables added since September that this list did
    -- not know about, which made the completeness guard refuse every call.
    -- Placed here because three of them hang off staff (crew_checkins,
    -- staff_incentives, staff_leaves, all ON DELETE CASCADE) and 'staff'
    -- comes later; the other nine have no foreign key to any listed table,
    -- so any position before 'branches' is legal. Checked by query, not by
    -- reading: no NO ACTION/RESTRICT key anywhere points from a later entry
    -- to an earlier one with this order (see the migration's postflight).
    --   support_tickets: its replies (support_ticket_replies, no org_id)
    --   go with it by ON DELETE CASCADE, so they are not counted here.
    --   mkt_wallet_entries: has ON DELETE CASCADE on org_id, so it can
    --   never outlive the org whatever this list says; listed so the dry
    --   run reports it.
    'ai_survey_usage','cft_catalogue','crew_checkins','job_checkin_keys',
    'staff_incentives','staff_leaves','mkt_wallet_entries','mkt_vendors',
    'platform_broadcast_recipients','support_tickets','wa_templates',
    'wa_accounts',
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
    'org_subscriptions','org_usage',
    -- 10 Nov 2026. The platform's own records, kept like audit_log:
    --   platform_audit  - Nagarva admin actions; no foreign key at all.
    --   mkt_job_events  - marketplace job history shared with the
    --                     customer's job; org_id is ON DELETE SET NULL.
    --   vendor_signups  - the application record. Its org_id is cleared
    --                     below (NO ACTION key), the row itself is kept.
    'platform_audit','mkt_job_events','vendor_signups'
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

  -- 10 Nov 2026. vendor_signups.org_id -> organizations is NO ACTION, so a
  -- company that came in through the signup form could not be deleted at
  -- all: the final delete below failed on it. Same treatment as
  -- invite_codes: the application record is kept (it is the platform's
  -- record of who applied), only its link to the deleted company is
  -- cleared. The row goes when the applicant's auth user is deleted
  -- (auth_user_id is ON DELETE CASCADE), which the Edge Function does next.
  update vendor_signups set org_id = null where org_id = p_org_id;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    table_name := 'vendor_signups (org_id nulled, rows kept)';
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

-- ---------- postflight ------------------------------------------------
do $post$
declare
  v_admin   uuid;
  v_org     record;
  v_rows    integer;
  v_err     text;
  v_tested  integer := 0;
  v_bad     text;
  v_total   bigint;
begin
  -- Grants unchanged: only postgres and service_role may execute.
  if has_function_privilege('anon', 'public.delete_org(uuid,uuid,boolean,boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.delete_org(uuid,uuid,boolean,boolean)', 'execute') then
    raise exception 'delete_org is executable by anon or authenticated after the replace';
  end if;

  -- Ordering, from the catalogue: no NO ACTION/RESTRICT key may point from
  -- an earlier v_order entry to a later one (that delete would fail), apart
  -- from the columns the function clears before its loop.
  with def as (select pg_get_functiondef('public.delete_org(uuid,uuid,boolean,boolean)'::regprocedure) d),
  arr as (select regexp_replace(substring(d from 'v_order constant text\[\] := array\[(.*?)\];'), '--[^\n]*', '', 'g') o from def),
  pos as (select m[1] t, row_number() over () i from arr, regexp_matches(arr.o, '''([a-z_0-9]+)''', 'g') m),
  nulled(tbl, col) as (values ('orders','quotation_id'),('orders','lr_id'),('orders','eway_bill_id'),
    ('orders','insurance_policy_id'),('orders','contract_id'),('orders','trip_id'),
    ('quotations','survey_id'),('lr_register','order_id'),('eway_bills','order_id'),
    ('insurance_policies','order_id'),('claims','complaint_id'),('complaints','claim_id'),
    ('customers','rate_card_id'),('rate_cards','customer_id')),
  fk as (select c.conrelid::regclass::text child, c.confrelid::regclass::text parent,
                (select string_agg(a.attname, ',') from pg_attribute a
                  where a.attrelid = c.conrelid and a.attnum = any(c.conkey)) cols
           from pg_constraint c
          where c.contype = 'f' and c.connamespace = 'public'::regnamespace
            and c.confdeltype in ('a', 'r') and c.conrelid <> c.confrelid)
  select string_agg(fk.child || ' -> ' || fk.parent, ', ') into v_bad
    from fk join pos pc on pc.t = fk.child join pos pp on pp.t = fk.parent
   where pc.i > pp.i
     and not exists (select 1 from nulled n where n.tbl = fk.child and n.col = fk.cols);
  if v_bad is not null then
    raise exception 'v_order deletes a parent before its child: %', v_bad;
  end if;

  -- Behaviour: really delete each company, then roll that delete back.
  select user_id into v_admin from platform_admins limit 1;
  for v_org in select id, name from organizations order by created_at loop
    v_err := null;
    begin
      -- dry run first: proves both guards pass for this company
      select count(*) into v_rows
        from public.delete_org(v_org.id, v_admin, true, true) r
       where r.table_name = 'TOTAL';
      if v_rows <> 1 then
        raise exception 'dry run returned no TOTAL line';
      end if;
      -- the real thing, forced (paying companies need p_force)
      select coalesce(sum(r.rows_affected), 0) into v_total
        from public.delete_org(v_org.id, v_admin, false, true) r
       where r.table_name = 'organizations';
      if v_total <> 1 then
        raise exception 'the company row was not deleted (% rows)', v_total;
      end if;
      if exists (select 1 from organizations where id = v_org.id) then
        raise exception 'the company row still exists after delete';
      end if;
      raise exception 'PROBE-ROLLBACK';
    exception when others then
      if sqlerrm <> 'PROBE-ROLLBACK' then
        v_err := sqlerrm;
      end if;
    end;
    if v_err is not null then
      raise exception 'Deleting "%" would fail: %', v_org.name, v_err;
    end if;
    if not exists (select 1 from organizations where id = v_org.id) then
      raise exception 'Probe for "%" was not rolled back -- stopping.', v_org.name;
    end if;
    v_tested := v_tested + 1;
  end loop;

  if v_tested <> (select count(*) from organizations) or v_tested = 0 then
    raise exception 'Tested % companies, expected %', v_tested, (select count(*) from organizations);
  end if;
  raise notice 'delete_org: every company (%) deletes cleanly; all probes rolled back.', v_tested;
end $post$;

commit;
