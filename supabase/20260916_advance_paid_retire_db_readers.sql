-- ============================================================
-- orders.advance_paid, step 1 of 2: take the DATABASE off it.
--
-- 16 Sept 2026. Handed over unrun.
--
-- Rewrites the two functions and the two views that read
-- `orders.advance_paid` so that nothing in Postgres names the column.
-- The column itself is NOT dropped here — that is
-- `20260916_advance_paid_drop_column.sql`, and the ordering matters for
-- a reason spelled out at the bottom of this header.
--
-- ------------------------------------------------------------
-- WHY THE COLUMN GOES (CLAUDE.md, "orders.advance_paid — SETTLED
-- 11 Sept 2026: REPLACE, NOT REVIVE")
-- ------------------------------------------------------------
-- An advance is money received, and money received has exactly one home:
-- payment_entries, summed onto orders.paid_total by
-- trg_sync_order_paid_total. advance_paid is a SECOND money-in source,
-- and two sources for one value drift — which is not a theory here:
--
--   accounts_page_widget.dart did `collections += advancePaid` and never
--   read paid_total, so the Daily Accounts Register reported Rs0
--   collected for the only order that has actually been paid. No error,
--   no empty state: a wrong number that looks like a right one, on the
--   screen an owner reads to decide who to chase.
--
-- ------------------------------------------------------------
-- COUNTED LIVE, 16 Sept 2026 — not estimated
-- ------------------------------------------------------------
--   orders (not deleted)            8
--   advance_paid <> 0               0   (and NULL on 0 — it is
--                                        NOT NULL-defaulted to 0)
--   paid_total  <> 0                1   (sum 37,800)
--   payment_entries (live)          2
--
-- So there is NO DATA MIGRATION. The column carries nothing anywhere.
-- Only its readers have to move.
--
-- ------------------------------------------------------------
-- THE FOUR DATABASE READERS — found by catalogue, not by grep
-- ------------------------------------------------------------
-- A first scan with `ilike '%advance_paid%'` also matched
-- `default_pricing_config()`. It does not contain the column. It
-- contains the LABEL string {"key":"advanceOnQuote","label":"Advance
-- Paid"} — and **`_` in LIKE is a single-character wildcard**, so
-- `advance_paid` matches "Advance Paid", space and all. Verified:
--
--     'Advance Paid' ilike '%advance_paid%'   -> true
--     'Advance Paid' ~* '\yadvance_paid\y'    -> false
--
-- The false positive came from the INSTRUMENT, not from a comment —
-- a neighbouring question ("does this text contain this pattern")
-- answered truthfully and read as the one that mattered ("does this
-- object reference this column"). Every predicate in this file therefore
-- uses the word-boundary regex, which also rejects `x_advance_paid_y`.
-- Comment lines are stripped as well, for the reason the delete_org and
-- customer_surveys.items tombstones record. pg_index, pg_constraint,
-- pg_attrdef and pg_attribute were asked separately: no index, no
-- constraint, no default and no generated column names it.
--
--  1. sync_order_paid_total()  — AFTER INSERT/UPDATE/DELETE trigger on
--     payment_entries. Adds advance_paid into BOTH the 'paid' and the
--     'partial' test, so the column silently participates in every
--     order's payment_status. THIS is why the drop is not a Dart-only
--     change.
--
--  2. can_delete_order(text)   — `(v_paid + v_advance) > 0` blocks a
--     delete. The advance term is redundant: the same function already
--     refuses when a live payment_entries row exists, which is now the
--     only way money can be attached to an order at all.
--
--  3. branch_kpis_view.outstanding — `sum(amount - advance_paid)`, which
--     NEVER SUBTRACTS paid_total. This is the Daily Accounts bug again,
--     on a second surface and in SQL: the one genuinely paid order
--     contributes its full amount to its branch's outstanding today.
--     Fixed here, because the column it reads is going away.
--
--  4. customer_360_view.total_advance — `sum(advance_paid)`, i.e. 0 for
--     every customer, sitting directly beside `total_collected`, which
--     is already `sum(paid_total)` and already correct. The column is
--     removed rather than redefined: redefining it would duplicate its
--     neighbour, and nothing in lib/ reads it (the generated getter
--     `Customer360ViewRow.totalAdvance` has no call site and is deleted
--     in the same change).
--
-- ------------------------------------------------------------
-- WHAT IS DELIBERATELY *NOT* FIXED HERE
-- ------------------------------------------------------------
-- branch_kpis_view keeps `amount` as its revenue base, where
-- dashboard_kpis_view uses `coalesce(nullif(quote_total,0), amount, 0)`
-- plus non-cancelled add-ons. The two views therefore still disagree
-- about outstanding, exactly as CLAUDE.md already records them
-- disagreeing about net profit. Reconciling the BASE is NG-046's job and
-- is a different change from removing a dead money-in column; doing it
-- here would move a branch card's revenue under cover of a cleanup.
-- Only the money-in term moves in this migration.
--
-- ------------------------------------------------------------
-- RUN ORDER, AND THE HAZARD IF IT IS IGNORED
-- ------------------------------------------------------------
--   1. Ship the app build that stops reading and writing the column
--      (this PR's Dart changes).
--   2. Run THIS migration. Safe at any time — it removes readers, and
--      the column still exists, so an older build keeps working.
--   3. Run 20260916_advance_paid_drop_column.sql ONLY once no device is
--      still running an older build.
--
-- Step 3 is the dangerous one and it is dangerous in a direction worth
-- naming: an installed OLDER build sends `'advance_paid': 0.0` in its
-- order-creation INSERT. After the drop that INSERT fails with 42703 and
-- the vendor CANNOT CREATE ORDERS. Same shape as the
-- kServerSideOrderIds outage — a flag flipped ahead of the state it
-- assumed — so the drop migration refuses to run on its own judgement
-- and makes the operator assert it.
-- ============================================================

begin;

set local search_path = public;

-- ------------------------------------------------------------
-- PREFLIGHT — raises, never skips
-- ------------------------------------------------------------
do $preflight$
declare
  v_named  int;
  v_opts   text;
begin
  -- (1) The column must still exist. If it is already gone, this file
  --     has nothing to do and its postflight would pass on a database
  --     somebody else already fixed — "ran and passed" must not be
  --     indistinguishable from "was never needed".
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'orders'
       and column_name = 'advance_paid'
  ) then
    raise exception
      'PREFLIGHT: orders.advance_paid does not exist. This migration '
      'rewrites its readers and must run BEFORE the drop. If the drop '
      'has already run, these objects were rewritten with it and there '
      'is nothing to do here.';
  end if;

  -- (2) All four readers must currently name it. This is the
  --     discriminating half: BEFORE this migration the count is 4,
  --     AFTER it is 0, so the check cannot return the same answer in
  --     both states. Comment lines are stripped, for the reason in the
  --     header.
  select count(*) into v_named from (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('sync_order_paid_total', 'can_delete_order')
        and (select string_agg(l, e'\n')
               from unnest(string_to_array(pg_get_functiondef(p.oid), e'\n')) l
              where btrim(l) not like '--%') ~* '\yadvance_paid\y'
    union all
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('branch_kpis_view', 'customer_360_view')
        and pg_get_viewdef(c.oid) ~* '\yadvance_paid\y'
  ) z;

  if v_named <> 4 then
    raise exception
      'PREFLIGHT: expected all 4 readers to name advance_paid, found %. '
      'Either one was already rewritten, or a reader has been renamed '
      'and this file is out of date. Re-derive the list before running.',
      v_named;
  end if;

  -- (3) Both views must carry security_invoker TODAY, so that if either
  --     loses it below, the loss is attributable to this migration
  --     rather than pre-existing. CLAUDE.md, 11 Sept 2026: a bare
  --     CREATE OR REPLACE VIEW resets reloptions it does not restate,
  --     and losing this is a silent cross-tenant leak.
  foreach v_opts in array array['branch_kpis_view', 'customer_360_view'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_opts
         and 'security_invoker=on' = any (coalesce(c.reloptions, '{}'))
    ) then
      raise exception
        'PREFLIGHT: public.% does not carry security_invoker=on. Fix that '
        'first — replacing it here would bake an owner-rights view in.',
        v_opts;
    end if;
  end loop;

  raise notice 'PREFLIGHT OK: 4 readers named advance_paid, both views invoker.';
end
$preflight$;

-- Capture customer_360_view's ACL before the drop, so the postflight can
-- prove it was restored rather than silently narrowed. DROP + CREATE
-- does not carry grants across; CREATE OR REPLACE cannot remove a
-- column, and a column is exactly what has to go.
create temporary table _c360_acl_before on commit drop as
  select coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') as grantee,
         a.privilege_type
    from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
   where c.oid = 'public.customer_360_view'::regclass;

-- ------------------------------------------------------------
-- 1. sync_order_paid_total() — paid_total IS money-in, alone
-- ------------------------------------------------------------
create or replace function public.sync_order_paid_total()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_order_id text;
  v_paid numeric;
  v_amount numeric;
begin
  v_order_id := coalesce(new.order_id, old.order_id);

  select coalesce(sum(amount), 0) into v_paid
    from payment_entries
   where order_id = v_order_id
     and deleted_at is null;

  select coalesce(amount, 0) into v_amount
    from orders where id = v_order_id;

  -- advance_paid used to be added to v_paid on both branches below.
  -- It was 0 on every order in the database and nothing wrote it after
  -- 16 Sept 2026, so payment_status is unchanged for existing data —
  -- but a second money-in source in the one function that decides
  -- whether a job is PAID is not something to leave lying around.
  update orders set
    paid_total = v_paid,
    payment_status = case
      when v_amount > 0 and v_paid >= v_amount then 'paid'
      when v_paid > 0 then 'partial'
      else 'pending'
    end
  where id = v_order_id;

  return coalesce(new, old);
end
$function$;

-- ------------------------------------------------------------
-- 2. can_delete_order() — the advance term was redundant
-- ------------------------------------------------------------
create or replace function public.can_delete_order(p_order_id text)
returns table(allowed boolean, reason text, alternative text)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_invoice text;
  v_paid numeric;
begin
  -- Column aliases avoid the OUT-parameter ambiguity (42702) that bit
  -- verify_org_pin() live.
  select o.invoice_no, coalesce(o.paid_total, 0)
    into v_invoice, v_paid
  from public.orders o
  where o.id = p_order_id;

  if not found then
    return query select false, 'Order not found'::text, null::text;
    return;
  end if;

  -- GST records must be retained — an invoiced order is never deletable,
  -- and this is checked first so the message names the real blocker when
  -- both apply.
  if v_invoice is not null and length(trim(v_invoice)) > 0 then
    return query select false,
      format('A GST invoice (%s) has been issued. Tax records must be retained.', v_invoice)::text,
      'cancel_order'::text;
    return;
  end if;

  -- paid_total alone. It is maintained from payment_entries by trigger,
  -- and the next test refuses on those rows directly, so an advance term
  -- here could only ever repeat what the row check already says.
  if v_paid > 0 then
    return query select false,
      'Payments have been recorded against this order.'::text,
      'cancel_order'::text;
    return;
  end if;

  if exists (select 1 from public.payment_entries pe
              where pe.order_id = p_order_id
                and pe.deleted_at is null) then
    return query select false,
      'Payment entries exist for this order.'::text,
      'cancel_order'::text;
    return;
  end if;

  return query select true, null::text, null::text;
end;
$function$;

-- ------------------------------------------------------------
-- 3. branch_kpis_view — outstanding now subtracts money received
-- ------------------------------------------------------------
-- CREATE OR REPLACE (not DROP): the column list, order and types are
-- unchanged, only the expression behind `outstanding` moves. The
-- `with (security_invoker = on)` clause is restated because a bare
-- replace DISCARDS reloptions — see the header and CLAUDE.md, 11 Sept.
create or replace view public.branch_kpis_view
  with (security_invoker = on) as
 select (branch || ':'::text) || coalesce(org_id::text, 'null'::text) as id,
    org_id,
    branch,
    coalesce(sum(amount) filter (where date_trunc('month'::text, created_at) = date_trunc('month'::text, now())), 0::numeric) as revenue,
    count(*) filter (where date_trunc('month'::text, created_at) = date_trunc('month'::text, now())) as order_count,
    -- WAS: sum(amount - coalesce(advance_paid, 0)) — which never
    -- subtracted a single rupee anybody had actually paid, because
    -- payments live in payment_entries and reach the order through
    -- paid_total. greatest(..., 0) keeps an over-collected order from
    -- lending negative outstanding to its branch.
    coalesce(sum(greatest(amount - coalesce(paid_total, 0::numeric), 0::numeric))
             filter (where payment_status is distinct from 'paid'::text), 0::numeric) as outstanding,
    coalesce(sum(amount) filter (where date_trunc('month'::text, created_at) = date_trunc('month'::text, now())), 0::numeric) - coalesce(sum(
        case
            when commission_expected then porter_cash_collect * coalesce(commission_pct, 0::numeric) / 100.0
            else 0::numeric
        end) filter (where date_trunc('month'::text, created_at) = date_trunc('month'::text, now())), 0::numeric) as net_profit
   from orders o
  where branch is not null and deleted_at is null
  group by branch, org_id;

-- ------------------------------------------------------------
-- 4. customer_360_view — total_advance removed
-- ------------------------------------------------------------
drop view public.customer_360_view;

create view public.customer_360_view
  with (security_invoker = on) as
 select c.id as customer_id,
    c.org_id,
    c.name,
    c.phone,
    c.customer_type,
    c.company_name,
    c.customer_since,
    count(distinct o.id) as total_orders,
    coalesce(sum(o.amount), 0::numeric) as lifetime_value,
    coalesce(avg(o.amount), 0::numeric) as avg_order_value,
    max(o.created_at) as last_order_at,
    count(distinct l.id) as total_leads,
    count(distinct q.id) as total_quotes,
    coalesce(sum(o.amount), 0::numeric) - coalesce(sum(o.paid_total), 0::numeric) as outstanding_estimate,
    -- total_advance (sum(advance_paid)) removed: 0 for every customer,
    -- and total_collected beside it is already the real figure.
    coalesce(sum(o.paid_total), 0::numeric) as total_collected,
    count(distinct ct.id) filter (where ct.status = 'active'::text) as active_contracts,
    max(a.occurred_at) as last_contact_at
   from customers c
     left join orders o on o.customer_id = c.id and o.deleted_at is null
     left join leads l on l.customer_id = c.id and l.deleted_at is null
     left join quotations q on q.customer_id = c.id
     left join contracts ct on ct.customer_id = c.id and ct.deleted_at is null
     left join activities a on a.customer_id = c.id
  where c.deleted_at is null
  group by c.id, c.org_id, c.name, c.phone, c.customer_type, c.company_name, c.customer_since;

-- GRANT ALL, not an enumerated list. The enumerated version was written
-- first and the ACL dry-run refused it: this server's ACL carries 32
-- entries (4 roles x 8 privileges) including MAINTAIN, which a
-- hand-written list of seven silently omits — so the grant-restore check
-- below would have raised on a correct migration. Naming privileges by
-- hand also dates the file against the next server version that adds
-- one.
grant all privileges on public.customer_360_view
   to anon, authenticated, service_role, postgres;

-- ------------------------------------------------------------
-- POSTFLIGHT — asserts the construct, and exercises the trigger
-- ------------------------------------------------------------
do $postflight$
declare
  v_named        int;
  v_opts         text;
  v_missing      text;
  v_order        text;
  v_org          uuid;
  v_amount       numeric;
  v_status       text;
  v_paid         numeric;
  v_view_out     numeric;
  v_new_expr     numeric;
  v_old_expr     numeric;
  v_probe_branch text;
  v_probe_org    uuid;
begin
  -- (1) No reader names the column any more. The mirror of preflight (2):
  --     4 before, 0 after.
  select count(*) into v_named from (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('sync_order_paid_total', 'can_delete_order')
        and (select string_agg(l, e'\n')
               from unnest(string_to_array(pg_get_functiondef(p.oid), e'\n')) l
              where btrim(l) not like '--%') ~* '\yadvance_paid\y'
    union all
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('branch_kpis_view', 'customer_360_view')
        and pg_get_viewdef(c.oid) ~* '\yadvance_paid\y'
  ) z;
  if v_named <> 0 then
    raise exception 'POSTFLIGHT: % reader(s) still name advance_paid.', v_named;
  end if;

  -- (2) security_invoker survived on BOTH views. This is the assertion
  --     that caught a real loss on 11 Sept 2026 and it is the reason
  --     that day's leak did not ship.
  foreach v_opts in array array['branch_kpis_view', 'customer_360_view'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_opts
         and 'security_invoker=on' = any (coalesce(c.reloptions, '{}'))
    ) then
      raise exception
        'POSTFLIGHT: security_invoker was LOST on public.% — every tenant''s '
        'rows would be readable. Rolling back.', v_opts;
    end if;
  end loop;

  -- (3) customer_360_view's grants came back exactly. A DROP + CREATE
  --     that quietly narrowed them would look like a working view and
  --     break a role nobody tested.
  select string_agg(grantee || ':' || privilege_type, ', ' order by grantee, privilege_type)
    into v_missing
    from (
      select grantee, privilege_type from _c360_acl_before
      except
      select coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC'), a.privilege_type
        from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
       where c.oid = 'public.customer_360_view'::regclass
    ) z;
  if v_missing is not null then
    raise exception
      'POSTFLIGHT: customer_360_view lost grant(s) across the recreate: %.',
      v_missing;
  end if;

  -- (4) total_advance is gone and total_collected is still there. Both
  --     halves, because a recreate that dropped the wrong column would
  --     pass the first on its own.
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='customer_360_view'
                and column_name='total_advance') then
    raise exception 'POSTFLIGHT: customer_360_view.total_advance still exists.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='customer_360_view'
                    and column_name='total_collected') then
    raise exception
      'POSTFLIGHT: customer_360_view.total_collected is MISSING — the '
      'recreate dropped the real figure instead of the dead one.';
  end if;

  -- (5) can_delete_order still SECURITY DEFINER and still answers. A
  --     replace that flipped it to INVOKER would leave it unable to read
  --     orders for a caller RLS keeps out, and nothing else would say so.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='can_delete_order'
                    and p.prosecdef) then
    raise exception 'POSTFLIGHT: can_delete_order is no longer SECURITY DEFINER.';
  end if;

  -- (6+7) BEHAVIOURAL, and both checks share one probe because neither
  --     can discriminate on this database's data as it stands.
  --
  --     THIS WAS FOUND BY RUNNING THE PREDICATE, NOT BY RE-READING IT.
  --     The first version of (7) picked "a branch-carrying order with
  --     paid_total > 0" and asserted the view's outstanding DIFFERED
  --     from the old advance_paid figure. Counted live: exactly one such
  --     order exists and its payment_status is 'paid', so the
  --     `payment_status is distinct from 'paid'` filter drops it from
  --     BOTH expressions — they are identical, and the check would have
  --     RAISED ON A CORRECT MIGRATION. The always-fails mirror, in a
  --     guard written to enforce the other half.
  --
  --     So the discriminating state is CONSTRUCTED rather than looked
  --     for: one payment entry makes an order partly-paid, which is the
  --     only state in which the old and new formulas can disagree. The
  --     whole probe is then rolled back.
  select o.id, o.org_id, coalesce(o.amount, 0), o.branch
    into v_order, v_org, v_amount, v_probe_branch
    from orders o
   where o.deleted_at is null
     and coalesce(o.amount, 0) > 0
     and o.branch is not null
     and not exists (select 1 from payment_entries pe
                      where pe.order_id = o.id and pe.deleted_at is null)
   order by o.created_at
   limit 1;

  if v_order is null then
    -- Refuse rather than report success on an unexercised rewrite. This
    -- is the hole set_staff_pin's own postflight had: with no qualifying
    -- row the probe would have "passed" having tested nothing.
    raise exception
      'POSTFLIGHT: found no order with amount > 0, a branch, and no payment '
      'entries, so neither the trigger nor the view could be exercised. '
      'Refusing rather than reporting success on an untested migration.';
  end if;
  v_probe_org := v_org;   -- same row; named separately for the view lookup

  begin
    -- --- half payment: payment_status must become 'partial' ---
    insert into payment_entries (org_id, order_id, amount, mode, note)
    values (v_org, v_order, round(v_amount / 2, 2), 'cash', 'POSTFLIGHT PROBE');

    select payment_status, coalesce(paid_total, 0) into v_status, v_paid
      from orders where id = v_order;
    if v_status <> 'partial' then
      raise exception 'PROBE: half payment gave payment_status=% (paid_total=%), expected partial.',
        v_status, v_paid;
    end if;

    -- --- with a partly-paid order in it, the branch's outstanding can
    --     now tell the two formulas apart. advance_paid still exists at
    --     this point in the transaction, so the OLD expression is the
    --     real one, not a reconstruction of it. ---
    select coalesce(sum(greatest(coalesce(amount,0) - coalesce(paid_total,0), 0))
                    filter (where payment_status is distinct from 'paid'), 0),
           coalesce(sum(coalesce(amount,0) - coalesce(advance_paid,0))
                    filter (where payment_status is distinct from 'paid'), 0)
      into v_new_expr, v_old_expr
      from orders
     where deleted_at is null and branch = v_probe_branch
       and org_id is not distinct from v_probe_org;

    select outstanding into v_view_out
      from branch_kpis_view
     where branch = v_probe_branch and org_id is not distinct from v_probe_org;

    if v_view_out is distinct from v_new_expr then
      raise exception
        'PROBE: branch % outstanding reads % but the new expression is %.',
        v_probe_branch, v_view_out, v_new_expr;
    end if;
    if v_view_out = v_old_expr then
      raise exception
        'PROBE: branch % outstanding (%) is identical to the OLD '
        'advance_paid figure while a partly-paid order sits in that '
        'branch. The view was not actually rewritten.',
        v_probe_branch, v_view_out;
    end if;

    -- --- top up: payment_status must become 'paid'. Without this the
    --     probe would pass against a function that hardcoded 'partial'. ---
    insert into payment_entries (org_id, order_id, amount, mode, note)
    values (v_org, v_order, v_amount, 'cash', 'POSTFLIGHT PROBE 2');

    select payment_status, coalesce(paid_total, 0) into v_status, v_paid
      from orders where id = v_order;
    if v_status <> 'paid' then
      raise exception 'PROBE: full payment gave payment_status=% (paid_total=%), expected paid.',
        v_status, v_paid;
    end if;

    raise notice
      'PROBE: order % — partial then paid; branch % outstanding % -> % '
      'against the old formula.',
      v_order, v_probe_branch, v_old_expr, v_new_expr;

    raise exception 'PROBE_ROLLBACK_OK';
  exception
    when others then
      if sqlerrm <> 'PROBE_ROLLBACK_OK' then
        raise exception 'POSTFLIGHT: probe failed — %', sqlerrm;
      end if;
  end;

  raise notice
    'POSTFLIGHT OK: 0 readers name advance_paid, both views invoker, grants '
    'restored, trigger proved partial AND paid, branch outstanding proved '
    'to differ from the old formula — probe rolled back.';
end
$postflight$;

commit;
