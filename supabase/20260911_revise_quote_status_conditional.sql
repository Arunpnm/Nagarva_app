-- =====================================================================
-- 20260911_revise_quote_status_conditional.sql
--
-- ONE BEHAVIOURAL CHANGE to revise_quote(): the quotation's status is
-- now set CONDITIONALLY.
--
--   no order against the quote  -> status becomes 'revised'
--   a live order exists         -> status is LEFT AS IT IS
--
-- WHY. status describes the quote's life with the CUSTOMER, and that
-- life ends when the quote becomes a job. Before an order exists,
-- 'revised' is exactly right: the customer has not agreed to v2. After
-- one exists, overwriting 'accepted' with 'revised' destroyed the one
-- fact the column was carrying, and NOTHING COULD PUT IT BACK -- the
-- only writer of 'accepted' lives inside _convertQuoteToOrder, which
-- cannot run twice because the order it creates already exists. A quote
-- revised on job day was therefore left permanently 'revised', with a
-- live order against it and no path out.
--
-- WHAT CARRIES THE AGREEMENT INSTEAD. The mandatory reason. On job day
-- the customer is present; if they do not agree, you do not revise. The
-- version row records what changed, by whom and why, which is a better
-- account of consent than a status flag ever was.
--
-- WHY NOT A RE-ACCEPT ACTION. It was the other candidate and it is
-- worse twice over: it fixes the symptom while leaving a step a manager
-- can forget -- and a forgotten step lands in the identical dead end --
-- and it would need the accept flip lifted out of _convertQuoteToOrder
-- to gain a second call site, widening the single write path that was
-- deliberately kept to one.
--
-- REVERSIBILITY IS THE CLINCHER. Adding an explicit re-accept later is
-- additive. Unwinding a status that has already been overwritten is
-- not: the information is gone.
--
-- THE CONDITION IS NOT A NEW TEST. v_reason_required already means
-- "a live, non-cancelled, non-deleted order references this quote", and
-- it is reused verbatim. Two tests of one condition is the duplication
-- this codebase keeps removing.
--
-- The returned jsonb gains 'status' -- the resulting value -- so a
-- caller never has to infer which branch it took.
--
-- Everything else is byte-identical to 20260911_revise_quote_rpc.sql.
-- CREATE OR REPLACE FUNCTION cannot patch one line, so the whole body
-- is restated; this file supersedes that one for the function only.
--
-- APPLIED 12 Sept 2026, and CONFIRMED BY BEHAVIOUR rather than by the
-- editor's success message. An independent probe afterwards revised a
-- real accepted quote with a live order and read the status back:
--   accepted -> accepted, version 2, returned jsonb carries 'status'.
-- Rolled back; quote_versions 0, statuses still accepted:4 / draft:2,
-- all four accepted_at intact, zero audit rows written.
--
-- THE FIRST ATTEMPT FAILED, and the cause was this file's own
-- preflight: `to_regproc` handed an ARGUMENT LIST returns NULL whether
-- or not the function exists, so the guard was NULL in every state and
-- refused a correct migration. Fixed to `to_regprocedure`. It looked
-- like a stale SQL-editor catalogue snapshot and was not -- a fresh
-- tab would have failed identically.
--
-- BRANCH 1 IS STILL UNPROVEN BY BEHAVIOUR, and that is not a defect in
-- the migration -- there is no order-free quotation to exercise it on
-- (all six live quotes carry a live order). The postflight says so in
-- a NOTICE rather than pretending otherwise. The branch that CHANGED
-- is proven; the branch that did not rests on reading the case
-- expression until someone revises a quote with no order against it,
-- which is the ordinary path and will exercise it the first time.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
-- ---------------------------------------------------------------------
do $$
begin
  -- to_regPROCEDURE, not to_regPROC. `to_regproc` takes a function NAME
  -- and returns NULL when handed an argument list, so
  -- to_regproc('public.revise_quote(text,jsonb,text)') is NULL whether
  -- or not the function exists. This preflight used it and refused a
  -- correct migration on 12 Sept 2026, reporting that a function which
  -- was demonstrably present did not exist.
  --
  -- It is the sixth-instance failure in CLAUDE.md's roll-call, in its
  -- mirror form: a check that returns the same result in BOTH states.
  -- Always-passes lets a broken migration through; always-fails blocks
  -- a correct one. Neither discriminates, and neither is a check.
  if to_regprocedure('public.revise_quote(text,jsonb,text)') is null then
    raise exception
      'revise_quote(text,jsonb,text) does not exist -- run '
      '20260911_revise_quote_rpc.sql first. This migration REPLACES that '
      'function; it does not create it from nothing.';
  end if;

  -- The behaviour being replaced must actually be the one described
  -- above. If the live body no longer carries the unconditional
  -- assignment, something else has edited this function since, and
  -- restating the whole body would silently discard that edit.
  if position('status          = ''revised''' in
              pg_get_functiondef('public.revise_quote(text,jsonb,text)'::regprocedure)) = 0
  then
    raise exception
      'revise_quote() does not carry the unconditional status assignment '
      'this migration expects to replace. Someone has edited it since '
      '20260911_revise_quote_rpc.sql -- read the live definition before '
      'running this, or that edit is lost.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- THE FUNCTION
-- ---------------------------------------------------------------------
create or replace function public.revise_quote(
  p_quote_id text,
  p_snapshot jsonb,
  p_reason   text default null
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_q               quotations%rowtype;
  v_prev_snapshot   jsonb;
  v_prev_version    int;
  v_next_version    int;
  v_changed         text[];
  v_summary         text;
  v_reason_required boolean;
  v_actor           text;
  v_old_total       numeric;
  v_new_total       numeric;
begin
  ------------------------------------------------------------------
  -- Input
  ------------------------------------------------------------------
  if p_quote_id is null or btrim(p_quote_id) = '' then
    raise exception 'revise_quote: p_quote_id is required.'
      using errcode = 'P0001';
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    raise exception
      'revise_quote: p_snapshot must be a JSON object holding the complete '
      'revised quote, not a partial patch.'
      using errcode = 'P0001';
  end if;

  ------------------------------------------------------------------
  -- Lock the quote. RLS decides visibility: a quote belonging to
  -- another org is simply not found, and the message says nothing
  -- about whether the id exists elsewhere.
  ------------------------------------------------------------------
  select * into v_q
    from quotations
   where id = p_quote_id
     and deleted_at is null
   for update;

  if not found then
    raise exception
      'revise_quote: quotation % was not found, or is not yours to revise.',
      p_quote_id
      using errcode = 'P0001';
  end if;

  ------------------------------------------------------------------
  -- Reason: optional before the quote becomes a job, mandatory after.
  -- Pre-confirmation revision is ordinary negotiation and forcing a
  -- reason every time is friction nobody thanks you for; after, it is
  -- the case that actually wants explaining.
  ------------------------------------------------------------------
  v_reason_required := exists (
    select 1 from orders o
     where o.quotation_id = v_q.id
       and o.deleted_at is null
       and coalesce(o.status, '') <> 'cancelled'
  );

  if v_reason_required and (p_reason is null or btrim(p_reason) = '') then
    raise exception
      'This quote already has an order against it, so a revision needs a '
      'reason. Say what changed and why.'
      using errcode = 'P0001';
  end if;

  ------------------------------------------------------------------
  -- LAZY VERSION-1 BACKFILL.
  -- If this quote has no history, capture the CURRENT row as version 1
  -- before writing the revision. Without it the state the customer was
  -- originally sent is lost the first time anyone revises.
  ------------------------------------------------------------------
  select qv.snapshot, qv.version
    into v_prev_snapshot, v_prev_version
    from quote_versions qv
   where qv.quote_id = v_q.id
   order by qv.version desc
   limit 1;

  if v_prev_version is null then
    v_prev_snapshot := to_jsonb(v_q);
    insert into quote_versions
      (org_id, quote_id, version, snapshot, change_summary,
       changed_fields, total_amount, created_by)
    values
      (v_q.org_id, v_q.id, 1, v_prev_snapshot,
       'Original quote, captured when it was first revised.',
       '{}'::text[], coalesce(v_q.total, 0), null);
    v_prev_version := 1;
  end if;

  v_next_version := v_prev_version + 1;

  ------------------------------------------------------------------
  -- Diff, computed here. Keys present in either snapshot whose values
  -- differ. Volatile bookkeeping columns are excluded so a revision
  -- does not report itself as a change.
  ------------------------------------------------------------------
  select array_agg(k order by k) into v_changed
    from (
      select coalesce(n.key, o.key) as k
        from jsonb_each(p_snapshot) n
        full outer join jsonb_each(v_prev_snapshot) o on o.key = n.key
       where n.value is distinct from o.value
         and coalesce(n.key, o.key) not in
             ('version','updated_at','created_at','status')
    ) d;

  v_old_total := coalesce((v_prev_snapshot ->> 'total')::numeric, 0);
  v_new_total := coalesce((p_snapshot      ->> 'total')::numeric, v_q.total, 0);

  v_summary := case
    when v_old_total is distinct from v_new_total then
      'Total ' || trim(to_char(v_old_total, 'FM999999999.00')) ||
      ' -> '   || trim(to_char(v_new_total, 'FM999999999.00')) ||
      case when coalesce(array_length(v_changed, 1), 0) > 1
           then format(' (%s fields changed)', array_length(v_changed, 1))
           else '' end
    when coalesce(array_length(v_changed, 1), 0) > 0 then
      format('%s field(s) changed, total unchanged', array_length(v_changed, 1))
    else 'No values changed'
  end;

  begin
    v_actor := auth.uid()::text;
  exception when others then
    v_actor := null;      -- no JWT (running as postgres, e.g. a migration)
  end;

  ------------------------------------------------------------------
  -- The version row. quote_versions_uniq(quote_id, version) is what
  -- makes a concurrent double-revision impossible: the loser of the
  -- race fails here rather than silently overwriting.
  ------------------------------------------------------------------
  insert into quote_versions
    (org_id, quote_id, version, snapshot, change_summary,
     changed_fields, total_amount, created_by)
  values
    (v_q.org_id, v_q.id, v_next_version, p_snapshot,
     case when p_reason is null or btrim(p_reason) = ''
          then v_summary
          else v_summary || ' -- ' || btrim(p_reason) end,
     coalesce(v_changed, '{}'::text[]), v_new_total, v_actor);

  ------------------------------------------------------------------
  -- Apply the revision to the quotation itself.
  --
  -- An EXPLICIT column list, never dynamic SQL over the snapshot's
  -- keys: a caller must not be able to reach a column by naming it.
  -- coalesce(..., existing) means an absent key leaves the column
  -- alone rather than nulling it.
  --
  -- Customer identity (customer, phone, addresses) is deliberately NOT
  -- revised here -- correcting a name is not a quote revision and
  -- should not consume a version number.
  ------------------------------------------------------------------
  update quotations set
    items           = coalesce(p_snapshot -> 'items',    items),
    charges         = coalesce(p_snapshot -> 'charges',  charges),
    subtotal        = coalesce((p_snapshot ->> 'subtotal')::numeric,   subtotal),
    gst_pct         = coalesce((p_snapshot ->> 'gst_pct')::numeric,    gst_pct),
    gst_amount      = coalesce((p_snapshot ->> 'gst_amount')::numeric, gst_amount),
    total           = coalesce((p_snapshot ->> 'total')::numeric,      total),
    total_cft       = coalesce((p_snapshot ->> 'total_cft')::numeric,  total_cft),
    chosen_package  = coalesce(p_snapshot ->> 'chosen_package',  chosen_package),
    chosen_vehicle  = coalesce(p_snapshot ->> 'chosen_vehicle',  chosen_vehicle),
    chosen_crew     = coalesce((p_snapshot ->> 'chosen_crew')::int, chosen_crew),
    -- STATUS IS CONDITIONAL -- see this migration's header.
    -- v_reason_required already means 'a live order references this
    -- quote'. Reused rather than re-tested, so the rule that makes the
    -- reason mandatory and the rule that protects the status cannot
    -- drift apart.
    status          = case when v_reason_required then quotations.status
                           else 'revised' end,
    version         = v_next_version
  where id = v_q.id;

  -- The audit trigger on quotations fires on that UPDATE by itself.
  -- Nothing is written to audit_log here: a second, hand-written audit
  -- row for the same event is exactly the duplication the trigger was
  -- installed to remove.

  return jsonb_build_object(
    'ok',             true,
    'quote_id',       v_q.id,
    'version',        v_next_version,
    'changed_fields', coalesce(v_changed, '{}'::text[]),
    'change_summary', v_summary,
    'reason_required', v_reason_required,
    -- The resulting status, so a caller never has to infer which
    -- branch the case expression took.
    'status',         (select q2.status from quotations q2 where q2.id = v_q.id)
  );
end;
$function$;

-- Grants restated. CREATE OR REPLACE FUNCTION does preserve the ACL,
-- but restating is harmless where a missing grant is a live outage --
-- the same reasoning as always writing `with (security_invoker = on)`
-- into a view statement rather than trusting it to survive.
revoke all on function public.revise_quote(text, jsonb, text) from public;
revoke all on function public.revise_quote(text, jsonb, text) from anon;
grant execute on function public.revise_quote(text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------
-- POSTFLIGHT
--
-- BEHAVIOURAL, and it asserts BOTH branches. Reading the body for a
-- `case` would prove the text changed, not that the rule fires -- and
-- the failure this file exists to prevent is a status being
-- overwritten, which only a real write can rule out.
--
--   Branch 2 (the one that changed): a quote WITH a live order is
--     revised and must keep its status.
--   Branch 1 (unchanged): a quote with NO order must end 'revised' --
--     asserted so a later edit to the case expression cannot quietly
--     invert it.
--
-- Both run against real rows and are unwound.
-- ---------------------------------------------------------------------
do $$
declare
  v_free_id     text;
  v_held_id     text;
  v_held_status text;
  v_after       text;
  v_res         jsonb;
begin
  select q.id into v_free_id
    from quotations q
   where q.deleted_at is null
     and not exists (select 1 from orders o
                      where o.quotation_id = q.id
                        and o.deleted_at is null
                        and coalesce(o.status, '') <> 'cancelled')
   limit 1;

  select q.id, q.status into v_held_id, v_held_status
    from quotations q
   where q.deleted_at is null
     and exists (select 1 from orders o
                  where o.quotation_id = q.id
                    and o.deleted_at is null
                    and coalesce(o.status, '') <> 'cancelled')
   limit 1;

  begin
    if v_held_id is null then
      raise exception
        'no quotation with a live order exists, so the branch this '
        'migration changes CANNOT BE EXERCISED. Refusing rather than '
        'reporting a pass that proved nothing.';
    end if;

    -- Branch 2. Reason supplied because it is mandatory here.
    v_res := public.revise_quote(
               v_held_id,
               jsonb_build_object('total', 123456),
               'postflight probe -- asserting the status is preserved');

    select status into v_after from quotations where id = v_held_id;

    if v_after is distinct from v_held_status then
      raise exception
        'a quote with a live order changed status from % to % during a '
        'revision. That is the overwrite this migration exists to stop.',
        v_held_status, v_after;
    end if;
    if (v_res ->> 'status') is distinct from v_held_status then
      raise exception
        'the returned status (%) disagrees with the stored status (%).',
        v_res ->> 'status', v_held_status;
    end if;
    if (v_res ->> 'reason_required') <> 'true' then
      raise exception
        'reason_required was not true for a quote with a live order, so '
        'the condition the status now shares is not firing.';
    end if;

    -- Branch 1.
    if v_free_id is not null then
      perform public.revise_quote(v_free_id,
                                  jsonb_build_object('total', 654321),
                                  null);
      select status into v_after from quotations where id = v_free_id;
      if v_after <> 'revised' then
        raise exception
          'a quote with no order against it ended as % rather than '
          'revised.', v_after;
      end if;
    else
      raise notice
        'no order-free quotation exists, so branch 1 was not exercised. '
        'The branch that CHANGED (branch 2) was.';
    end if;

    raise exception 'STATUS_PROBE_OK';
  exception
    when others then
      if sqlerrm <> 'STATUS_PROBE_OK' then raise; end if;
  end;

  raise notice
    'revise_quote: status preserved when a live order exists, set to '
    'revised when none does. Both probes unwound.';
end $$;

commit;

-- =====================================================================
-- ROLLBACK
--   Re-run 20260911_revise_quote_rpc.sql, which restores the
--   unconditional assignment. Version rows written in the meantime are
--   left alone -- they are the record, not the mechanism.
-- =====================================================================
