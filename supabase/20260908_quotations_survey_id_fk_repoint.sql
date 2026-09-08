-- `quotations.survey_id` points at the wrong table.
--
-- Arun, 8 Sept 2026: "surveys wins. customer_surveys is NOT a duplicate —
-- it's an item/CFT-based model with a review workflow. It stays in the
-- schema for a future module."
--
-- The FK currently targets `customer_surveys`, which has never held a
-- row and has no writer anywhere. Every survey the product actually
-- creates lands in `surveys` — both app writers (leads_page,
-- lead_detail) and all four survey RPCs write there. So the column could
-- never have been populated: the only ids available to put in it would
-- have violated the constraint.
--
-- That is why `quotations.survey_id` has never been non-null on any row.
-- It is not an unused feature; it is a feature that was structurally
-- impossible to use.
--
-- ==========================================================================
-- SCOPE — what this does NOT do
-- ==========================================================================
--
-- `customer_surveys` is NOT dropped, NOT merged, and gets NO writer. It
-- stays exactly as it is for the future item/CFT module. This migration
-- moves ONE foreign key.
--
-- No data is migrated because there is none to migrate: every
-- `survey_id` is null by construction (asserted in PREFLIGHT — if that
-- assertion ever fails, STOP, because a non-null value would be a
-- `customer_surveys` id that this repoint would silently orphan).
--
-- ==========================================================================
-- ORDERING — this runs BEFORE the app writes survey_id
-- ==========================================================================
--
-- The Dart side is gated on `kQuotationSurveyIdFkRepointed`
-- (lib/config/app_config.dart), which ships FALSE. Flip it only after
-- this file has run. Writing survey_id first would insert `surveys` ids
-- against a constraint still pointing at `customer_surveys`, and every
-- quote save from a survey would fail with a foreign-key violation.

begin;

-- ==========================================================================
-- PREFLIGHT — raises, never skips
-- ==========================================================================
do $pre$
declare
  v_conname text;
  v_target  text;
  v_dangling bigint;
begin
  if to_regclass('public.quotations') is null then
    raise exception 'PREFLIGHT: public.quotations does not exist.';
  end if;
  if to_regclass('public.surveys') is null then
    raise exception 'PREFLIGHT: public.surveys does not exist - nothing to point at.';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='quotations'
                    and column_name='survey_id') then
    raise exception 'PREFLIGHT: quotations.survey_id does not exist.';
  end if;

  -- The column and surveys.id must be the same type, or the new
  -- constraint cannot be created.
  if (select data_type from information_schema.columns
       where table_schema='public' and table_name='quotations'
         and column_name='survey_id')
     is distinct from
     (select data_type from information_schema.columns
       where table_schema='public' and table_name='surveys'
         and column_name='id') then
    raise exception
      'PREFLIGHT: quotations.survey_id and surveys.id are different types. Fix that first.';
  end if;

  -- Find the existing FK on survey_id, whatever it is called.
  select con.conname, cl.relname
    into v_conname, v_target
    from pg_constraint con
    join pg_class cl on cl.oid = con.confrelid
   where con.conrelid = 'public.quotations'::regclass
     and con.contype  = 'f'
     and con.conkey = array[(select attnum from pg_attribute
                              where attrelid='public.quotations'::regclass
                                and attname='survey_id')];

  if v_conname is null then
    raise notice 'No existing FK on quotations.survey_id - one will simply be added.';
  elsif v_target = 'surveys' then
    raise exception
      'PREFLIGHT: quotations.survey_id already targets surveys - this migration has already run.';
  elsif v_target <> 'customer_surveys' then
    raise exception
      'PREFLIGHT: quotations.survey_id targets %, which is neither customer_surveys nor surveys. Stopping rather than guessing.',
      v_target;
  end if;

  -- THE ONE THAT MATTERS. Every value must be null, because a non-null
  -- value is a customer_surveys id that repointing would orphan — the
  -- constraint would still be satisfied structurally while the row now
  -- claims a survey that does not exist.
  select count(*) into v_dangling from public.quotations where survey_id is not null;
  if v_dangling > 0 then
    raise exception
      'PREFLIGHT: % quotation(s) already carry a survey_id. These reference customer_surveys and would be silently orphaned. Migrate or null them deliberately first.',
      v_dangling;
  end if;
end
$pre$;

-- ==========================================================================
-- REPOINT
-- ==========================================================================
do $do$
declare
  v_conname text;
begin
  select con.conname into v_conname
    from pg_constraint con
   where con.conrelid = 'public.quotations'::regclass
     and con.contype  = 'f'
     and con.conkey = array[(select attnum from pg_attribute
                              where attrelid='public.quotations'::regclass
                                and attname='survey_id')];

  if v_conname is not null then
    execute format('alter table public.quotations drop constraint %I', v_conname);
  end if;
end
$do$;

-- ON DELETE SET NULL, deliberately: deleting a survey must not delete
-- the quotation that came from it. The quote is a document the customer
-- was sent and the vendor may have been paid against; losing the link to
-- its origin is acceptable, losing the quote is not.
alter table public.quotations
  add constraint quotations_survey_id_fkey
  foreign key (survey_id) references public.surveys(id)
  on delete set null;

create index if not exists quotations_survey_id_idx
  on public.quotations (survey_id)
  where survey_id is not null;

-- ==========================================================================
-- POSTFLIGHT — asserts the CONSTRUCT, rolls back if it is not there
-- ==========================================================================
do $post$
declare
  v_target text;
  v_action char;
begin
  select cl.relname, con.confdeltype
    into v_target, v_action
    from pg_constraint con
    join pg_class cl on cl.oid = con.confrelid
   where con.conrelid = 'public.quotations'::regclass
     and con.contype  = 'f'
     and con.conname  = 'quotations_survey_id_fkey';

  if v_target is null then
    raise exception 'POSTFLIGHT: quotations_survey_id_fkey was not created.';
  end if;

  -- confrelid must resolve to surveys, by name, not by assumption.
  if v_target <> 'surveys' then
    raise exception
      'POSTFLIGHT: quotations.survey_id resolves to %, not surveys.', v_target;
  end if;

  if v_action <> 'n' then
    raise exception
      'POSTFLIGHT: expected ON DELETE SET NULL, found confdeltype %.', v_action;
  end if;

  -- And nothing else still points survey_id at the old table.
  if exists (select 1 from pg_constraint con
               join pg_class cl on cl.oid = con.confrelid
              where con.conrelid = 'public.quotations'::regclass
                and con.contype = 'f'
                and cl.relname = 'customer_surveys') then
    raise exception
      'POSTFLIGHT: a constraint on quotations still targets customer_surveys.';
  end if;
end
$post$;

commit;

-- AFTER RUNNING: set kQuotationSurveyIdFkRepointed = true in
-- lib/config/app_config.dart and ship a build. Until then the app leaves
-- survey_id null, exactly as it does today.

-- ==========================================================================
-- ROLLBACK
-- ==========================================================================
-- begin;
--   alter table public.quotations drop constraint if exists quotations_survey_id_fkey;
--   drop index if exists public.quotations_survey_id_idx;
--   update public.quotations set survey_id = null where survey_id is not null;
--   alter table public.quotations
--     add constraint quotations_survey_id_fkey
--     foreign key (survey_id) references public.customer_surveys(id);
-- commit;
