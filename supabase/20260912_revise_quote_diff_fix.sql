-- =====================================================================
-- 20260912_revise_quote_diff_fix.sql
--
-- revise_quote() reported 67 CHANGED FIELDS for a revision that changed
-- four. Found by running the thing, not by reading it: the first real
-- revision through the UI (Meena Iyer TEST, 12 Sept 2026, freight
-- 40,000 -> 44,000) wrote
--
--   change_summary: "Total 47200.00 -> 51920.00 (67 fields changed)"
--   changed_fields: accepted_at, accepted_by_name, access_notes,
--                   access_restrictions, advance_amount, advance_pct,
--                   approval_status, approved_at, approved_by,
--                   balance_amount, charges, customer, ... (67)
--
-- and the vendor saw "(67 fields changed)" on the lead.
--
-- THE CAUSE: THE TWO SNAPSHOTS ARE DIFFERENT SHAPES, BY DESIGN.
--   version 1  = to_jsonb(quotations) -- the whole row, 76 keys,
--                captured for recoverability by the lazy backfill
--   a revision = the 10 priced keys the RPC is allowed to write
--
-- The diff was a FULL OUTER JOIN over both key sets, so all 66 columns
-- present only in v1 fell out as "changed". Most of them are columns
-- revise_quote CANNOT WRITE -- its UPDATE has an explicit column list
-- that excludes customer, phone and the addresses deliberately. The
-- function was reporting changes to fields it is structurally incapable
-- of changing.
--
-- THE FIX: compare only the keys the caller SUBMITTED. Those are
-- exactly the keys that can have changed, so the comparison finally
-- asks the question the column is named after. A key absent from the
-- previous snapshot reads as changed, which is correct -- it had no
-- prior value.
--
-- WHY VERSION 1 KEEPS THE WHOLE ROW. Trimming v1 to ten keys would make
-- both sides the same shape and is the wrong fix: v1 exists so the
-- state the customer was originally sent is recoverable, and ten priced
-- fields are not that state. The asymmetry is deliberate; the diff was
-- what failed to account for it.
--
-- WHY THIS MATTERS BEYOND TIDINESS. changed_fields is the audit-grade
-- record of what moved in a quote, and it is what a dispute would be
-- settled on. A list of 67 fields, 63 of them untouched and some
-- unwritable, is not a weaker record than a correct one -- it is an
-- actively misleading one, and it buries the four that matter.
--
-- Everything else is byte-identical to
-- 20260911_revise_quote_status_conditional.sql. CREATE OR REPLACE
-- FUNCTION cannot patch one block, so the whole body is restated; this
-- file supersedes that one for the function only.
--
-- NOT RUN. File only.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
--
-- Note to_regPROCEDURE. `to_regproc` handed an argument list returns
-- NULL whether or not the function exists -- a check that gives the
-- same answer in both states, which refused a correct migration on
-- 12 Sept 2026. See CLAUDE.md's sixth-instance entry.
-- ---------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.revise_quote(text,jsonb,text)') is null then
    raise exception
      'revise_quote(text,jsonb,text) does not exist -- run '
      '20260911_revise_quote_rpc.sql and then '
      '20260911_revise_quote_status_conditional.sql first.';
  end if;

  -- The conditional-status behaviour must already be present, or this
  -- file would silently revert it while fixing the diff.
  if position('case when v_reason_required then quotations.status' in
              pg_get_functiondef('public.revise_quote(text,jsonb,text)'::regprocedure)) = 0
  then
    raise exception
      'revise_quote() does not carry the conditional status assignment. '
      'Run 20260911_revise_quote_status_conditional.sql first -- this '
      'migration restates the whole body and would otherwise undo it.';
  end if;

  -- And the broken diff must still be the one being replaced.
  if position('full outer join jsonb_each(v_prev_snapshot)' in
              pg_get_functiondef('public.revise_quote(text,jsonb,text)'::regprocedure)) = 0
  then
    raise exception
      'revise_quote() does not carry the full-outer-join diff this '
      'migration expects to replace. Someone has edited it since -- read '
      'the live definition before running this, or that edit is lost.';
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
  -- DIFF OVER THE SUBMITTED KEYS ONLY -- never a full outer join against
  -- the previous snapshot. The two snapshots are DIFFERENT SHAPES by
  -- design: version 1 is `to_jsonb(quotations)`, the whole 76-column row
  -- captured for recoverability, while a revision carries the 10 priced
  -- keys the RPC is allowed to write. A full outer join counted every
  -- column present only in v1 as "changed", so the first real revision
  -- on 12 Sept 2026 reported 67 changed fields -- including accepted_at,
  -- customer and access_notes, none of which this function can even
  -- write -- when four had actually changed.
  --
  -- Only the submitted keys CAN have changed, so only they are compared.
  -- A key missing from the previous snapshot reads as changed, which is
  -- right: it had no prior value.
  select array_agg(n.key order by n.key) into v_changed
    from jsonb_each(p_snapshot) n
   where n.key not in ('version','updated_at','created_at','status')
     and n.value is distinct from (v_prev_snapshot -> n.key);

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

revoke all on function public.revise_quote(text, jsonb, text) from public;
revoke all on function public.revise_quote(text, jsonb, text) from anon;
grant execute on function public.revise_quote(text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------
-- POSTFLIGHT
--
-- BEHAVIOURAL. Revises a real quote by changing ONE field and requires
-- the diff to name exactly that field -- not a count, the field. A
-- count would pass on the wrong set of the right size.
--
-- It uses the quote revised through the UI on 12 Sept if it is still
-- there, else any quote, and unwinds either way.
-- ---------------------------------------------------------------------
do $$
declare
  v_id       text;
  v_changed  text[];
  v_summary  text;
  v_before   numeric;
begin
  select q.id, coalesce(q.total, 0) into v_id, v_before
    from quotations q
   where q.deleted_at is null
   order by q.version desc nulls last, q.created_at desc
   limit 1;

  if v_id is null then
    raise exception 'no quotation exists, so the diff cannot be exercised.';
  end if;

  begin
    -- Change exactly one submitted key: total. Everything else in the
    -- snapshot is sent at its CURRENT value, so a correct diff must
    -- report `total` and nothing else.
    perform public.revise_quote(
      v_id,
      (select jsonb_build_object(
                'items',          q.items,
                'charges',        q.charges,
                'subtotal',       q.subtotal,
                'gst_pct',        q.gst_pct,
                'gst_amount',     q.gst_amount,
                'total',          v_before + 1,
                'total_cft',      q.total_cft,
                'chosen_package', q.chosen_package,
                'chosen_vehicle', q.chosen_vehicle,
                'chosen_crew',    q.chosen_crew)
         from quotations q where q.id = v_id),
      'postflight probe -- asserting the diff names one field');

    select qv.changed_fields, qv.change_summary
      into v_changed, v_summary
      from quote_versions qv
     where qv.quote_id = v_id
     order by qv.version desc
     limit 1;

    if v_changed is distinct from array['total']::text[] then
      raise exception
        'the diff reported % instead of {total}. Summary: %',
        coalesce(v_changed::text, 'NULL'), v_summary;
    end if;

    raise exception 'DIFF_PROBE_OK';
  exception
    when others then
      if sqlerrm <> 'DIFF_PROBE_OK' then raise; end if;
  end;

  raise notice
    'revise_quote: a one-field revision now reports exactly that field. '
    'Probe unwound.';
end $$;

commit;

-- =====================================================================
-- NOTE ON THE ROW ALREADY WRITTEN
--   quote_versions v2 for the Meena Iyer TEST quote carries the 67-field
--   list this migration stops producing. It is left alone: it is a true
--   record of what the function did at the time, and rewriting history
--   to make a past version look like it was produced by today's code is
--   exactly what an audit trail must not do. The summary is wrong about
--   the WORLD but right about the FUNCTION, which is the more useful
--   thing for it to be honest about.
--
-- ROLLBACK
--   Re-run 20260911_revise_quote_status_conditional.sql, which restores
--   the full-outer-join diff along with everything else.
-- =====================================================================
