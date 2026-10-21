-- ============================================================
-- mark_lead_lost() — one transaction for a status change and the reason
-- that explains it. Item 5.3 ("lost requiring a confirm dialog + optional
-- reason") made atomic.
--
-- 15 Sept 2026. Handed over unrun. Independent of the day's other
-- migrations; run in any order.
--
-- ------------------------------------------------------------
-- WHAT IS WRONG TODAY: two writes, no transaction, and a guard that
-- throws the second one away on purpose.
-- ------------------------------------------------------------
-- lead_detail_page_widget.dart's _confirmMarkLost does:
--
--     await _setLeadStatus(kLeadStatusLost, force: true);   -- write 1
--     if (!mounted || _canonicalStatus != kLeadStatusLost) return;
--     try {
--       await SupaFlow.client.from('quote_outcomes').insert({...});  -- write 2
--     } catch (_) {
--       // "The status change is the important part and already landed;
--       //  failing to record the outcome shouldn't surface as an error."
--     }
--
-- Three defects, one root cause:
--   1. NOT ATOMIC. Write 1 can land and write 2 not. The lead then reads
--      `lost` with no reason, and the dialog never reappears — because
--      it only opens from a chip the lead no longer shows.
--   2. The `!mounted` guard DISCARDS THE REASON DELIBERATELY. Navigate
--      away in the half-second between the two calls and the vendor's
--      typed reason is dropped by design.
--   3. The blanket `catch (_)` swallows a genuine failure, and its own
--      comment reasons backwards about which half matters. **The status
--      is one word the vendor can see and set again. The reason, the
--      competitor and their price cannot be reconstructed by anyone** —
--      recovering them means phoning a customer who has already gone
--      elsewhere. `quote_outcomes` exists precisely to hold the half
--      that is being discarded.
--   Same shape as quick_payment_section's blanket catch, which this
--   project already records as "the worse half".
--
-- ------------------------------------------------------------
-- COUNTED LIVE, 15 Sept 2026 — not estimated
-- ------------------------------------------------------------
--   leads                      11 rows: confirmed 7, follow_up 2,
--                              quoted 1, new 1
--   leads with status 'lost'   0
--   quote_outcomes             0 rows
--   leads that HAVE an order   7 of 11
--
-- So this path has never run end to end, and `price_gap_pct` has never
-- been populated by anything — the Dart insert stops at `recorded_by`.
--
-- The CHECK constraint already carries the full six-value enum
-- ('new','follow_up','survey_done','quoted','confirmed','lost'), so
-- item 5.1's "migrate/backfill if names differ" has nothing to do: the
-- database and lib/backend/lead_status.dart already agree.
--
-- ------------------------------------------------------------
-- DESIGN
-- ------------------------------------------------------------
-- SECURITY INVOKER (the default — stated here because it is a choice).
-- `leads` carries org_isolation AND a RESTRICTIVE branch_isolation
-- policy; `quote_outcomes` is org-scoped. Running as the CALLER means
-- both apply for free and correctly. A SECURITY DEFINER version would
-- have to re-implement org and branch scoping by hand, which is the
-- fail-open guard class that cost this project a day — see
-- 20260915_set_staff_pin_fail_open.sql. Same reasoning as
-- next_doc_number/next_lr_number, which are deliberately not DEFINER.
--
-- IDEMPOTENT. Nothing enforces one outcome per lead — quote_outcomes
-- has only a PK, no unique index on lead_id or quote_id (checked). So a
-- double tap, or a retry after a timeout where the write actually
-- landed, would otherwise file the same loss twice and double-count it
-- in any "why are we losing deals" report. A second call returns the
-- existing row and writes nothing.
--
-- WARNS, NEVER BLOCKS, when the lead already has an order. 7 of 11
-- leads do. A lead can genuinely be lost after an order exists (the job
-- was cancelled and went elsewhere), so refusing would block a real
-- case; but overwriting `confirmed` silently is how a lead with a live
-- order comes to read `lost` with nobody noticing. The function returns
-- `had_order` and `previous_status` and lets the UI say so — the same
-- posture as _generateInvoice warning about a missing Rule 46 address
-- rather than refusing to issue.
--
-- price_gap_pct is computed HERE and only here, so it has exactly one
-- writer. Dart must not also send it.
-- ============================================================

begin;

set local search_path = public, pg_catalog;

-- ------------------------------------------------------------
-- PREFLIGHT
-- ------------------------------------------------------------
-- Discriminating: the function's absence is true before and false
-- after. to_regprocedure (NOT to_regproc) is used because the argument
-- is a full signature — to_regproc returns NULL in every state when
-- handed an argument list, which is the always-fails trap this project
-- recorded on 12 Sept.
do $preflight$
declare
  v_has_fn   boolean;
  v_outcomes integer;
begin
  v_has_fn := to_regprocedure(
    'public.mark_lead_lost(uuid,text,text,text,numeric,text,numeric,text)'
  ) is not null;

  if v_has_fn then
    raise exception
      'PREFLIGHT: mark_lead_lost already exists. Refusing rather than silently '
      'replacing a function whose current behaviour was not established.';
  end if;

  -- The dependencies this function is written against, asserted rather
  -- than assumed. A missing one must RAISE, never skip.
  if to_regclass('public.quote_outcomes') is null then
    raise exception 'PREFLIGHT: public.quote_outcomes does not exist.';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.leads'::regclass
       and conname  = 'leads_status_check'
       and pg_get_constraintdef(oid) like '%''lost''%'
  ) then
    raise exception
      'PREFLIGHT: leads_status_check does not permit ''lost''. The enum this '
      'function writes is not the one the table accepts — reconcile first.';
  end if;

  select count(*) into v_outcomes from public.quote_outcomes;
  raise notice 'PREFLIGHT OK: quote_outcomes has % row(s) before this change.', v_outcomes;
end
$preflight$;

-- ------------------------------------------------------------
-- THE FUNCTION
-- ------------------------------------------------------------
create function public.mark_lead_lost(
  p_lead_id         uuid,
  p_reason_code     text    default null,
  p_reason_note     text    default null,
  p_competitor_name text    default null,
  p_competitor_price numeric default null,
  p_quote_id        text    default null,
  p_our_price       numeric default null,
  p_recorded_by     text    default null
)
returns jsonb
language plpgsql
-- SECURITY INVOKER is the default and is the point: see the header.
set search_path to 'public'
as $function$
declare
  v_prev      text;
  v_had_order boolean;
  v_existing  uuid;
  v_outcome   uuid;
  v_gap       numeric;
begin
  if p_lead_id is null then
    raise exception 'A lead must be chosen before it can be marked lost.'
      using errcode = 'P0001';
  end if;

  -- Validated explicitly rather than left to the CHECK, so the vendor
  -- sees a sentence. extractDbErrorMessage surfaces P0001 only — a raw
  -- 23514 would reach them as Postgres internals.
  if p_reason_code is not null
     and p_reason_code not in ('price','competitor','timing',
                               'service_scope','customer_cancelled','other') then
    raise exception 'Unknown reason code %. Pick one of the listed reasons.', p_reason_code
      using errcode = 'P0001';
  end if;

  -- One statement, and the comparison happens HERE against the CURRENT
  -- row. The Dart path computed "never downgrade" in the client against
  -- a copy of the status read when the page opened, then wrote the
  -- result unconditionally — so a lead someone else had advanced could
  -- be pulled backwards by a guard written to prevent exactly that.
  -- RLS decides whether this caller may see the row at all; a lead in
  -- another org or another branch simply matches nothing.
  select l.status,
         exists (select 1 from public.orders o where o.lead_id = l.id)
    into v_prev, v_had_order
    from public.leads l
   where l.id = p_lead_id
   for update;

  if not found then
    raise exception 'That lead could not be found, or is not yours to edit.'
      using errcode = 'P0001';
  end if;

  -- Idempotence. quote_outcomes has no unique index (only its PK), so
  -- without this a double tap files the same loss twice and inflates
  -- every later count of why deals are lost.
  if v_prev = 'lost' then
    select qo.id into v_existing
      from public.quote_outcomes qo
     where qo.lead_id = p_lead_id and qo.outcome = 'lost'
     order by qo.recorded_at desc
     limit 1;

    if v_existing is not null then
      return jsonb_build_object(
        'ok', true, 'already', true,
        'previous_status', v_prev,
        'had_order', v_had_order,
        'outcome_id', v_existing
      );
    end if;
    -- Already lost but NO outcome row: precisely the state the
    -- non-atomic path leaves behind. Fall through and record the reason
    -- rather than refusing — this is the repair case.
  end if;

  update public.leads
     set status = 'lost'
   where id = p_lead_id;

  -- Single writer for a derived value. Guarded against division by zero
  -- rather than trusting the caller not to send 0.
  if p_competitor_price is not null
     and p_our_price is not null
     and p_our_price <> 0 then
    v_gap := round(((p_our_price - p_competitor_price) / p_our_price) * 100, 2);
  end if;

  insert into public.quote_outcomes (
    org_id, quote_id, lead_id, outcome,
    reason_code, reason_note, competitor_name, competitor_price,
    our_price, price_gap_pct, recorded_by
  )
  select l.org_id, p_quote_id, p_lead_id, 'lost',
         p_reason_code, nullif(btrim(coalesce(p_reason_note, '')), ''),
         nullif(btrim(coalesce(p_competitor_name, '')), ''), p_competitor_price,
         p_our_price, v_gap, nullif(btrim(coalesce(p_recorded_by, '')), '')
    from public.leads l
   where l.id = p_lead_id
  returning id into v_outcome;

  if v_outcome is null then
    -- Cannot happen with the row locked above; raising rather than
    -- returning ok is the difference between a repair and a silent
    -- half-write, which is the whole point of this function.
    raise exception 'The reason could not be recorded, so the lead was not marked lost.'
      using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'ok', true, 'already', false,
    'previous_status', v_prev,
    'had_order', v_had_order,
    'outcome_id', v_outcome
  );
end;
$function$;

revoke execute on function
  public.mark_lead_lost(uuid,text,text,text,numeric,text,numeric,text) from public;
revoke execute on function
  public.mark_lead_lost(uuid,text,text,text,numeric,text,numeric,text) from anon;
grant  execute on function
  public.mark_lead_lost(uuid,text,text,text,numeric,text,numeric,text) to authenticated;

-- ------------------------------------------------------------
-- POSTFLIGHT
-- ------------------------------------------------------------
-- Same transaction, so a failed assertion rolls the function away.
-- Asserts the CONSTRUCT, not a flag: security-invoker and the grants are
-- read from the catalogue, and the shape is proven by calling it.
do $postflight$
declare
  v_oid      oid;
  v_secdef   boolean;
  v_acl      text;
  v_lead     uuid;
  v_res      jsonb;
  v_outcomes integer;
begin
  v_oid := to_regprocedure(
    'public.mark_lead_lost(uuid,text,text,text,numeric,text,numeric,text)');
  if v_oid is null then
    raise exception 'POSTFLIGHT: mark_lead_lost was not created.';
  end if;

  select p.prosecdef, coalesce(array_to_string(p.proacl, ','), '<default>')
    into v_secdef, v_acl
    from pg_proc p where p.oid = v_oid;

  -- SECURITY INVOKER is load-bearing here, not incidental: it is what
  -- makes org and branch RLS apply without this function re-implementing
  -- either. DEFINER would silently widen it.
  if v_secdef then
    raise exception
      'POSTFLIGHT: mark_lead_lost is SECURITY DEFINER. It must run as the caller '
      'so RLS scopes it; a DEFINER version would need hand-written org and branch '
      'checks. Rolling back.';
  end if;

  -- Asked of the CATALOGUE, not of the ACL's printed text. The first
  -- draft of this check was a LIKE over that text and was wrong in BOTH
  -- directions — proven by running it over constructed cases rather than
  -- by re-reading it:
  --   * it RAISED on 'authenticated=X/postgres', a perfectly correct ACL
  --     (always-fails: would refuse a correct migration);
  --   * it did NOT raise on '=X/postgres,...', i.e. PUBLIC actually
  --     holding EXECUTE — the single case it existed to catch
  --     (always-passes: the guard misses its own purpose).
  -- aclexplode is the instrument this project's conventions already name;
  -- grantee 0 is PUBLIC. Verified against live functions whose grants are
  -- known: public_submit_survey -> true, public_submit_survey_impl -> false.
  if exists (
    select 1
      from pg_proc p,
           lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = v_oid
       and a.privilege_type = 'EXECUTE'
       and (a.grantee = 0 or a.grantee = 'anon'::regrole::oid)
  ) then
    raise exception
      'POSTFLIGHT: PUBLIC or anon holds EXECUTE on mark_lead_lost (acl %). This '
      'function edits a vendor''s lead pipeline and must be authenticated-only.', v_acl;
  end if;

  -- BEHAVIOURAL, and rolled back. A catalogue check proves the function
  -- exists; only a call proves it does anything. Probes on a lead that
  -- is NOT already lost, so both halves are exercised.
  select id into v_lead
    from public.leads
   where coalesce(status,'new') <> 'lost'
   order by created_at
   limit 1;

  if v_lead is null then
    raise exception
      'POSTFLIGHT: no non-lost lead exists to probe with. Refusing to report a '
      'pass over an untested function.';
  end if;

  begin
    v_res := public.mark_lead_lost(
      v_lead, 'price', 'ccr postflight probe', null, null, null, null, 'ccr');
    select count(*) into v_outcomes from public.quote_outcomes;
    raise exception 'ccr_probe_rollback';
  exception when others then
    if sqlerrm <> 'ccr_probe_rollback' then
      raise exception 'POSTFLIGHT: probe call failed unexpectedly: %', sqlerrm;
    end if;
  end;

  if coalesce(v_res->>'ok','') <> 'true' then
    raise exception 'POSTFLIGHT: probe did not report ok (%).', v_res::text;
  end if;
  if v_res->>'outcome_id' is null then
    raise exception 'POSTFLIGHT: probe recorded no outcome row (%).', v_res::text;
  end if;
  if v_outcomes <> 1 then
    raise exception
      'POSTFLIGHT: expected exactly 1 quote_outcomes row during the probe, saw %. '
      'The status change and the reason must land together or not at all.', v_outcomes;
  end if;

  raise notice
    'POSTFLIGHT OK: invoker, acl %, probe returned % — status and reason written together, '
    'then rolled back.', v_acl, v_res::text;
end
$postflight$;

commit;
