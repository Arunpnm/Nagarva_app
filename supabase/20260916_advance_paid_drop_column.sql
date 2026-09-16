-- ============================================================
-- orders.advance_paid, step 2 of 2: drop the column.
--
-- 16 Sept 2026. Handed over unrun.
--
-- RUN THIS LAST, AND NOT ON THE SAME DAY AS ANYTHING ELSE.
--
--   1. Ship the app build that stops reading and writing the column.
--   2. Run 20260916_advance_paid_retire_db_readers.sql.
--   3. Wait until no device is still running an older build.
--   4. Run this.
--
-- ------------------------------------------------------------
-- WHY STEP 3 IS NOT A FORMALITY
-- ------------------------------------------------------------
-- An installed OLDER build sends `'advance_paid': 0.0` in its
-- order-creation INSERT. The moment this column is gone that INSERT
-- fails with 42703 (undefined column) and the vendor CANNOT CREATE
-- ORDERS — the core workflow, on a phone that is not being updated
-- while somebody stands in a customer's flat.
--
-- That is the kServerSideOrderIds outage exactly: a change applied ahead
-- of the state it assumed, with no fallback by design. No query can tell
-- you which builds are installed, so this migration does not pretend to
-- check it. It makes the operator assert it, out loud, and refuses
-- otherwise — see the GUC in the preflight.
--
-- ------------------------------------------------------------
-- NO DATA IS LOST, AND THAT IS COUNTED RATHER THAN ASSUMED
-- ------------------------------------------------------------
-- 16 Sept 2026: advance_paid was 0 on all 8 live orders, NOT NULL on
-- none of them, and paid_total was non-zero on one. The preflight below
-- re-counts it AT RUN TIME rather than trusting this paragraph, because
-- a count in a comment is a claim with a date on it: if any row carries
-- a non-zero advance by the time this runs, some build is still writing
-- the column and dropping it would destroy money data.
-- ============================================================

begin;

set local search_path = public;

do $preflight$
declare
  v_named    int;
  v_nonzero  int;
  v_confirm  text;
begin
  -- (1) The column must exist. If it is already gone this file has
  --     nothing to do, and a postflight that "passes" on somebody else's
  --     work is the always-passes shape.
  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='orders'
       and column_name='advance_paid'
  ) then
    raise exception
      'PREFLIGHT: orders.advance_paid is already gone. Nothing to drop.';
  end if;

  -- (2) Nothing in the database may still read it. This is step 2's
  --     dependency on step 1, and it RAISES rather than skipping: a
  --     guard that lets a script pass without doing its job is worse
  --     than no guard.
  select count(*) into v_named from (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname='public' and p.prokind='f'
        and (select string_agg(l, e'\n')
               from unnest(string_to_array(pg_get_functiondef(p.oid), e'\n')) l
              where btrim(l) not like '--%') ~* '\yadvance_paid\y'
    union all
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname='public' and c.relkind in ('v','m')
        and pg_get_viewdef(c.oid) ~* '\yadvance_paid\y'
    union all
    select 1 from pg_policies
      where coalesce(qual,'')||coalesce(with_check,'') ~* '\yadvance_paid\y'
    union all
    select 1 from pg_constraint where pg_get_constraintdef(oid) ~* '\yadvance_paid\y'
    union all
    select 1 from pg_index ix join pg_class i on i.oid = ix.indexrelid
      where pg_get_indexdef(i.oid) ~* '\yadvance_paid\y'
  ) z;

  if v_named > 0 then
    raise exception
      'PREFLIGHT: % database object(s) still reference advance_paid. Run '
      'supabase/20260916_advance_paid_retire_db_readers.sql first — it '
      'rewrites sync_order_paid_total(), can_delete_order(), '
      'branch_kpis_view and customer_360_view.', v_named;
  end if;

  -- (3) No row may carry a non-zero advance. If one does, a build
  --     somewhere is still writing this column and the drop would throw
  --     money away silently.
  select count(*) into v_nonzero
    from orders where coalesce(advance_paid, 0) <> 0;
  if v_nonzero > 0 then
    raise exception
      'PREFLIGHT: % order(s) carry a non-zero advance_paid. Something is '
      'still writing it. Move those amounts into payment_entries before '
      'dropping the column — this migration will not discard money.',
      v_nonzero;
  end if;

  -- (4) The thing SQL cannot check: that no old build is still in the
  --     field. The operator asserts it by running
  --        set local nagarva.old_builds_retired = 'yes';
  --     in the same statement batch, immediately above this file.
  --     Deliberately not defaulted to a pass — an unanswered question
  --     must not read as a yes.
  v_confirm := coalesce(current_setting('nagarva.old_builds_retired', true), '');
  if lower(v_confirm) <> 'yes' then
    raise exception
      'PREFLIGHT: not confirmed that every installed build has stopped '
      'writing advance_paid. An older APK sends it in its order INSERT '
      'and will get 42703 — order creation breaks for that device. When '
      'that is genuinely true, run this file with '
      '"set local nagarva.old_builds_retired = ''yes'';" ahead of it.';
  end if;

  raise notice
    'PREFLIGHT OK: column present, 0 db readers, 0 non-zero rows, old '
    'builds confirmed retired.';
end
$preflight$;

alter table public.orders drop column advance_paid;

do $postflight$
declare
  v_order   text;
  v_org     uuid;
  v_amount  numeric;
  v_status  text;
  v_paid    numeric;
begin
  -- (1) Gone.
  if exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='orders'
       and column_name='advance_paid'
  ) then
    raise exception 'POSTFLIGHT: advance_paid still exists.';
  end if;

  -- (2) paid_total survived. A drop that took the neighbouring money
  --     column would otherwise pass check (1) perfectly.
  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='orders'
       and column_name='paid_total'
  ) then
    raise exception
      'POSTFLIGHT: orders.paid_total is MISSING — the wrong column was '
      'dropped.';
  end if;

  -- (3) BEHAVIOURAL: the payment trigger still runs against a table that
  --     no longer has the column, in both directions. A catalogue check
  --     cannot tell you that sync_order_paid_total() still executes;
  --     only calling it can.
  select o.id, o.org_id, coalesce(o.amount, 0)
    into v_order, v_org, v_amount
    from orders o
   where o.deleted_at is null and coalesce(o.amount,0) > 0
     and not exists (select 1 from payment_entries pe
                      where pe.order_id = o.id and pe.deleted_at is null)
   order by o.created_at limit 1;

  if v_order is null then
    raise exception
      'POSTFLIGHT: no order with amount > 0 and no payments, so the trigger '
      'could not be exercised after the drop. Refusing rather than '
      'reporting success on an untested change.';
  end if;

  begin
    insert into payment_entries (org_id, order_id, amount, mode, note)
    values (v_org, v_order, round(v_amount/2, 2), 'cash', 'POSTFLIGHT PROBE');
    select payment_status, coalesce(paid_total,0) into v_status, v_paid
      from orders where id = v_order;
    if v_status <> 'partial' then
      raise exception 'PROBE: half payment gave %, expected partial (paid_total=%).',
        v_status, v_paid;
    end if;

    insert into payment_entries (org_id, order_id, amount, mode, note)
    values (v_org, v_order, v_amount, 'cash', 'POSTFLIGHT PROBE 2');
    select payment_status into v_status from orders where id = v_order;
    if v_status <> 'paid' then
      raise exception 'PROBE: full payment gave %, expected paid.', v_status;
    end if;

    raise exception 'PROBE_ROLLBACK_OK';
  exception
    when others then
      if sqlerrm <> 'PROBE_ROLLBACK_OK' then
        raise exception 'POSTFLIGHT: trigger probe failed after the drop — %',
          sqlerrm;
      end if;
  end;

  raise notice
    'POSTFLIGHT OK: advance_paid dropped, paid_total intact, payment '
    'trigger proved partial AND paid after the drop — probe rolled back.';
end
$postflight$;

commit;
