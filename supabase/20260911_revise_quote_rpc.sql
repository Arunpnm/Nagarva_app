-- =====================================================================
-- 20260911_revise_quote_rpc.sql                                 PART 1
--
-- revise_quote() -- one action, one version row, enforced in the
-- database rather than by UI discipline.
--
-- THE REQUIREMENT THIS EXISTS TO MAKE STRUCTURAL
-- An order-day change to items AND price is ONE revision, not two
-- edits. There is no code path here that writes items without writing
-- price, because there is no path that writes either alone: the RPC
-- takes the WHOLE snapshot or nothing. An inline item editor that saves
-- independently is therefore not merely discouraged, it has no endpoint
-- to call. Two records of one event that can disagree is the pattern
-- this project has removed four times; this is the version of the rule
-- that cannot be forgotten.
--
-- SECURITY INVOKER, deliberately -- matching next_doc_number
-- (prosecdef = false). The caller may only revise a quote their own
-- session can see: quotations is RLS'd org_isolation, so a foreign-org
-- id simply is not found and the function refuses. A DEFINER version
-- would bypass RLS and force us to re-implement the org check by hand,
-- which is how those checks get forgotten.
--
-- LAZY VERSION-1 BACKFILL, and it is not optional.
-- nagarva_migration_004 shipped a backfill that would have written a
-- version 1 row per existing quote. It ran when zero quotations
-- existed, so it wrote nothing -- quote_versions has 0 rows today and
-- every live quote has no history at all. If the first revision only
-- wrote the NEW state, the state the customer was originally sent would
-- be unrecoverable: history would begin at version 2 with nothing to
-- diff against. So the first revision of any quote snapshots the
-- CURRENT row as version 1 first, then writes the revision as version
-- 2. Both rows, one transaction.
--
-- changed_fields AND change_summary ARE COMPUTED HERE, never accepted
-- from the caller. A client-supplied diff is a second account of the
-- same event that can disagree with the values it describes.
--
-- created_by IS A uid, NOT A NAME. auth.uid()::text, server-derived.
-- The name cannot be resolved server-side -- all five staff rows carry
-- auth_user_id = NULL -- and a client-supplied name would be forgeable,
-- which is worthless in the dispute a version history exists to settle.
-- Same position as audit_row(). Populating staff.auth_user_id at PIN
-- login resolves both, retroactively.
--
-- THE ONE JUDGEMENT CALL, FLAGGED FOR REVIEW
-- "Reason is MANDATORY once the order is confirmed." There is no
-- 'confirmed' order status in this product -- live statuses are booked,
-- closed and delivered (counted 11 Sept 2026), and _convertQuoteToOrder
-- creates orders at 'booked'. So "confirmed" is read here as THE QUOTE
-- HAS BECOME A JOB: a non-cancelled, non-deleted order references it.
-- That is the moment after which a price change needs explaining.
-- quotations.status = 'accepted' is set at the same instant by the same
-- code, so either test gives the same answer today; the order is used
-- because the brief said order. One line, one place -- see
-- v_reason_required below -- if you want it moved.
--
-- APPLIED 11 Sept 2026, and verified against the database rather than
-- from the editor's success message: revise_quote exists with
-- prosecdef = false, proacl = {postgres,authenticated,service_role}
-- (no anon, no PUBLIC), quote_versions carries RLS with org_isolation,
-- and the postflight's probe left 0 version rows behind.
--
-- THE FIRST RUN FAILED, on 42P01, in this file's own postflight -- a
-- comma-join mixed with an explicit JOIN, so the alias was out of
-- scope for its ON clause. It aborted in one transaction and left
-- nothing behind. Fixed with cross join lateral, and the grant check
-- was strengthened while it was open: see the NULL proacl note there.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT
-- ---------------------------------------------------------------------
do $$
begin
  if to_regclass('public.quote_versions') is null then
    raise exception 'public.quote_versions is missing (migration 004).';
  end if;
  if to_regclass('public.quotations') is null then
    raise exception 'public.quotations is missing.';
  end if;

  -- The unique index this function relies on to make a concurrent
  -- double-revision impossible. Asserted by SHAPE, not by name alone.
  if not exists (
    select 1 from pg_index ix join pg_class i on i.oid = ix.indexrelid
     where ix.indrelid = 'public.quote_versions'::regclass
       and ix.indisunique
       and pg_get_indexdef(i.oid) like '%(quote_id, version)%'
  ) then
    raise exception
      'no unique index on quote_versions(quote_id, version). Two concurrent '
      'revisions could then write the same version number.';
  end if;

  -- 'revised' must already be legal, or every successful revision would
  -- fail on the status CHECK at the last statement.
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.quotations'::regclass
       and conname  = 'quotations_status_check'
       and pg_get_constraintdef(oid) like '%''revised''%'
  ) then
    raise exception
      'quotations_status_check does not admit ''revised''. Run '
      '20260911_status_vocabulary.sql first.';
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
    status          = 'revised',
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
    'reason_required', v_reason_required
  );
end;
$function$;

comment on function public.revise_quote(text, jsonb, text) is
  'Revises a quotation as ONE action: one quote_versions row, one '
  'quotations UPDATE, one transaction. Takes the complete snapshot, never '
  'a partial patch, so an item change and a price change cannot be '
  'recorded separately. Computes changed_fields and change_summary '
  'server-side. Backfills version 1 from the current row on first use. '
  'Reason mandatory once a live order references the quote.';

revoke all on function public.revise_quote(text, jsonb, text) from public;
revoke all on function public.revise_quote(text, jsonb, text) from anon;
grant execute on function public.revise_quote(text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------
-- POSTFLIGHT -- structural, then a real revision, then unwound.
-- ---------------------------------------------------------------------
do $$
declare
  v_secdef  boolean;
  v_qid     text;
  v_before  numeric;
  v_res     jsonb;
  v_v1      jsonb;
  v_v2      jsonb;
  v_n       int;
  v_ok      boolean := false;
begin
  select p.prosecdef into v_secdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and p.proname='revise_quote';
  if v_secdef is null then
    raise exception 'revise_quote() was not created.';
  end if;
  if v_secdef then
    raise exception
      'revise_quote() is SECURITY DEFINER; it must be INVOKER so RLS decides '
      'which quotes a caller may revise.';
  end if;

  -- Grants. Two distinct hazards, and the first run of this file got the
  -- SQL wrong on both counts -- worth spelling out so it is not rewritten
  -- back into either mistake.
  --
  -- (a) A comma-join cannot be mixed with an explicit JOIN like this:
  --       from pg_proc p, aclexplode(p.proacl) a join pg_namespace n on ...
  --     The explicit JOIN binds tighter, so `p` is not in scope for its
  --     ON clause and Postgres raises 42P01. Use LATERAL, which makes the
  --     dependency on `p` explicit.
  --
  -- (b) A NULL proacl is NOT safe for a FUNCTION. Unlike a table, a
  --     function with no explicit ACL grants EXECUTE to PUBLIC by
  --     default -- so "no rows in aclexplode" would have PASSED a
  --     function that anyone can call. It is checked first, separately.
  declare
    v_acl aclitem[];
  begin
    select p.proacl into v_acl
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'revise_quote';

    if v_acl is null then
      raise exception
        'revise_quote() has no explicit ACL, which for a FUNCTION means '
        'EXECUTE is granted to PUBLIC by default. The REVOKEs above did '
        'not take effect.';
    end if;

    if exists (
      select 1
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        cross join lateral aclexplode(p.proacl) a
       where n.nspname = 'public'
         and p.proname = 'revise_quote'
         and (a.grantee = 0 or a.grantee = 'anon'::regrole)
    ) then
      raise exception 'revise_quote() is executable by anon or PUBLIC.';
    end if;
  end;

  ------------------------------------------------------------------
  -- BEHAVIOURAL: revise a real draft quote, assert both version rows,
  -- then unwind. Chosen on a quote with NO order against it, so the
  -- mandatory-reason branch is not triggered by the probe.
  ------------------------------------------------------------------
  select q.id, coalesce(q.total, 0) into v_qid, v_before
    from quotations q
   where q.deleted_at is null
     and not exists (select 1 from orders o
                      where o.quotation_id = q.id and o.deleted_at is null)
   order by q.created_at
   limit 1;

  if v_qid is null then
    raise notice
      'no order-free quotation exists; the behavioural probe was SKIPPED. '
      'Exercise revise_quote() from the app before relying on it.';
    return;
  end if;

  begin
    v_res := public.revise_quote(
      v_qid,
      jsonb_build_object('total', v_before + 1000, 'subtotal', v_before + 1000),
      'Postflight probe'
    );

    if (v_res ->> 'ok') <> 'true' then
      raise exception 'probe: revise_quote did not return ok. %', v_res;
    end if;
    if (v_res ->> 'version')::int <> 2 then
      raise exception
        'probe: expected version 2 on a first revision, got %.',
        v_res ->> 'version';
    end if;

    select count(*) into v_n from quote_versions where quote_id = v_qid;
    if v_n <> 2 then
      raise exception
        'probe: expected 2 version rows (the backfilled original plus the '
        'revision), found %.', v_n;
    end if;

    select snapshot into v_v1 from quote_versions
      where quote_id = v_qid and version = 1;
    select snapshot into v_v2 from quote_versions
      where quote_id = v_qid and version = 2;
    if v_v1 is null or v_v2 is null then
      raise exception 'probe: a version snapshot is missing.';
    end if;
    if coalesce((v_v1 ->> 'total')::numeric, -1) <> v_before then
      raise exception
        'probe: version 1 did not capture the ORIGINAL total (% vs %).',
        v_v1 ->> 'total', v_before;
    end if;
    if not ('total' = any(
          (select changed_fields from quote_versions
            where quote_id = v_qid and version = 2))) then
      raise exception 'probe: changed_fields did not name total.';
    end if;
    if (select status from quotations where id = v_qid) <> 'revised' then
      raise exception 'probe: the quotation status was not set to revised.';
    end if;

    raise exception 'REVISE_PROBE_OK';
  exception
    when others then
      if sqlerrm <> 'REVISE_PROBE_OK' then
        raise;
      end if;
      v_ok := true;
  end;

  if not v_ok then
    raise exception 'probe did not run to completion.';
  end if;

  if (select count(*) from quote_versions) <> 0 then
    raise exception
      'probe left % quote_versions row(s); it must leave none.',
      (select count(*) from quote_versions);
  end if;

  raise notice
    'revise_quote() installed and PROVEN by a real revision (version 1 '
    'backfilled, version 2 written, diff correct, status revised), unwound.';
end $$;

commit;

-- =====================================================================
-- WHAT IS NOT HERE
-- ---------------------------------------------------------------------
--  * The version history PANEL. It reads quote_versions and NEVER
--    audit_log -- a manager reads the history, the audit log is what
--    gets opened when someone disputes it. Dart, own commit.
--  * A caller. Nothing invokes revise_quote() yet; the quote builder is
--    still insert-only. Wiring it is the Dart half.
--  * Branding in the snapshot. An old version re-renders with TODAY's
--    letterhead, because the PDF pulls org profile and terms at render
--    time. The panel should say "figures as sent", not claim the
--    document is byte-identical. Snapshotting branding per version was
--    judged a lot of duplication for a rare case -- revisit only if a
--    vendor actually changes letterhead mid-negotiation.
--
-- ROLLBACK
--   drop function if exists public.revise_quote(text, jsonb, text);
-- Version rows already written are left alone.
-- =====================================================================
