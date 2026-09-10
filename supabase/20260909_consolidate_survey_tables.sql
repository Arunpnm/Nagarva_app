-- Consolidate the two survey tables into one.
--
-- Arun, 9 Sept 2026. ONE table, customer-facing, its total_cft feeds
-- quotation pricing. `customer_surveys` is the NAME that survives;
-- `surveys` is the TABLE that survives. Columns move, data does not.
--
-- ==========================================================================
-- READ FIRST: THE RENAME BREAKS FIVE LIVE FUNCTIONS
-- ==========================================================================
--
-- Postgres stores function bodies as TEXT and does not rewrite them when a
-- table is renamed. Five functions reference `public.surveys` by name, and
-- two of them are the anon-callable pair serving the real customer survey
-- page on link.nagarva.in:
--
--   public_get_survey_impl      v public.surveys%rowtype;  +  select * from
--   public_submit_survey_impl   update public.surveys
--   public_org_for_token        select org_id from public.surveys
--   get_survey_by_token         from public.surveys s
--   submit_survey               update public.surveys
--
-- Renaming without fixing these takes /survey down for every vendor the
-- moment it commits. That is why STEP 6 below exists even though it was not
-- in the brief: a rename that ships a production outage is not a complete
-- migration. Each is re-created with the table name corrected and every
-- other attribute — signature, return type, volatility, SECURITY DEFINER,
-- search_path — preserved byte-for-byte from `pg_get_functiondef`.
--
-- `CREATE OR REPLACE FUNCTION` cannot change a return type (see CLAUDE.md's
-- 42P13 convention). None of these change shape, so REPLACE is correct and
-- no DROP is needed.
--
-- ==========================================================================
-- NOT FIXED HERE, AND IT NEEDS ITS OWN MIGRATION: delete_org
-- ==========================================================================
--
-- `delete_org` (9,449 chars, SECURITY DEFINER, admin tooling) breaks in TWO
-- ways after this runs, and is deliberately left alone rather than rewritten
-- blind inside an unrelated change:
--
--   line 37   'surveys', ...            <- a quoted name in a table-name
--                                          array. After the rename no such
--                                          table exists.
--   line 39   'customer_surveys', ...   <- same array. Now resolves to the
--                                          renamed, data-holding table.
--                                          Listed twice in effect.
--   line 153  update customer_surveys set converted_to_order_id = null ...
--                                       <- `converted_to_order_id` belongs
--                                          to the table being DROPPED. The
--                                          surviving table has no such
--                                          column, so this line errors.
--
-- Two ways to close it, and it is Arun's call, not this file's: drop line
-- 153 and de-duplicate the array, or add `converted_to_order_id text` to the
-- surviving table. The second was not in the brief's column list, so this
-- migration does not invent it. `delete_org` is admin-only and no vendor
-- path touches it, so the breakage is real but not urgent.
--
-- ==========================================================================
-- WHAT THE BRIEF GOT WRONG ABOUT THE DATA, VERIFIED 9 SEPT 2026
-- ==========================================================================
--
--   * `customer_surveys` really is 0 rows by count(*), and 0 FKs point at
--     it. (pg_stat_user_tables once claimed 2 — see CLAUDE.md's statistics
--     convention. count(*) is what this file asserts.)
--   * `surveys` holds **7 rows, not 4**. The 9 Sept flow test added three
--     (Hariharan Subramanian, Vinay Gowda, Meenakshi Sundaram). The
--     postflight therefore captures the count in preflight and asserts it is
--     UNCHANGED, rather than hardcoding a number that was already stale when
--     the brief was written.
--   * `from_floor` and `to_floor` are **NULL on all 7 rows**. The
--     integer -> text cast is trivially safe, but "assert no nulls
--     introduced" cannot distinguish that from a cast that nulled
--     everything, because everything is already null. The postflight
--     asserts the null COUNT is unchanged instead, which is the assertion
--     that would actually catch a bad cast.
--   * The 7 Sept row (Ponmani, id 63688496-…, move_date 2026-09-11) is the
--     ONLY row carrying a move_date, so asserting it survives is meaningful
--     rather than incidental.
--
-- Cosmetic and deliberately NOT changed: the rename carries the indexes,
-- constraints, trigger and policy across, but they keep their old names —
-- `surveys_pkey`, `surveys_token_key`, `surveys_org_id_idx`,
-- `surveys_lead_id_idx`, `surveys_status_check`, `surveys_org_isolation`,
-- `trg_org_writable`. Renaming those is churn with no behavioural effect and
-- would make this diff harder to review.

begin;

-- ==========================================================================
-- STEP 1 — PREFLIGHT. Raises; never skips.
-- ==========================================================================
do $pre$
declare
  v_cs_rows   bigint;
  v_cs_fks    int;
  v_s_rows    bigint;
  v_ff_nulls  bigint;
  v_tf_nulls  bigint;
begin
  if to_regclass('public.customer_surveys') is null then
    raise exception 'PREFLIGHT: public.customer_surveys does not exist. This migration has already run, or the schema moved.';
  end if;
  if to_regclass('public.surveys') is null then
    raise exception 'PREFLIGHT: public.surveys does not exist. Nothing to rename.';
  end if;

  -- count(*), not a planner statistic.
  select count(*) into v_cs_rows from public.customer_surveys;
  if v_cs_rows <> 0 then
    raise exception
      'PREFLIGHT: customer_surveys holds % row(s). This migration DROPS it. Move or delete the data first — it will not be merged.',
      v_cs_rows;
  end if;

  select count(*) into v_cs_fks from pg_constraint
   where confrelid = 'public.customer_surveys'::regclass and contype = 'f';
  if v_cs_fks <> 0 then
    raise exception
      'PREFLIGHT: % foreign key(s) reference customer_surveys. Dropping it would break them.',
      v_cs_fks;
  end if;

  -- Capture the pre-state for the postflight. Transaction-local GUCs rather
  -- than a scratch table: a `create table` here would be a new relation in
  -- public with no RLS, which is exactly the accident this project just had.
  select count(*) into v_s_rows from public.surveys;
  select count(*) into v_ff_nulls from public.surveys where from_floor is null;
  select count(*) into v_tf_nulls from public.surveys where to_floor  is null;

  perform set_config('nagarva.pre_rows',      v_s_rows::text,   true);
  perform set_config('nagarva.pre_ff_nulls',  v_ff_nulls::text, true);
  perform set_config('nagarva.pre_tf_nulls',  v_tf_nulls::text, true);

  if v_s_rows = 0 then
    raise exception 'PREFLIGHT: surveys is empty. Expected live rows; refusing to rename a table that lost its data.';
  end if;
end
$pre$;

-- ==========================================================================
-- STEP 2 — drop the empty table, freeing the name
-- ==========================================================================
drop table public.customer_surveys;

-- ==========================================================================
-- STEP 3 — add the columns that move across
-- ==========================================================================
-- total_cft is NUMERIC, not the integer the old table used. A custom survey
-- line can carry fractional CFT; quotations.total_cft was widened from
-- integer to numeric on 17 Aug 2026 for exactly that reason, and this is the
-- column that will feed it.
alter table public.surveys
  add column if not exists items             jsonb,
  add column if not exists custom_items      jsonb,
  add column if not exists photos            jsonb,
  add column if not exists total_cft         numeric,
  add column if not exists suggested_vehicle text,
  add column if not exists service           text,
  add column if not exists notes             text,
  add column if not exists customer_email    text,
  add column if not exists from_city         text,
  add column if not exists to_city           text;

-- ==========================================================================
-- STEP 4 — from_floor / to_floor: integer -> text
-- ==========================================================================
-- "Ground", "Stilt" and "2 (no lift)" are all real answers a customer gives.
-- Explicit USING so the cast is stated rather than inferred.
alter table public.surveys
  alter column from_floor type text using from_floor::text,
  alter column to_floor   type text using to_floor::text;

-- ==========================================================================
-- STEP 5 — the rename
-- ==========================================================================
-- Indexes, constraints, the trigger, the RLS policy and the inbound FK
-- (quotations_survey_id_fkey) all follow the table by OID. Asserted below
-- rather than assumed.
alter table public.surveys rename to customer_surveys;

-- ==========================================================================
-- STEP 6 — the five functions the rename would otherwise break
-- ==========================================================================
-- NOT IN THE BRIEF. See the header for why it is here anyway. Each body is
-- verbatim from pg_get_functiondef with `public.surveys` ->
-- `public.customer_surveys` and nothing else touched.

CREATE OR REPLACE FUNCTION public.get_survey_by_token(p_token text)
 RETURNS TABLE(id uuid, status text, customer_name text, customer_phone text, org_name text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select s.id, s.status, s.customer_name, s.customer_phone, o.name as org_name
  from public.customer_surveys s
  join public.organizations o on o.id = s.org_id
  where s.token = p_token;
$function$;

CREATE OR REPLACE FUNCTION public.public_org_for_token(p_token text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Three tables, three DIFFERENT column names. The first version of this
  -- migration assumed all three were `token` and failed on
  -- `document_signatures.sign_token` — caught by the transaction, nothing
  -- applied. The preflight above now asserts all four columns by name so
  -- a rename trips the guard instead of the RUN.
  select org_id from public.customer_surveys    where token           = p_token
  union all
  select org_id from public.document_signatures where sign_token      = p_token
  union all
  select org_id from public.orders              where tracking_token  = p_token
  union all
  select org_id from public.orders              where quotation_token = p_token
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.submit_survey(p_token text, p_customer_name text, p_customer_phone text, p_from_address text, p_to_address text, p_move_date date, p_rooms jsonb, p_special_instructions text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  update public.customer_surveys
    set customer_name = p_customer_name,
        customer_phone = p_customer_phone,
        from_address = p_from_address,
        to_address = p_to_address,
        move_date = p_move_date,
        rooms = coalesce(p_rooms, '[]'::jsonb),
        special_instructions = p_special_instructions,
        status = 'submitted',
        submitted_at = now()
    where token = p_token
      and status = 'pending';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION public.public_get_survey_impl(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v public.customer_surveys%rowtype;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  select * into v from public.customer_surveys where token = p_token;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if v.status is distinct from 'pending' then
    return jsonb_build_object('ok', false, 'reason', 'already_submitted');
  end if;

  if v.expires_at < now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  -- No org_id, no lead_id, no phone. No pricing of any kind.
  -- vendor_name is the org's public trading name and nothing else.
  return jsonb_build_object(
    'ok',                   true,
    'vendor_name',          (select o.name from public.organizations o
                              where o.id = v.org_id),
    'customer_name',        v.customer_name,
    'from_address',         v.from_address,
    'to_address',           v.to_address,
    'move_date',            v.move_date,
    'rooms',                coalesce(v.rooms, '[]'::jsonb),
    'special_instructions', v.special_instructions,
    'survey_cats',          public.resolve_survey_cats(v.org_id)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.public_submit_survey_impl(p_token text, p_rooms jsonb, p_instructions text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if p_token is null or length(p_token) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;

  if p_rooms is null or jsonb_typeof(p_rooms) <> 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_payload');
  end if;

  -- Guard against an oversized payload at a public endpoint. 150, not
  -- 50: the catalogue itself offers 110 selectable lines, so the old
  -- ceiling refused legitimate lists. Keep this ABOVE the largest
  -- catalogue any tenant can build, or this refuses real customers
  -- again.
  if jsonb_array_length(p_rooms) > 150 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;

  update public.customer_surveys
     set rooms                = p_rooms,
         special_instructions = nullif(left(coalesce(p_instructions, ''), 2000), ''),
         status               = 'submitted',
         submitted_at         = now(),
         used_at              = now()
   where token      = p_token
     and status     = 'pending'
     and expires_at > now()
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'reason', 'not_submittable');
  end if;

  return jsonb_build_object('ok', true, 'survey_id', v_id);
end;
$function$;

-- ==========================================================================
-- POSTFLIGHT — assertions inside the transaction
-- ==========================================================================
do $post$
declare
  v_rows      bigint;
  v_ff_nulls  bigint;
  v_tf_nulls  bigint;
  v_bad       int;
  v_txt       text;
begin
  -- The old name is gone and the new one is the surviving table.
  if to_regclass('public.surveys') is not null then
    raise exception 'POSTFLIGHT: public.surveys still exists after the rename.';
  end if;
  if to_regclass('public.customer_surveys') is null then
    raise exception 'POSTFLIGHT: public.customer_surveys does not exist.';
  end if;

  -- Every row survived. Compared against the count captured in preflight,
  -- not against a literal that was already stale when the brief was written.
  select count(*) into v_rows from public.customer_surveys;
  if v_rows <> current_setting('nagarva.pre_rows')::bigint then
    raise exception 'POSTFLIGHT: row count changed, % before -> % after.',
      current_setting('nagarva.pre_rows'), v_rows;
  end if;

  -- The 7 Sept row, by id, still carries its move_date. It is the only row
  -- that has one, so this catches a cast or rewrite that silently blanked
  -- data in a way a row count cannot.
  if not exists (
    select 1 from public.customer_surveys
     where id = '63688496-619b-47e3-a27c-21ad8cb7c401'
       and move_date = date '2026-09-11'
  ) then
    raise exception 'POSTFLIGHT: the 7 Sept row (63688496-…) is missing or lost its move_date 2026-09-11.';
  end if;

  -- The floor columns are text now, and the cast introduced no new nulls.
  -- Every row was already null here, so the meaningful assertion is that the
  -- null count is UNCHANGED — a cast that nulled a populated row would show
  -- up as an increase.
  if (select data_type from information_schema.columns
       where table_schema='public' and table_name='customer_surveys'
         and column_name='from_floor') <> 'text' then
    raise exception 'POSTFLIGHT: from_floor is not text.';
  end if;
  if (select data_type from information_schema.columns
       where table_schema='public' and table_name='customer_surveys'
         and column_name='to_floor') <> 'text' then
    raise exception 'POSTFLIGHT: to_floor is not text.';
  end if;

  select count(*) into v_ff_nulls from public.customer_surveys where from_floor is null;
  select count(*) into v_tf_nulls from public.customer_surveys where to_floor   is null;
  if v_ff_nulls <> current_setting('nagarva.pre_ff_nulls')::bigint
     or v_tf_nulls <> current_setting('nagarva.pre_tf_nulls')::bigint then
    raise exception
      'POSTFLIGHT: floor nulls changed. from_floor % -> %, to_floor % -> %.',
      current_setting('nagarva.pre_ff_nulls'), v_ff_nulls,
      current_setting('nagarva.pre_tf_nulls'), v_tf_nulls;
  end if;

  -- All ten new columns exist.
  select count(*) into v_bad from (values
    ('items'),('custom_items'),('photos'),('total_cft'),('suggested_vehicle'),
    ('service'),('notes'),('customer_email'),('from_city'),('to_city')
  ) as w(c)
  where not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='customer_surveys' and column_name = w.c);
  if v_bad > 0 then
    raise exception 'POSTFLIGHT: % of the 10 new columns are missing.', v_bad;
  end if;

  -- The inbound FK followed the rename. Asserted, not assumed — this is the
  -- one the brief specifically called out.
  if not exists (
    select 1 from pg_constraint
     where conname   = 'quotations_survey_id_fkey'
       and conrelid  = 'public.quotations'::regclass
       and confrelid = 'public.customer_surveys'::regclass
       and contype   = 'f'
  ) then
    raise exception
      'POSTFLIGHT: quotations_survey_id_fkey does not resolve to customer_surveys.';
  end if;

  -- RLS survived the rename: still enabled, and the policy that was on
  -- surveys is on the renamed table. Behaviour, not just the flag.
  if not (select relrowsecurity from pg_class where oid = 'public.customer_surveys'::regclass) then
    raise exception 'POSTFLIGHT: RLS is not enabled on customer_surveys.';
  end if;
  if not exists (
    select 1 from pg_policy
     where polrelid = 'public.customer_surveys'::regclass
       and polname  = 'surveys_org_isolation'
  ) then
    raise exception 'POSTFLIGHT: the org_isolation policy did not survive the rename.';
  end if;

  -- The single token index carried across (the duplicate was dropped by
  -- 20260908_drop_redundant_duplicate_indexes.sql) and is still unique.
  if not exists (
    select 1 from pg_index ix join pg_class i on i.oid = ix.indexrelid
     where ix.indrelid = 'public.customer_surveys'::regclass
       and i.relname   = 'surveys_token_key'
       and ix.indisunique
  ) then
    raise exception 'POSTFLIGHT: surveys_token_key is missing or no longer unique on the renamed table.';
  end if;

  -- No function body still points at the old name. This is what would have
  -- taken /survey down.
  select count(*), string_agg(p.proname, ', ')
    into v_bad, v_txt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc like '%public.surveys%';
  if v_bad > 0 then
    raise exception
      'POSTFLIGHT: % function(s) still reference public.surveys: %', v_bad, v_txt;
  end if;
end
$post$;

commit;

-- ==========================================================================
-- ROLLBACK — read this before using it
-- ==========================================================================
-- The rename, the added columns and the floor cast all reverse cleanly. The
-- DROPPED customer_surveys table does NOT — it had zero rows, so no data is
-- lost, but its definition is gone and would have to be recreated from a
-- prior migration if it were ever wanted again. It will not be.
-- begin;
--   alter table public.customer_surveys rename to surveys;
--   alter table public.surveys
--     alter column from_floor type integer using nullif(from_floor,'')::integer,
--     alter column to_floor   type integer using nullif(to_floor,'')::integer;
--   alter table public.surveys
--     drop column if exists items,
--     drop column if exists custom_items,
--     drop column if exists photos,
--     drop column if exists total_cft,
--     drop column if exists suggested_vehicle,
--     drop column if exists service,
--     drop column if exists notes,
--     drop column if exists customer_email,
--     drop column if exists from_city,
--     drop column if exists to_city;
--   -- and re-apply the five function bodies with public.surveys restored.
-- commit;
