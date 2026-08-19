-- ============================================================
-- supabase/20260818_delete_org.sql   (REVISION 2 — 18 Aug 2026)
--
-- delete_org(p_org_id, p_actor, p_dry_run, p_force) — remove one tenant's
-- data in dependency order, or report what WOULD be removed.
--
-- ---- WHY REVISION 2 -------------------------------------------------
-- Revision 1 could never execute. Arun found it on the first real call:
--
--   * The function is SECURITY DEFINER with EXECUTE revoked from
--     `authenticated`, so only `service_role`/`postgres` can call it.
--   * But its first guard was `is_platform_admin()`, which reads
--     `auth.uid()`.
--   * Under `service_role` there is no `sub` claim, so `auth.uid()` is
--     NULL, `is_platform_admin()` is false, and the guard raises.
--   * Under `authenticated` `auth.uid()` works — but there is no EXECUTE.
--
-- Both conditions could never hold at once. A session-derived identity
-- check is simply incompatible with a service-role-only grant. That is a
-- design error, not a tuning problem.
--
-- FIX (Arun's, 18 Aug 2026): the platform-admin check moves to the Edge
-- Function, which verifies the CALLER's own JWT, and the verified actor
-- uuid is passed in as `p_actor`. The RPC keeps a second layer, but
-- sourced from that parameter instead of a session variable that will
-- always be empty here.
--
-- The service_role-only grant stays: a vendor JWT still cannot reach
-- this function directly, so p_actor cannot be spoofed by anyone who
-- isn't already service_role.
--
-- Also fixed in this revision: the audit insert used `entity`, but the
-- live column is `entity_type`, and there is a dedicated `actor` uuid
-- column that revision 1 didn't populate. Because that insert sits in an
-- exception handler, the mismatch would have silently skipped the audit
-- row on every run — the one record that must survive a deletion.
--
-- ---- THIS FUNCTION IS NOT THE WHOLE JOB ----------------------------
-- Public-schema rows only. A tenant delete is not complete — and for
-- DPDP is not lawful — until `admin-delete-org` has also removed the
-- Supabase Auth users and Storage objects. **auth.users is where the
-- email address lives.** Always go through the Edge Function; it is now
-- also the only path that can authenticate at all.
--
-- Full rationale, table list, and how the ordering was derived:
-- NG-SCOPE-delete-org.md
--
-- HANDED BACK UNRUN.
-- ============================================================

begin;

-- Revision 1's signature exists in the database (Arun ran it). Dropping
-- explicitly rather than relying on CREATE OR REPLACE: the argument list
-- changes, so this would otherwise create a second overload and make
-- every call ambiguous.
drop function if exists public.delete_org(uuid, boolean, boolean);

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
  -- Tenant #1, Arun's own live business. No automated path removes it,
  -- force flag or not.
  c_apc constant uuid := '11111111-1111-4111-8111-111111111111';

  v_org         record;
  v_actor_name  text;
  v_unknown     text[];
  v_tbl         text;
  v_n           bigint;
  v_total       bigint := 0;

  -- Deletion order: children before parents. Derived by Tarjan SCC +
  -- Kahn's algorithm over the live FK graph (18 Aug 2026), NOT authored
  -- by hand. If the schema changes, recompute — do not patch by hand.
  -- The coverage check below is what stops this list going stale
  -- silently.
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

  -- Deliberately NEVER deleted with the tenant. Each exists precisely to
  -- outlive the account — see NG-SCOPE-delete-org.md §1. Short version:
  -- DPDP erasure covers the vendor's data, not the platform's lawful
  -- record of the commercial relationship. Their orders are theirs; our
  -- invoices are ours. These keep a dangling org_id on purpose; do NOT
  -- "fix" that with foreign keys, which would force either cascade
  -- (destroying them) or restrict (making deletion impossible).
  v_keep constant text[] := array[
    'audit_log',          -- the only record of what happened, if disputed
    'consent_records',    -- proof of consent; needed BECAUSE they left
    'data_requests',      -- the erasure request itself
    'erasure_log',        -- the record of what was erased
    'breach_incidents',   -- statutory retention
    'billing_events',     -- what they were charged, and when
    'platform_invoices',  -- NAGARVA's revenue records, not tenant data
    'org_subscriptions',  -- subscription history behind those invoices
    'org_usage'           -- aggregate usage backing billing disputes
  ];
begin
  ----------------------------------------------------------------
  -- Guards
  --
  -- NOTE the deliberate absence of is_platform_admin() here — see this
  -- file's header. Under service_role auth.uid() is NULL, so that check
  -- could only ever fail. The caller's identity is verified in
  -- admin-delete-org (against their real JWT) and arrives as p_actor;
  -- what follows is the second layer, re-derived from that parameter.
  ----------------------------------------------------------------
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

  ----------------------------------------------------------------
  -- Coverage check — MANDATORY, per Arun (18 Aug 2026):
  -- "Without it this function rots into the exact bug it exists to
  -- prevent."
  --
  -- Any BASE TABLE carrying org_id in neither list means the schema grew
  -- and this function didn't. Failing loudly is the point: a silent miss
  -- is a new orphan.
  ----------------------------------------------------------------
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

  ----------------------------------------------------------------
  -- DRY RUN — count only, write nothing, in the same order.
  ----------------------------------------------------------------
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
                  '. Nothing deleted. Re-send with dry_run=false to delete.';
    rows_affected := 0; return next;
    table_name := '-- Auth users and Storage are NOT covered here — the '
                  'Edge Function handles those, and they are what actually '
                  'erase the email address.';
    rows_affected := 0; return next;
    return;
  end if;

  ----------------------------------------------------------------
  -- REAL RUN. One transaction: all tables or none — a partially deleted
  -- tenant is worse than an undeleted one.
  ----------------------------------------------------------------

  -- Audit BEFORE deleting, so intent is recorded even if the process
  -- dies mid-way. Column names verified against the live schema this
  -- revision (`entity_type`, not `entity`; `actor` uuid populated) —
  -- revision 1 got these wrong and, because of the exception handler
  -- below, would have skipped the audit row silently on every run.
  begin
    insert into audit_log (org_id, entity_type, entity_id, action,
                           actor, actor_name, actor_role, reason, new_value)
    values (p_org_id, 'organizations', p_org_id::text, 'delete_org',
            p_actor, v_actor_name, 'platform_admin',
            case when p_force then 'forced delete of an active tenant'
                 else 'tenant deletion' end,
            jsonb_build_object('org_name', v_org.name, 'slug', v_org.slug,
                               'plan_status', v_org.plan_status,
                               'forced', p_force, 'at', now()));
  exception when others then
    -- Never let an audit-schema mismatch block a lawful erasure — but
    -- make the failure visible rather than swallowing it entirely.
    raise warning 'audit_log insert FAILED (deletion continuing): %', sqlerrm;
  end;

  ----------------------------------------------------------------
  -- Break the three FK cycles before deleting. No topological order
  -- exists through these, so any implementation assuming one fails on
  -- real data:
  --   customers <-> rate_cards
  --   claims <-> complaints
  --   orders <-> quotations <-> customer_surveys <-> lr_register
  --           <-> eway_bills <-> insurance_policies
  -- All 15 columns below were verified nullable on 18 Aug 2026, so this
  -- needs no schema change.
  --
  -- Deliberately NOT using session_replication_role = 'replica' or
  -- deferred constraints: those disable integrity checking wholesale, so
  -- a bug here becomes silent corruption instead of a loud failure.
  ----------------------------------------------------------------
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

  ----------------------------------------------------------------
  -- Ordered delete.
  ----------------------------------------------------------------
  foreach v_tbl in array v_order loop
    execute format('delete from public.%I where org_id = $1', v_tbl) using p_org_id;
    get diagnostics v_n = row_count;
    if v_n > 0 then
      table_name := v_tbl; rows_affected := v_n; v_total := v_total + v_n;
      return next;
    end if;
  end loop;

  -- invite_codes is NOT org-scoped (no org_id column) and is on the keep
  -- list by Arun's instruction, 18 Aug 2026: the code is his ISSUANCE
  -- record — which IPAMTOA member it went to and whether it was used —
  -- which is his data, not the tenant's. Null the dangling reference,
  -- keep the row.
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

  table_name := 'TOTAL'; rows_affected := v_total; return next;
  table_name := '-- Auth users and Storage still remain. The Edge Function '
                'removes those next — until it does, the email address is '
                'still in auth.users.';
  rows_affected := 0; return next;
end;
$fn$;

-- Service-role only. A vendor or staff JWT (role `authenticated`) cannot
-- reach this at all, which is why p_actor cannot be spoofed by anyone who
-- isn't already service_role — i.e. the Edge Function, which verified a
-- real JWT before calling.
revoke all on function public.delete_org(uuid, uuid, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.delete_org(uuid, uuid, boolean, boolean)
  to service_role;

comment on function public.delete_org(uuid, uuid, boolean, boolean) is
  'Deletes one tenant''s public-schema rows in dependency order, or '
  '(default) reports what would be deleted. Call ONLY via the '
  'admin-delete-org Edge Function: it verifies the caller''s JWT against '
  'platform_admins and passes the verified uuid as p_actor. An '
  'is_platform_admin() check cannot work here — under service_role '
  'auth.uid() is NULL. Does NOT touch auth.users or Storage. '
  'See NG-SCOPE-delete-org.md.';

commit;

-- ============================================================
-- After running this, do NOT call it from the SQL editor — an editor
-- session runs as `postgres`, which can execute it, but you would be
-- hand-supplying p_actor with no JWT verification behind it. Deploy
-- admin-delete-org and dry-run through that instead; it is the only path
-- where the platform-admin check means anything.
-- ============================================================
