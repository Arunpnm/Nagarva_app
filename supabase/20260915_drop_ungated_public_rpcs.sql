-- =====================================================================
-- Drop the four anon-direct, ungated public RPCs (15 Sept 2026)
--
-- HAND-RUN. Read this header before executing.
--
-- WHAT THIS DROPS, and why wrapping them was rejected
-- ---------------------------------------------------------------------
-- Two complete pairs, both predating the wrapper/_impl gate that the
-- 8 Sept suspension work built:
--
--   survey     get_survey_by_token(text)
--              submit_survey(text,text,text,text,text,date,jsonb,text)
--   quotation  get_quotation_by_token(text)
--              accept_quotation(text,text)
--
-- All four are SECURITY DEFINER with `anon` holding DIRECT EXECUTE and
-- no wrapper in front. Adding a wrapper does NOT fix them, because what
-- is wrong lives in the function BODIES, not in the missing gate:
--
--   * get_survey_by_token returns `customer_phone`. The designed
--     replacement (public_get_survey -> _impl) deliberately withholds it
--     -- its own comment reads "No org_id, no lead_id, no phone." The
--     old function also returns the survey's uuid, which the new one
--     never exposes.
--   * get_survey_by_token checks NOTHING: no token-length floor, no
--     status check, no expires_at check, no serviceability gate. So an
--     EXPIRED or ALREADY-SUBMITTED token still yields customer name +
--     phone + org name, permanently. public_get_survey answers
--     'expired' / 'already_submitted' and returns no data at all.
--   * submit_survey has no jsonb_typeof(p_rooms)='array' check, no
--     150-element cap, no token-length floor and NO EXPIRY CHECK (only
--     status='pending'). It also writes customer_name, customer_phone,
--     from_address, to_address and move_date -- so any holder of a token
--     can OVERWRITE THE CUSTOMER'S IDENTITY FIELDS. public_submit_survey
--     _impl touches none of those.
--   * accept_quotation is a WRITE that anon can call with no gate of any
--     kind.
--
-- submit_survey is also the direct cause of one table holding two jsonb
-- shapes: because it never validated element shape, the Flutter
-- SurveyPage was able to write a free-text {room, items} row alongside
-- the four per-item {cat,item,sub,cft,qty} rows the live page writes.
--
-- HOW WE KNOW submit_survey WAS THE WRITER -- a discriminating marker
-- ---------------------------------------------------------------------
-- public_submit_survey_impl sets `used_at`; submit_survey does not.
-- That is a marker holding a DIFFERENT value in each state, so reading
-- it is informative -- as opposed to a marker present in both states,
-- which returns the same answer either way and is therefore not a check
-- at all (CLAUDE.md, sixth roll-call instance). Across all five
-- submitted rows the correlation is exact:
--
--   035758c7  submitted 2 Sep 01:35  used_at NULL  free-text shape
--   e56a0f53  submitted 9 Sep        used_at set   per-item shape
--   ffa9c0a7  submitted 9 Sep        used_at set   per-item shape
--   81fe446e  submitted 9 Sep        used_at set   per-item shape
--   98ba603d  submitted 14 Sep       used_at set   per-item shape
--
-- One use, on 2 Sept, never since. Recorded here because it is the rule
-- working rather than being quoted.
--
-- WHY THIS IS SAFE
-- ---------------------------------------------------------------------
--   * No database object calls any of the four. Asserted in preflight.
--   * The only clients were two Flutter pages that no deployed artifact
--     can reach: link.nagarva.in serves public_site/ (which calls the
--     public_* pair), and AndroidManifest.xml registers NO https intent
--     filter, so the APK never intercepts a survey or quote link.
--   * BOTH pages are DELETED in this same commit -- survey_page_widget
--     .dart and quote_page_widget.dart, routes and exports included.
--     Deleting SurveyPage removes the only writer of the free-text shape,
--     so that shape cannot return. Neither page could function without
--     these RPCs, and a page that cannot load while still sitting in the
--     tree reads as alive.
--
-- /quote IS TAKEN NOW, DELIBERATELY
-- ---------------------------------------------------------------------
-- kQuoteLinkHosted is false and /quote has never been served by
-- anything, so there is nothing to leave behind. Dropping the quotation
-- pair now is cheaper than remembering it when /quote is finally built
-- -- and when it is built, it must be REBUILT THROUGH THE WRAPPER
-- PATTERN (public_get_quotation / public_accept_quotation, each calling
-- a locked _impl), not by restoring these. Restoring these would
-- reintroduce an anon-callable write with no gate.
--
-- NO CLIENT IS LEFT CALLING A DROPPED FUNCTION
-- ---------------------------------------------------------------------
-- nav.dart predicted that dropping these would make the Flutter pages
-- "break silently". Deleting both pages is what makes that impossible,
-- rather than merely loud. Git holds the layouts for the /quote rebuild:
--   git show 3199ea1:lib/quote_page/quote_page_widget.dart
--   git show 3199ea1:lib/survey_page/survey_page_widget.dart
--
-- ROLLBACK
--   There is none, by intent. These are not to be recreated; the
--   replacement for survey already exists and the replacement for
--   quotation is to be written through the wrapper pattern. Their bodies
--   remain in git history (supabase/20260725_survey_quote_flow.sql and
--   supabase/20260909_consolidate_survey_tables.sql) if ever needed for
--   reference.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Asserts, never skips: a guard that lets this pass without
-- doing its job would hand back a clean result over a no-op.
-- ---------------------------------------------------------------------
do $$
declare
  v_targets text[] := array[
    'public.get_survey_by_token(text)',
    'public.submit_survey(text,text,text,text,text,date,jsonb,text)',
    'public.get_quotation_by_token(text)',
    'public.accept_quotation(text,text)'
  ];
  v_sig      text;
  v_missing  text[] := '{}';
  v_dependent record;
  v_deps     text[] := '{}';
begin
  -- 1. Every target must EXIST. If one is already gone, this migration
  --    is not the thing that removed it and the operator needs to know
  --    why before the rest runs.
  foreach v_sig in array v_targets loop
    if to_regprocedure(v_sig) is null then
      v_missing := v_missing || v_sig;
    end if;
  end loop;

  if array_length(v_missing, 1) is not null then
    raise exception
      'PREFLIGHT: expected function(s) not present: %. Nothing dropped. Establish who removed them before re-running.',
      array_to_string(v_missing, ', ');
  end if;

  -- 2. No database object may CALL any of the four.
  --    The pattern requires a non-identifier char (or line start) before
  --    the name, optionally allowing a `public.` qualifier. That matters:
  --    a bare substring search matches public_submit_survey against
  --    submit_survey and reports a caller that does not exist. Same
  --    family as the delete_org tombstone -- a text test answering a
  --    question nobody asked.
  --    Self-exclusion compares OIDs, never a rebuilt signature string:
  --    on this server pg_get_function_identity_arguments() returns
  --    argument NAMES as well as types ('p_token text'), so feeding its
  --    output back to to_regprocedure() raises 42601 and would fail this
  --    migration while it was entirely correct.
  for v_dependent in
    select n.nspname || '.' || p.proname as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prokind = 'f'
      and n.nspname not in ('pg_catalog', 'information_schema')
      and p.oid <> all (array(select to_regprocedure(s)::oid from unnest(v_targets) s))
      and pg_get_functiondef(p.oid) ~*
            '(^|[^a-zA-Z0-9_])(public\.)?(get_survey_by_token|submit_survey|get_quotation_by_token|accept_quotation)\s*\('
  loop
    v_deps := v_deps || v_dependent.sig;
  end loop;

  if array_length(v_deps, 1) is not null then
    raise exception
      'PREFLIGHT: % database object(s) still call a drop target: %. Resolve before dropping.',
      array_length(v_deps, 1), array_to_string(v_deps, ', ');
  end if;

  -- 3. No view, default, trigger or other catalogue entry may depend on
  --    them either. pg_depend answers this; a body scan does not.
  if exists (
    select 1
    from pg_depend d
    where d.refclassid = 'pg_proc'::regclass   -- oids are unique only
                                               -- WITHIN a catalogue; without
                                               -- this, a matching oid in
                                               -- another catalogue reads as a
                                               -- dependency on our function.
      and d.refobjid in (
            select to_regprocedure(s)::oid from unnest(v_targets) s
          )
      and d.deptype <> 'i'
      and d.classid <> 'pg_proc'::regclass
  ) then
    raise exception
      'PREFLIGHT: a catalogue dependency on a drop target exists (pg_depend). Inspect before dropping.';
  end if;

  raise notice 'PREFLIGHT OK: 4 targets present, no callers, no catalogue dependencies.';
end;
$$;

-- ---------------------------------------------------------------------
-- DROP. No IF EXISTS: preflight has already proven each one is present,
-- so IF EXISTS could only mask a target that vanished between the two
-- statements.
-- ---------------------------------------------------------------------
drop function public.get_survey_by_token(text);
drop function public.submit_survey(text, text, text, text, text, date, jsonb, text);
drop function public.get_quotation_by_token(text);
drop function public.accept_quotation(text, text);

-- ---------------------------------------------------------------------
-- POSTFLIGHT. Inside the same transaction, so a failed assertion rolls
-- the whole thing back and partial application is impossible.
-- ---------------------------------------------------------------------
do $$
declare
  v_targets text[] := array[
    'public.get_survey_by_token(text)',
    'public.submit_survey(text,text,text,text,text,date,jsonb,text)',
    'public.get_quotation_by_token(text)',
    'public.accept_quotation(text,text)'
  ];
  v_sig       text;
  v_survivors text[] := '{}';

  -- The seven correctly-gated pairs. A migration that drops functions is
  -- exactly the right moment to prove the survivors were not caught by a
  -- wildcard, so this asserts their GRANT SHAPE, not merely that they
  -- still exist.
  v_wrappers text[] := array[
    'public.public_get_survey(text)',
    'public.public_submit_survey(text,jsonb,text)',
    'public.public_get_signature_request(text)',
    'public.public_submit_signature(text,text,text)',
    'public.public_submit_complaint(text,text,text)',
    'public.public_submit_review(text,integer,text)',
    'public.public_get_order_documents(text)'
  ];
  v_impls text[] := array[
    'public.public_get_survey_impl(text)',
    'public.public_submit_survey_impl(text,jsonb,text)',
    'public.public_get_signature_request_impl(text)',
    'public.public_submit_signature_impl(text,text,text)',
    'public.public_submit_complaint_impl(text,text,text)',
    'public.public_submit_review_impl(text,integer,text)',
    'public.public_get_order_documents_impl(text)'
  ];
  v_oid       oid;
  v_anon      boolean;
  v_public    boolean;
  v_bad       text[] := '{}';
begin
  -- 1. All four are gone.
  foreach v_sig in array v_targets loop
    if to_regprocedure(v_sig) is not null then
      v_survivors := v_survivors || v_sig;
    end if;
  end loop;

  if array_length(v_survivors, 1) is not null then
    raise exception 'POSTFLIGHT: drop target(s) still present: %.',
      array_to_string(v_survivors, ', ');
  end if;

  -- 2. Every wrapper still EXISTS and is still anon-callable. If a
  --    wildcard had caught one, the public pages go dark.
  foreach v_sig in array v_wrappers loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      v_bad := v_bad || (v_sig || ' [MISSING]');
      continue;
    end if;
    select bool_or(a.grantee = 'anon'::regrole)
      into v_anon
      from pg_proc p,
           lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = v_oid and a.privilege_type = 'EXECUTE';
    if not coalesce(v_anon, false) then
      v_bad := v_bad || (v_sig || ' [anon lost EXECUTE]');
    end if;
  end loop;

  -- 3. Every _impl still exists and is still LOCKED -- neither anon nor
  --    PUBLIC may execute it. coalesce(proacl, acldefault(...)) is
  --    load-bearing: a NULL proacl means default privileges, under which
  --    PUBLIC DOES hold EXECUTE. Reading NULL as "no grants" would call
  --    an exposed function locked.
  foreach v_sig in array v_impls loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      v_bad := v_bad || (v_sig || ' [MISSING]');
      continue;
    end if;
    select bool_or(a.grantee = 'anon'::regrole),
           bool_or(a.grantee = 0)
      into v_anon, v_public
      from pg_proc p,
           lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid = v_oid and a.privilege_type = 'EXECUTE';
    if coalesce(v_anon, false) then
      v_bad := v_bad || (v_sig || ' [anon GAINED EXECUTE]');
    end if;
    if coalesce(v_public, false) then
      v_bad := v_bad || (v_sig || ' [PUBLIC holds EXECUTE]');
    end if;
  end loop;

  if array_length(v_bad, 1) is not null then
    raise exception 'POSTFLIGHT: gated pair grant shape changed: %.',
      array_to_string(v_bad, ', ');
  end if;

  raise notice 'POSTFLIGHT OK: 4 dropped; 7 wrappers anon-callable; 7 impls locked to postgres/service_role.';
end;
$$;

commit;
