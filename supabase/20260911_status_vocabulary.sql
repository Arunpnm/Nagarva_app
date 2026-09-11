-- =====================================================================
-- 20260911_status_vocabulary.sql                     PART 2, SQL half
--
-- Three things, all vocabulary. No behaviour changes.
--   1. quotations.status  CHECK: draft, sent, revised, accepted, lost
--   2. leads.status       CHECK: the six constants lead_status.dart
--                                already defines
--   3. quote_outcomes.reason_code: the column comment it never had
--
-- AND IT PROVES THE AUDIT TRIGGER BY A REAL WRITE.
-- 20260911_audit_row_trigger.sql installed trg_audit_quotations and
-- verified it with a probe on app_settings. It has NEVER FIRED on
-- quotations -- audit_log is still at 48 rows, exactly where it was
-- before the trigger existed, because nothing has written to an audited
-- table since. Installed and working are different states, so the
-- postflight below performs a REAL UPDATE on a real quotations row and
-- asserts the audit row that comes back, then unwinds it.
--
-- The probe update is `status: draft -> sent`, chosen deliberately:
-- 'sent' is a value that did not exist before this migration, so one
-- write proves BOTH that the new CHECK admits the new vocabulary AND
-- that the trigger fires on quotations with a correct diff.
--
-- WHY THE CHECKS ARE SAFE TO ADD NOW (counted 11 Sept 2026, including
-- soft-deleted rows -- a CHECK applies to those too):
--   quotations: 4 accepted, 2 draft, 0 soft-deleted, 0 null
--   leads:      6 confirmed, 2 follow_up, 1 new, 0 soft-deleted, 0 null
-- Every live value is already legal. The preflight re-counts rather
-- than trusting this comment, and names any offender instead of letting
-- ALTER TABLE raise a bare constraint violation.
--
-- 'sent' AND 'revised' HAVE NO WRITER YET -- deliberate.
-- The constraint admits two values the app cannot currently produce.
-- That is the correct order: Part 1's revision RPC writes 'revised',
-- and defining the vocabulary before the thing that writes into it
-- costs nothing, while the reverse costs an amendment written around
-- rows that already exist. The Dart half (the 'sent' writer on share,
-- and the _kLostReasonCodes trim) is a separate commit.
--
-- NULL IS ALLOWED, AND THAT IS A DECISION, NOT AN OVERSIGHT.
-- Both columns are nullable with a default ('draft' / 'new'). A bare
-- `status in (...)` would already permit NULL, because a CHECK passes
-- when it evaluates to NULL rather than false -- so the NULL branch is
-- written out explicitly instead of relying on the next reader knowing
-- three-valued logic. Tightening either column to NOT NULL is a
-- separate decision with its own backfill question; it is not smuggled
-- in here.
--
-- NOT RUN. File only, per instruction.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
-- ---------------------------------------------------------------------
do $$
declare
  v_bad  text;
  v_n    int;
begin
  if to_regclass('public.quotations') is null then
    raise exception 'public.quotations is missing.';
  end if;
  if to_regclass('public.leads') is null then
    raise exception 'public.leads is missing.';
  end if;
  if to_regclass('public.quote_outcomes') is null then
    raise exception 'public.quote_outcomes is missing.';
  end if;

  -- Name the offending values rather than letting ALTER TABLE raise a
  -- bare "violates check constraint" with nothing to act on.
  select string_agg(distinct coalesce(status,'<null>'), ', ')
    into v_bad
    from public.quotations
   where status is not null
     and status not in ('draft','sent','revised','accepted','lost');
  if v_bad is not null then
    raise exception
      'quotations holds status value(s) the new CHECK would reject: %. '
      'Reconcile them before adding the constraint.', v_bad;
  end if;

  select string_agg(distinct coalesce(status,'<null>'), ', ')
    into v_bad
    from public.leads
   where status is not null
     and status not in ('new','follow_up','survey_done','quoted','confirmed','lost');
  if v_bad is not null then
    raise exception
      'leads holds status value(s) the new CHECK would reject: %.', v_bad;
  end if;

  -- The postflight probe depends on the audit trigger being live AND on
  -- a draft quotation existing to move. Both are preconditions of this
  -- migration doing its second job, so both raise rather than skip.
  if not exists (
    select 1 from pg_trigger
     where tgname = 'trg_audit_quotations' and not tgisinternal and tgenabled = 'O'
  ) then
    raise exception
      'trg_audit_quotations is missing or disabled. Run '
      '20260911_audit_row_trigger.sql first -- this migration exists partly '
      'to prove that trigger by a real write.';
  end if;

  select count(*) into v_n
    from public.quotations where status = 'draft' and deleted_at is null;
  if v_n = 0 then
    raise exception
      'no draft quotation exists to probe the audit trigger with. The probe '
      'needs one real row to move from draft to sent.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. quotations.status
-- ---------------------------------------------------------------------
alter table public.quotations
  drop constraint if exists quotations_status_check;

alter table public.quotations
  add constraint quotations_status_check
  check (status is null or status in ('draft','sent','revised','accepted','lost'));

comment on column public.quotations.status is
  'draft (saved, not sent) | sent (issued to the customer) | revised '
  '(superseded by a newer version -- written by the revision RPC) | '
  'accepted (converted to an order) | lost (see quote_outcomes for the '
  'reason). Free text until 11 Sept 2026, which is how it ended up with '
  'only two values in use.';

-- ---------------------------------------------------------------------
-- 2. leads.status
--    The six values lib/backend/lead_status.dart already defines. No new
--    vocabulary -- this constrains the column to what the app has always
--    written, including the `lost` state _confirmMarkLost() already sets.
-- ---------------------------------------------------------------------
alter table public.leads
  drop constraint if exists leads_status_check;

alter table public.leads
  add constraint leads_status_check
  check (status is null or status in
        ('new','follow_up','survey_done','quoted','confirmed','lost'));

comment on column public.leads.status is
  'Mirrors lib/backend/lead_status.dart exactly: new | follow_up | '
  'survey_done | quoted | confirmed | lost. Keep the two in step -- the '
  'Dart constants are the vocabulary, this CHECK is the enforcement.';

-- ---------------------------------------------------------------------
-- 3. quote_outcomes.reason_code -- the comment it never had.
--
-- lead_detail_page_widget.dart's _kLostReasonCodes says its eight values
-- are "migration 004's own column comment -- not invented here". There
-- is NO comment on this column (col_description returned null, 11 Sept
-- 2026), so that provenance claim has never been true. Writing the
-- comment for real, with the SIX codes agreed rather than the eight.
--
-- Dropped, and why -- both free, since quote_outcomes has 0 rows:
--   trust       a customer will not say "I did not trust you", so the
--               code gets guessed, and a guessed reason in a reasons
--               report is worse than a blank one
--   unreachable that is a LEAD state, not a quote outcome. It already
--               exists as leads.status -- keeping it here too is the
--               duplication this project keeps removing
--
-- No CHECK constraint on this column, deliberately: the Dart half still
-- offers eight values until it is trimmed, and a CHECK landing first
-- would make the live Mark Lost dialog fail on two of its options. The
-- CHECK belongs with the Dart trim, in that commit.
-- ---------------------------------------------------------------------
comment on column public.quote_outcomes.reason_code is
  'One of six: price | competitor | timing | service_scope | '
  'customer_cancelled | other. Free text with reason_note carrying the '
  'detail. Trimmed from eight on 11 Sept 2026 -- "trust" invited a '
  'guess, and "unreachable" is a lead state (leads.status), not a quote '
  'outcome. NOT yet CHECK-constrained: the Dart dialog still offers the '
  'old eight until its own commit lands.';

-- ---------------------------------------------------------------------
-- POSTFLIGHT
--
-- Structural assertions, then the real-write proof of the audit trigger.
-- ---------------------------------------------------------------------
do $$
declare
  v_def        text;
  v_qid        text;
  v_org        uuid;
  v_a_entity   text;
  v_a_action   text;
  v_a_old      jsonb;
  v_a_new      jsonb;
  v_a_fields   text[];
  v_a_org      uuid;
  v_rows       int;
  v_ok         boolean := false;
begin
  -- 1. Both constraints exist and say what they should.
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conrelid = 'public.quotations'::regclass
     and conname  = 'quotations_status_check';
  if v_def is null then
    raise exception 'quotations_status_check was not created.';
  end if;
  foreach v_a_action in array array['draft','sent','revised','accepted','lost'] loop
    if position('''' || v_a_action || '''' in v_def) = 0 then
      raise exception
        'quotations_status_check does not admit %: %', v_a_action, v_def;
    end if;
  end loop;

  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conrelid = 'public.leads'::regclass
     and conname  = 'leads_status_check';
  if v_def is null then
    raise exception 'leads_status_check was not created.';
  end if;
  foreach v_a_action in array
    array['new','follow_up','survey_done','quoted','confirmed','lost'] loop
    if position('''' || v_a_action || '''' in v_def) = 0 then
      raise exception 'leads_status_check does not admit %: %', v_a_action, v_def;
    end if;
  end loop;

  -- 2. The comment landed.
  if col_description('public.quote_outcomes'::regclass,
        (select attnum from pg_attribute
          where attrelid='public.quote_outcomes'::regclass
            and attname='reason_code')) is null then
    raise exception 'quote_outcomes.reason_code still has no comment.';
  end if;

  -- 3. THE REAL-WRITE PROOF.
  --
  -- The audit trigger has been live on quotations since
  -- 20260911_audit_row_trigger.sql and has never fired -- audit_log sat
  -- at 48 rows, unchanged, because nothing wrote to an audited table.
  -- A row in pg_trigger is not evidence that a correct audit row gets
  -- written. This moves a real quotation draft -> sent, reads the audit
  -- row back, asserts its shape, and then unwinds the whole block so
  -- neither the quotation nor the audit row survives.
  --
  -- draft -> sent also exercises the constraint added above: 'sent' was
  -- not a legal value until nine statements ago.
  select id, org_id into v_qid, v_org
    from public.quotations
   where status = 'draft' and deleted_at is null
   order by created_at
   limit 1;

  begin
    update public.quotations set status = 'sent' where id = v_qid;

    select entity_type, action, old_value, new_value, changed_fields, org_id
      into v_a_entity, v_a_action, v_a_old, v_a_new, v_a_fields, v_a_org
      from public.audit_log
     where entity_type = 'quotations'
       and entity_id   = v_qid
       and action      = 'row_update'
     order by created_at desc
     limit 1;

    if v_a_action is null then
      raise exception
        'AUDIT PROBE FAILED: a real UPDATE on quotations % produced no '
        'audit row. The trigger is installed but not working.', v_qid;
    end if;
    if v_a_entity <> 'quotations' then
      raise exception 'AUDIT PROBE: entity_type is %, expected quotations.', v_a_entity;
    end if;
    if v_a_old ->> 'status' is distinct from 'draft' then
      raise exception
        'AUDIT PROBE: old_value.status is %, expected draft.',
        coalesce(v_a_old ->> 'status', '<null>');
    end if;
    if v_a_new ->> 'status' is distinct from 'sent' then
      raise exception
        'AUDIT PROBE: new_value.status is %, expected sent.',
        coalesce(v_a_new ->> 'status', '<null>');
    end if;
    if v_a_fields is null or not ('status' = any(v_a_fields)) then
      raise exception
        'AUDIT PROBE: changed_fields did not name status (got %).',
        coalesce(v_a_fields::text, '<null>');
    end if;
    if v_a_org is distinct from v_org then
      raise exception
        'AUDIT PROBE: audit row org_id % does not match the quotation''s %.',
        coalesce(v_a_org::text,'<null>'), coalesce(v_org::text,'<null>');
    end if;

    -- Everything passed. Unwind: the UPDATE and its audit row both go.
    raise exception 'STATUS_PROBE_OK';
  exception
    when others then
      if sqlerrm <> 'STATUS_PROBE_OK' then
        raise;                      -- a real failure: propagate, roll back
      end if;
      v_ok := true;
  end;

  if not v_ok then
    raise exception 'audit probe did not run to completion.';
  end if;

  -- 4. Nothing survived the probe.
  select count(*) into v_rows
    from public.quotations where id = v_qid and status <> 'draft';
  if v_rows <> 0 then
    raise exception 'probe left quotation % off draft; it must not.', v_qid;
  end if;
  select count(*) into v_rows
    from public.audit_log where entity_type='quotations' and entity_id = v_qid;
  if v_rows <> 0 then
    raise exception 'probe left % audit row(s) behind; it must not.', v_rows;
  end if;

  raise notice
    'status vocabulary constrained; audit trigger PROVEN BY A REAL WRITE on '
    'quotations (old/new/changed_fields/org_id all correct) and unwound.';
end $$;

commit;

-- =====================================================================
-- AFTER THIS RUNS
-- ---------------------------------------------------------------------
-- The probe proves the trigger end to end EXCEPT for `actor`. It runs as
-- postgres in the SQL editor, where auth.uid() is null, so actor will be
-- null on the probe row -- which is why the assertions above do not test
-- it. The first real app write is what proves actor, and it will be the
-- Dart half's 'sent' writer. After that ships, check:
--
--   select entity_type, action, actor, org_id, changed_fields, created_at
--     from audit_log where action = 'row_update'
--    order by created_at desc limit 5;
--
-- Expect actor = the session's auth uid, NOT null. actor_name and
-- actor_role will still be null -- that is the documented limit until
-- staff.auth_user_id is populated at PIN login, not a bug.
--
-- NEXT, IN ORDER:
--  * Dart half (own commit): the 'sent' writer on the share action, and
--    trim _kLostReasonCodes from eight to six. A CHECK on
--    quote_outcomes.reason_code lands WITH that trim, never before it --
--    the live Mark Lost dialog still offers the two dropped codes.
--  * Atomic lost (own commit, own review): quotations.status = 'lost'
--    and the quote_outcomes row written in one transaction. That is a
--    behaviour change to a live path, not vocabulary work, which is why
--    it does not ride along here.
--  * Part 1: the revision RPC, which writes 'revised' -- legal as of
--    this migration.
--
-- ROLLBACK
--   alter table public.quotations drop constraint if exists quotations_status_check;
--   alter table public.leads      drop constraint if exists leads_status_check;
--   comment on column public.quote_outcomes.reason_code is null;
-- =====================================================================
