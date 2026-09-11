-- =====================================================================
-- 20260911_reason_code_check.sql              PART 2, the held-back half
--
-- Pins quote_outcomes.reason_code to the six codes agreed on 11 Sept.
--
--   price | competitor | timing | service_scope | customer_cancelled
--   | other
--
-- ORDERING MATTERS -- RUN THIS ONLY AFTER A BUILD CARRYING THE TRIM.
-- 20260911_status_vocabulary.sql deliberately did NOT add this
-- constraint: the live Mark Lost dialog still offered eight codes, and a
-- CHECK landing first would have failed two of its options at the exact
-- moment a vendor picked one. The Dart trim is commit e3b2bce. If the
-- app you are running predates it, close this file and run it later --
-- nothing breaks by waiting, and something does break by rushing.
--
-- The preflight cannot check which build is running, so it checks the
-- next best thing: that no existing row already uses a dropped code.
-- With 0 rows today that passes trivially, and it stays correct if this
-- is ever run against a database that has collected outcomes.
--
-- WHY A CHECK AND NOT AN ENUM: a Postgres enum needs ALTER TYPE to
-- change and cannot drop a value at all. This list has already changed
-- once (eight to six) and a vendor-facing vocabulary will change again.
-- A CHECK is one DROP/ADD pair; an enum with a dead value is permanent.
--
-- NULL IS PERMITTED, as it is on quotations.status and leads.status:
-- reason_code is optional in the dialog (the vendor may record a loss
-- with only a note, or with nothing). Written explicitly rather than
-- relying on a CHECK passing when it evaluates to NULL.
--
-- NOT RUN. File only.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
-- ---------------------------------------------------------------------
do $$
declare
  v_bad text;
  v_n   int;
begin
  if to_regclass('public.quote_outcomes') is null then
    raise exception 'public.quote_outcomes is missing.';
  end if;

  -- Name the offenders rather than letting ALTER TABLE raise a bare
  -- constraint violation with nothing to act on.
  select string_agg(distinct reason_code, ', ')
    into v_bad
    from public.quote_outcomes
   where reason_code is not null
     and reason_code not in
         ('price','competitor','timing','service_scope','customer_cancelled','other');
  if v_bad is not null then
    select count(*) into v_n
      from public.quote_outcomes
     where reason_code in ('trust','unreachable');
    raise exception
      'quote_outcomes holds reason_code value(s) this CHECK would reject: %. '
      '% row(s) use the two codes dropped on 11 Sept (trust, unreachable). '
      'Decide where they map -- "trust" is usually price or competitor, '
      '"unreachable" belongs on leads.status -- and update them before '
      'adding the constraint.', v_bad, v_n;
  end if;

  -- The column comment written by 20260911_status_vocabulary.sql is the
  -- human-readable half of this constraint. If it is absent, that
  -- migration has not run and the two would disagree.
  if col_description('public.quote_outcomes'::regclass,
       (select attnum from pg_attribute
         where attrelid='public.quote_outcomes'::regclass
           and attname='reason_code')) is null then
    raise exception
      'quote_outcomes.reason_code has no comment -- run '
      '20260911_status_vocabulary.sql first, or the constraint and the '
      'documentation of it will not agree.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- THE CONSTRAINT
-- ---------------------------------------------------------------------
alter table public.quote_outcomes
  drop constraint if exists quote_outcomes_reason_code_check;

alter table public.quote_outcomes
  add constraint quote_outcomes_reason_code_check
  check (reason_code is null or reason_code in
        ('price','competitor','timing','service_scope','customer_cancelled','other'));

-- ---------------------------------------------------------------------
-- POSTFLIGHT
--
-- Asserts the constraint admits all six and REFUSES a dropped one. The
-- second half matters more: a CHECK that permits everything would pass
-- a definition test while enforcing nothing, so the refusal is proven
-- by attempting a real insert and requiring it to fail.
-- ---------------------------------------------------------------------
do $$
declare
  v_def  text;
  v_code text;
  v_org  uuid;
  v_ok   boolean := false;
begin
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conrelid = 'public.quote_outcomes'::regclass
     and conname  = 'quote_outcomes_reason_code_check';
  if v_def is null then
    raise exception 'quote_outcomes_reason_code_check was not created.';
  end if;

  foreach v_code in array
    array['price','competitor','timing','service_scope','customer_cancelled','other'] loop
    if position('''' || v_code || '''' in v_def) = 0 then
      raise exception 'the constraint does not admit %: %', v_code, v_def;
    end if;
  end loop;

  foreach v_code in array array['trust','unreachable'] loop
    if position('''' || v_code || '''' in v_def) > 0 then
      raise exception 'the constraint still admits the dropped code %.', v_code;
    end if;
  end loop;

  -- BEHAVIOURAL: a dropped code must actually be refused, not merely
  -- absent from the definition text. Insert one and require the failure,
  -- then unwind. 23514 is check_violation.
  select id into v_org from public.organizations order by created_at limit 1;

  begin
    begin
      insert into public.quote_outcomes (org_id, outcome, reason_code)
      values (v_org, 'lost', 'trust');
      -- Reached only if the constraint did NOT fire.
      raise exception 'CONSTRAINT_DID_NOT_FIRE';
    exception
      when check_violation then
        v_ok := true;          -- refused, as required
    end;

    if not v_ok then
      raise exception
        'a reason_code of "trust" was accepted; the constraint is not enforcing.';
    end if;

    -- Unwind anything this block touched, successful insert or not.
    raise exception 'REASON_PROBE_OK';
  exception
    when others then
      if sqlerrm = 'CONSTRAINT_DID_NOT_FIRE' then
        raise exception
          'a reason_code of "trust" was accepted; the constraint is not enforcing.';
      end if;
      if sqlerrm <> 'REASON_PROBE_OK' then
        raise;
      end if;
  end;

  if (select count(*) from public.quote_outcomes) <> 0 then
    raise exception
      'the probe left % row(s) in quote_outcomes; it must leave none.',
      (select count(*) from public.quote_outcomes);
  end if;

  raise notice
    'quote_outcomes.reason_code constrained to six codes; a dropped code was '
    'attempted and correctly refused.';
end $$;

commit;

-- =====================================================================
-- NOTE ON THE ROW COUNT ASSERTION
-- ---------------------------------------------------------------------
-- The final check requires quote_outcomes to be EMPTY, which is true
-- today (0 rows, 11 Sept 2026) and is what makes the probe's cleanup
-- verifiable. If this file is ever re-run against a database that has
-- collected real outcomes, that assertion will fail on legitimate data
-- — change it to compare against a count captured before the probe
-- rather than to zero. Left strict deliberately: a wrong assumption
-- that raises is better than one that passes quietly.
--
-- ROLLBACK
--   alter table public.quote_outcomes
--     drop constraint if exists quote_outcomes_reason_code_check;
-- =====================================================================
