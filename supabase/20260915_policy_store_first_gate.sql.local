-- =====================================================================
-- 20260915_policy_store_first_gate.sql                          PART 4
--
-- Per-tenant policy: the store made safe, the single reader, and the
-- first gate. Follows PART 1 (revise_quote), PART 2 (status vocabulary)
-- and PART 3 step 1 (audit_row trigger), all of which are LIVE --
-- verified by query on 15 Sept 2026, not read off a deploy log:
--   audit_row() exists, trg_audit_quotations and trg_audit_app_settings
--   are both attached with tgenabled = 'O'.
-- That matters because CLAUDE.md requires the audit trigger to land
-- BEFORE or WITH the first policy gate -- "a policy that can be switched
-- with no record is the one thing a policy gate cannot be." The trigger
-- is already on app_settings, so this migration inherits the record
-- rather than owing it.
--
-- THREE THINGS, AND THE FIRST IS WHY THE OTHER TWO ARE WORTH ANYTHING
--
-- 1. WRITES TO app_settings BECOME OWNER-ONLY.
--    app_settings carries ONE policy today, `org_isolation FOR ALL`, so
--    every org member can INSERT, UPDATE and DELETE policy rows.
--    PROVEN BY EXECUTION, rolled back, 15 Sept 2026: a constructed
--    org_members row with role 'staff' -- is_org_owner() = false --
--    inserted into app_settings with no error:
--
--      PROBE_ROLLBACK is_owner=f sees=8
--                     NON_OWNER_MEMBER_WROTE_POLICY=t err=-
--
--    A gate a blocked supervisor can switch off is not a gate. Every
--    policy below would have been decorative without this.
--
--    Nothing live regresses. Counted, not assumed: all 24 app_settings
--    rows are category 'documents', every AppSettingsTable reference in
--    lib/ is a READ, no Edge Function names the table, and the only SQL
--    writer (seed_org_document_settings) is SECURITY DEFINER and so is
--    not subject to RLS at all.
--
-- 2. ONE READER: org_policy_bool() / org_policy_num() / org_policy().
--    CLAUDE.md rule 5 -- "Every policy read goes through a single
--    helper. A hand-written app_settings query is the thing to flag in
--    review." The DEFAULT IS AN ARGUMENT, which makes rule 3 ("ABSENT
--    MEANS DEFAULT") structural rather than remembered at each site.
--
-- 3. THE FIRST GATE: revision_reason_required_after_confirm, default ON.
--    Chosen first because it is the one policy whose ON behaviour is
--    ALREADY what the product does, so with no row seeded the product
--    is byte-for-byte unchanged. A first gate that cannot change
--    anything on the day it ships is the right first gate.
--
-- NOT SEEDED. No policy row is written for any org, by design (rule 3).
-- A tenant with zero policy rows behaves exactly like today's product,
-- and a policy added in six months needs no backfill.
--
-- NOT RUN. File only, per this project's standing convention.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

-- ---------------------------------------------------------------------
-- PREFLIGHT. Raises; never skips.
--
-- Every predicate below was dry-run READ-ONLY against the live database
-- before this file was written, and each one discriminates: it returns a
-- different answer before and after this migration, or it is an
-- invariant asserted as a precondition. A check that reads the same in
-- both states is not a check.
-- ---------------------------------------------------------------------
do $$
declare
  v_n int;
begin
  if to_regclass('public.app_settings') is null then
    raise exception 'public.app_settings is missing.';
  end if;

  -- Already applied? The FOR ALL policy is gone in the post state.
  if not exists (
    select 1 from pg_policy
     where polrelid = 'public.app_settings'::regclass
       and polname = 'org_isolation' and polcmd = '*'
  ) then
    raise exception
      'app_settings no longer carries the single `org_isolation FOR ALL` '
      'policy this migration splits. Either it has already run, or the '
      'policy set has been changed by something else -- inspect '
      'pg_policy for public.app_settings before re-running.';
  end if;

  -- The uniqueness the reader and every future upsert depend on.
  -- ASK pg_index.indisunique, NOT pg_constraint: app_settings_uniq was
  -- created with CREATE UNIQUE INDEX and so appears in NO constraint
  -- catalogue. A pg_constraint query reports this table unprotected.
  if not exists (
    select 1 from pg_index ix join pg_class i on i.oid = ix.indexrelid
     where ix.indrelid = 'public.app_settings'::regclass
       and ix.indisunique and i.relname = 'app_settings_uniq'
  ) then
    raise exception
      'app_settings_uniq (unique on org_id, category, key) is missing. '
      'Without it one policy can be held by two rows, which is the '
      'two-sources-one-value shape this store exists to avoid.';
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'app_settings'
       and c.relrowsecurity
  ) then
    raise exception 'RLS is not enabled on app_settings.';
  end if;

  -- is_org_owner() is what the new write policies rest on. It must
  -- exist and it must be exists()-wrapped, because a NULL-returning
  -- owner check in a USING clause is the fail-open shape
  -- 20260915_set_staff_pin_fail_open.sql exists to close.
  if to_regprocedure('public.is_org_owner(uuid)') is null then
    raise exception 'public.is_org_owner(uuid) is missing.';
  end if;
  -- Behavioural, not a string match for 'exists' over the body: a text
  -- check like that is satisfied by a COMMENT mentioning exists, which
  -- is the shape CLAUDE.md records under "an is-it-already-present check
  -- must not be able to match PROSE about the thing". An
  -- exists()-wrapped function returns FALSE for an org that does not
  -- exist; a bare `col = auth.uid()` rewrite would return NULL.
  if public.is_org_owner('00000000-0000-0000-0000-000000000000'::uuid)
     is null then
    raise exception
      'is_org_owner() returned NULL rather than false; it is no longer '
      'exists()-wrapped and must not be the basis of a write policy.';
  end if;

  -- PART 3 step 1 must be live, or a policy could be switched with no
  -- record. This is the precondition CLAUDE.md names, asserted rather
  -- than assumed.
  select count(*) into v_n
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
   where not t.tgisinternal and p.proname = 'audit_row'
     and t.tgrelid = 'public.app_settings'::regclass
     and t.tgenabled = 'O';
  if v_n <> 1 then
    raise exception
      'the audit trigger is not attached-and-enabled on app_settings '
      '(found %). Run 20260911_audit_row_trigger.sql first: a policy '
      'that can be switched with no record is not a policy gate.', v_n;
  end if;

  -- revise_quote is the first gate's host. Assert the SIGNATURE, with
  -- to_regprocedure -- to_regproc takes a NAME and returns NULL when
  -- handed an argument list, in every state, which is an always-fails
  -- check that refuses a correct migration.
  if to_regprocedure('public.revise_quote(text,jsonb,text)') is null then
    raise exception 'public.revise_quote(text,jsonb,text) is missing.';
  end if;

  -- The behavioural postflight needs a quotation with a live order, or
  -- it passes having tested nothing. Refuse rather than report success
  -- on an untested gate.
  if not exists (
    select 1 from public.quotations q
     where q.deleted_at is null
       and exists (select 1 from public.orders o
                    where o.quotation_id = q.id and o.deleted_at is null
                      and coalesce(o.status,'') <> 'cancelled')
  ) then
    raise exception
      'no quotation with a live order exists, so the reason gate cannot '
      'be exercised. This migration refuses to install a gate it cannot '
      'prove.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. THE STORE -- split org_isolation FOR ALL into read and write
--
-- SELECT stays org-scope: reads are unchanged for every member, and the
-- reader below relies on that.
-- INSERT / UPDATE / DELETE become owner-only.
--
-- WHY OWNER AND NOT MANAGER. is_org_manager() matches
-- role in ('owner','admin','manager'). Policy decides whether money must
-- be collected before a job is confirmed; a manager who is blocked by
-- that is exactly the person with a reason to switch it off. This
-- follows the Tier A/B precedent, where org-level configuration writes
-- are owner-only via is_org_owner(). If a vendor later needs a manager
-- to edit policy, that is a deliberate widening with an argument behind
-- it, not a default.
--
-- is_org_owner(org_id) already implies membership of that org, so the
-- org check is subsumed -- it is written out anyway because a policy
-- should read as what it enforces.
-- ---------------------------------------------------------------------
drop policy if exists org_isolation on public.app_settings;

create policy app_settings_select on public.app_settings
  for select
  using (org_id in (select current_org_ids()));

create policy app_settings_insert on public.app_settings
  for insert
  with check (
    org_id in (select current_org_ids())
    and public.is_org_owner(org_id)
  );

create policy app_settings_update on public.app_settings
  for update
  using (
    org_id in (select current_org_ids())
    and public.is_org_owner(org_id)
  )
  with check (
    org_id in (select current_org_ids())
    and public.is_org_owner(org_id)
  );

create policy app_settings_delete on public.app_settings
  for delete
  using (
    org_id in (select current_org_ids())
    and public.is_org_owner(org_id)
  );

-- ---------------------------------------------------------------------
-- 2. THE SINGLE READER
--
-- SECURITY INVOKER, deliberately. app_settings SELECT is org-scope, so
-- running as the caller makes isolation apply for free; a DEFINER
-- version would have to re-implement it by hand, which is the class of
-- bug this week was spent closing. It also keeps one more DEFINER
-- function off a surface that has just been shrunk by four.
--
-- THE FAIL DIRECTION, stated because it is not the same for every
-- policy. An unreadable or absent row yields p_default. For the first
-- gate that default is TRUE, so the unreadable case still REQUIRES a
-- reason -- it fails closed. A future gate whose default is OFF fails
-- OPEN under the same code, so such a gate must be enforced where the
-- money is (a trigger raising P0001), never by this read alone. Rule 6.
--
-- The default is an ARGUMENT rather than a constant inside the function
-- because "absent means default" is a per-policy fact, and a single
-- reader that hardcoded one default would quietly impose it on the next
-- policy someone adds.
-- ---------------------------------------------------------------------
create or replace function public.org_policy(p_org_id uuid, p_key text)
returns jsonb
language sql
stable
set search_path to 'public', 'pg_catalog'
as $function$
  select s.value
    from app_settings s
   where s.org_id = p_org_id
     and s.category = 'policy'
     and s.key = p_key
$function$;

comment on function public.org_policy(uuid, text) is
  'Raw per-tenant policy value from app_settings (category ''policy''). '
  'NULL means no row, which means the policy default -- callers must use '
  'org_policy_bool/org_policy_num, which take the default explicitly.';

create or replace function public.org_policy_bool(
  p_org_id uuid, p_key text, p_default boolean)
returns boolean
language sql
stable
set search_path to 'public', 'pg_catalog'
as $function$
  select case
    when v is null                then p_default
    when jsonb_typeof(v) = 'boolean' then (v)::text::boolean
    -- A value stored as the STRING "true" is accepted so a hand-written
    -- row does not read as its own opposite. Anything else is not a
    -- boolean and falls back to the default rather than being coerced --
    -- a garbled value must not silently switch a gate.
    when jsonb_typeof(v) = 'string'
         and lower(v #>> '{}') in ('true','false')
                                  then lower(v #>> '{}') = 'true'
    else p_default
  end
  from (select public.org_policy(p_org_id, p_key) as v) t
$function$;

comment on function public.org_policy_bool(uuid, text, boolean) is
  'The single reader for a boolean per-tenant policy. Absent, unreadable '
  'or non-boolean means p_default -- CLAUDE.md rule 3. Never hand-write '
  'an app_settings query for a policy.';

create or replace function public.org_policy_num(
  p_org_id uuid, p_key text, p_default numeric default null)
returns numeric
language sql
stable
set search_path to 'public', 'pg_catalog'
as $function$
  select case
    when v is null                  then p_default
    when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric
    when jsonb_typeof(v) = 'string'
         and (v #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$'
                                    then (v #>> '{}')::numeric
    else p_default
  end
  from (select public.org_policy(p_org_id, p_key) as v) t
$function$;

comment on function public.org_policy_num(uuid, text, numeric) is
  'The single reader for a numeric per-tenant policy. Default is NULL, '
  'which is the "never seeded" state CLAUDE.md rule 4 requires: a policy '
  'needing a figure ships with the figure NULL and its gate OFF, and the '
  'gate refuses to switch ON until the figure is set.';

-- Grants: mirror revise_quote, which is the first caller. PUBLIC is
-- revoked explicitly -- a function inherits EXECUTE from the default
-- PUBLIC grant, so revoking from anon alone changes nothing and
-- reports success.
revoke all on function public.org_policy(uuid, text)                   from public;
revoke all on function public.org_policy_bool(uuid, text, boolean)     from public;
revoke all on function public.org_policy_num(uuid, text, numeric)      from public;
revoke all on function public.org_policy(uuid, text)                   from anon;
revoke all on function public.org_policy_bool(uuid, text, boolean)     from anon;
revoke all on function public.org_policy_num(uuid, text, numeric)      from anon;
grant execute on function public.org_policy(uuid, text)                to authenticated, service_role;
grant execute on function public.org_policy_bool(uuid, text, boolean)  to authenticated, service_role;
grant execute on function public.org_policy_num(uuid, text, numeric)   to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 3. THE FIRST GATE -- and a coupling that had to be split first
--
-- The live function computes ONE variable and uses it for THREE things:
--
--   v_reason_required := exists (<a live order references this quote>);
--   ...
--   if v_reason_required and <no reason> then raise ...
--   status = case when v_reason_required then quotations.status
--                 else 'revised' end
--   return ... 'reason_required', v_reason_required
--
-- The first is the reason gate. The second is a STATUS decision: a quote
-- with a live order keeps its status, one without is marked 'revised'.
-- Those are two different questions wearing one name.
--
-- Gating that single variable on the policy would therefore have made
-- switching OFF a reason requirement ALSO change status semantics --
-- quotes with live orders would start flipping to 'revised'. Silent,
-- and nothing in the UI would report it.
--
-- So: v_has_order keeps the status decision, and the policy narrows only
-- the reason gate. With no policy row the default is TRUE and
-- v_reason_required = v_has_order, i.e. exactly today's behaviour. The
-- postflight asserts BOTH halves, because a test that only shows the
-- gate opening would not notice the status moving with it.
--
-- WHY THIS GATE NEEDS NO SEPARATE ESCAPE (CLAUDE.md rule 7): the gate IS
-- a mandatory reason, and turning it off is the escape. That switch
-- writes an app_settings row, which trg_audit_app_settings records with
-- old and new value -- so the escape is durable and attributable by
-- construction. Rule 7 is satisfied without a second mechanism.
--
-- SERVER-SIDE (rule 6): the gate lives in revise_quote, which is the
-- only writer of quote_versions and the chokepoint for a revision. It
-- is not a UI preference and is not enforced in Dart.
--
-- CREATE OR REPLACE is correct here: the signature and return type are
-- unchanged, so no DROP is needed. SECURITY INVOKER is preserved --
-- asserted in postflight, because a silent flip to DEFINER would bypass
-- the org and branch isolation this function relies on.
-- ---------------------------------------------------------------------
create or replace function public.revise_quote(
  p_quote_id text, p_snapshot jsonb, p_reason text default null)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_q               quotations%rowtype;
  v_prev_snapshot   jsonb;
  v_prev_version    int;
  v_next_version    int;
  v_changed         text[];
  v_summary         text;
  v_has_order       boolean;
  v_reason_required boolean;
  v_actor           text;
  v_old_total       numeric;
  v_new_total       numeric;
begin
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

  -- STATUS decision. Not policy-gated, and must never become so.
  v_has_order := exists (
    select 1 from orders o
     where o.quotation_id = v_q.id
       and o.deleted_at is null
       and coalesce(o.status, '') <> 'cancelled'
  );

  -- REASON gate. Policy-gated, default ON, so an org with no policy row
  -- behaves exactly as before this migration.
  v_reason_required := v_has_order
    and public.org_policy_bool(
          v_q.org_id, 'revision_reason_required_after_confirm', true);

  if v_reason_required and (p_reason is null or btrim(p_reason) = '') then
    raise exception
      'This quote already has an order against it, so a revision needs a '
      'reason. Say what changed and why.'
      using errcode = 'P0001';
  end if;

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
    v_actor := null;
  end;

  insert into quote_versions
    (org_id, quote_id, version, snapshot, change_summary,
     changed_fields, total_amount, created_by)
  values
    (v_q.org_id, v_q.id, v_next_version, p_snapshot,
     case when p_reason is null or btrim(p_reason) = ''
          then v_summary
          else v_summary || ' -- ' || btrim(p_reason) end,
     coalesce(v_changed, '{}'::text[]), v_new_total, v_actor);

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
    -- v_has_order, NOT v_reason_required. See the comment above.
    status          = case when v_has_order then quotations.status
                           else 'revised' end,
    version         = v_next_version
  where id = v_q.id;

  return jsonb_build_object(
    'ok',              true,
    'quote_id',        v_q.id,
    'version',         v_next_version,
    'changed_fields',  coalesce(v_changed, '{}'::text[]),
    'change_summary',  v_summary,
    'reason_required', v_reason_required,
    'has_order',       v_has_order,
    'status',          (select q2.status from quotations q2 where q2.id = v_q.id)
  );
end;
$function$;

-- ---------------------------------------------------------------------
-- POSTFLIGHT
--
-- Structural where structure is the claim, BEHAVIOURAL where behaviour
-- is. Everything a probe writes is unwound by a sentinel raise inside a
-- subtransaction, and the whole migration is one transaction, so a
-- failed assertion leaves the database exactly as it was.
--
-- Each probe asserts its own PRECONDITION before probing. A check that
-- cannot reach its own raise passes having tested nothing, which is how
-- a migration written to enforce something can ship enforcing nothing.
-- ---------------------------------------------------------------------
do $$
declare
  v_org        uuid;
  v_owner      uuid;
  v_member     uuid := '00000000-0000-0000-0000-00000000dead';
  v_qid        text;
  v_name       text;
  v_prosecdef  boolean;
  v_n          int;
  v_ok         boolean := false;
  v_policy_before int;
  v_policy_after  int;
  v_member_wrote  boolean := false;
  v_owner_wrote   boolean := false;
  v_member_reads  int;
  v_absent     boolean;
  v_present    boolean;
  v_other_org  uuid;
  v_num        numeric;
  v_status_before text;
  v_status_after  text;
  v_raised_on   boolean := false;
  v_raised_off  boolean := false;
  v_res        jsonb;
begin
  -- Counted BEFORE anything is probed, so the "nothing seeded" check
  -- below compares rather than assuming zero. Asserting `count = 0`
  -- would be correct today and would refuse a correct re-run the moment
  -- one tenant has set one policy.
  select count(*) into v_policy_before
    from public.app_settings where category = 'policy';

  -- === 1. STRUCTURE =================================================
  -- The FOR ALL policy is gone and exactly four command-scoped ones
  -- replace it. This reads FALSE before and TRUE after.
  if exists (select 1 from pg_policy
              where polrelid = 'public.app_settings'::regclass
                and polcmd = '*') then
    raise exception 'a FOR ALL policy still exists on app_settings.';
  end if;
  select count(*) into v_n from pg_policy
   where polrelid = 'public.app_settings'::regclass;
  if v_n <> 4 then
    raise exception
      'expected exactly 4 policies on app_settings, found %.', v_n;
  end if;
  foreach v_name in array array['app_settings_select','app_settings_insert',
                                'app_settings_update','app_settings_delete'] loop
    if not exists (select 1 from pg_policy
                    where polrelid = 'public.app_settings'::regclass
                      and polname = v_name) then
      raise exception 'policy % is missing.', v_name;
    end if;
  end loop;
  -- Every WRITE policy must actually name the owner check. A policy
  -- that merely exists proves nothing about what it enforces.
  for v_name in
    select polname from pg_policy
     where polrelid = 'public.app_settings'::regclass and polcmd <> 'r'
  loop
    if position('is_org_owner' in coalesce(
         (select coalesce(pg_get_expr(polqual, polrelid), '') ||
                 coalesce(pg_get_expr(polwithcheck, polrelid), '')
            from pg_policy
           where polrelid = 'public.app_settings'::regclass
             and polname = v_name), '')) = 0 then
      raise exception '% does not check is_org_owner.', v_name;
    end if;
  end loop;

  -- revise_quote must still be SECURITY INVOKER. A silent flip to
  -- DEFINER would bypass org and branch isolation.
  select p.prosecdef into v_prosecdef
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'revise_quote';
  if v_prosecdef is null then
    raise exception 'revise_quote() is missing after replace.';
  end if;
  if v_prosecdef then
    raise exception
      'revise_quote() became SECURITY DEFINER; it must run as the caller '
      'so org_isolation and branch_isolation apply.';
  end if;

  -- PUBLIC must not hold EXECUTE on the readers. aclexplode, because a
  -- LIKE over the printed ACL is wrong in both directions: it raises on
  -- `authenticated=X/postgres` (correct) and misses `=X/postgres`
  -- (PUBLIC actually holding EXECUTE). Grantee 0 is PUBLIC.
  for v_name in
    select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('org_policy','org_policy_bool','org_policy_num')
  loop
    if exists (
      select 1 from pg_proc p
      cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
      join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_name
         and g.grantee = 0 and g.privilege_type = 'EXECUTE'
    ) then
      raise exception 'PUBLIC still holds EXECUTE on %.', v_name;
    end if;
  end loop;

  -- === 2. THE STORE, BEHAVIOURALLY ==================================
  -- PRECONDITION: an org with an owner. org_members holds only owners
  -- today, so the non-owner member is CONSTRUCTED -- otherwise this
  -- probe would find nobody and pass having tested nothing.
  select om.org_id, om.user_id into v_org, v_owner
    from public.org_members om where om.role = 'owner' limit 1;
  if v_org is null then
    raise exception
      'no org owner exists; the write-policy probe cannot be run, and a '
      'gate that has not been proven must not be reported as installed.';
  end if;

  begin
    insert into public.org_members (org_id, user_id, role)
    values (v_org, v_member, 'staff');

    -- (a) the constructed NON-OWNER MEMBER: can still read, cannot write
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_member::text, 'role','authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_member_reads from public.app_settings;
    begin
      insert into public.app_settings (org_id, category, key, value)
      values (v_org, 'policy', '__probe_member__', 'true'::jsonb);
      v_member_wrote := true;
    exception when others then
      v_member_wrote := false;
    end;
    reset role;

    -- (b) the OWNER: must still be able to write. Without this half, a
    -- policy set that refuses EVERYONE would pass (a) perfectly.
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_owner::text, 'role','authenticated')::text, true);
    set local role authenticated;
    begin
      insert into public.app_settings (org_id, category, key, value)
      values (v_org, 'policy', '__probe_owner__', 'true'::jsonb);
      v_owner_wrote := true;
    exception when others then
      v_owner_wrote := false;
    end;
    reset role;

    if v_member_wrote then
      raise exception
        'a non-owner org member WROTE a policy row; the gate is decorative.';
    end if;
    if not v_owner_wrote then
      raise exception
        'the org OWNER could not write a policy row; the new policies '
        'refuse everyone, which passes the denial check and breaks the '
        'product.';
    end if;
    if v_member_reads = 0 then
      raise exception
        'a non-owner org member can no longer READ app_settings; document '
        'boilerplate would vanish from every staff session.';
    end if;

    -- === 3. THE READER ==============================================
    -- Absent means default, in BOTH directions -- a reader that always
    -- returned its default would pass a one-sided test.
    v_absent := public.org_policy_bool(v_org, '__no_such_policy__', true);
    if not v_absent then
      raise exception 'org_policy_bool ignored a TRUE default when absent.';
    end if;
    if public.org_policy_bool(v_org, '__no_such_policy__', false) then
      raise exception 'org_policy_bool ignored a FALSE default when absent.';
    end if;

    insert into public.app_settings (org_id, category, key, value)
    values (v_org, 'policy', '__probe_read__', 'false'::jsonb);
    v_present := public.org_policy_bool(v_org, '__probe_read__', true);
    if v_present then
      raise exception
        'org_policy_bool returned the default over a stored value.';
    end if;

    -- A stored value must not leak across orgs.
    select id into v_other_org from public.organizations
     where id <> v_org limit 1;
    if v_other_org is not null then
      -- The stored value is FALSE for v_org. Read against another org it
      -- must return the DEFAULT (true).
      -- WHAT THIS PROVES, precisely: the FUNCTION'S OWN org filter. This
      -- runs as the migration's role, which bypasses RLS, so it is not a
      -- test of org_isolation -- that is proven separately by the member
      -- probe above, which runs under `set local role authenticated`.
      -- Both matter: RLS is the backstop, and a function that ignored
      -- p_org_id would read the wrong tenant's policy for a caller RLS
      -- was perfectly willing to admit.
      if not public.org_policy_bool(v_other_org, '__probe_read__', true) then
        raise exception 'org_policy_bool read another org''s policy value.';
      end if;
    end if;

    -- Numeric: absent is NULL, which is rule 4's "never seeded" state.
    v_num := public.org_policy_num(v_org, '__no_such_number__');
    if v_num is not null then
      raise exception 'org_policy_num invented a value for an absent key.';
    end if;

    -- === 4. THE GATE, BEHAVIOURALLY =================================
    select q.id, q.status into v_qid, v_status_before
      from public.quotations q
     where q.deleted_at is null
       and exists (select 1 from public.orders o
                    where o.quotation_id = q.id and o.deleted_at is null
                      and coalesce(o.status,'') <> 'cancelled')
     limit 1;
    if v_qid is null then
      raise exception
        'no quotation with a live order; the reason gate was not proven.';
    end if;

    -- (a) policy ABSENT -> default ON -> a reason is still required.
    begin
      v_res := public.revise_quote(v_qid, jsonb_build_object('total', 1), null);
    exception when others then
      v_raised_on := true;
    end;
    if not v_raised_on then
      raise exception
        'with no policy row the reason gate did not fire; the default is '
        'not ON and every existing org just lost the requirement.';
    end if;

    -- (b) policy OFF -> the same call succeeds...
    insert into public.app_settings (org_id, category, key, value)
    values ((select org_id from public.quotations where id = v_qid),
            'policy', 'revision_reason_required_after_confirm', 'false'::jsonb)
    on conflict (org_id, category, key) do update set value = 'false'::jsonb;

    begin
      v_res := public.revise_quote(v_qid, jsonb_build_object('total', 1), null);
    exception when others then
      v_raised_off := true;
    end;
    if v_raised_off then
      raise exception
        'the reason gate still fired with the policy switched OFF; the '
        'gate does not read the policy.';
    end if;

    -- ...and STATUS MUST NOT HAVE MOVED WITH IT. This is the assertion
    -- that catches the coupling: before the split, switching the reason
    -- policy off would also have flipped this quote to 'revised'.
    select status into v_status_after from public.quotations where id = v_qid;
    if v_status_after is distinct from v_status_before then
      raise exception
        'switching the reason policy OFF changed the quote status from % '
        'to % -- the status decision is still coupled to the reason gate.',
        v_status_before, v_status_after;
    end if;
    if (v_res ->> 'has_order') <> 'true' then
      raise exception 'has_order was not reported true for a quote with a live order.';
    end if;

    raise exception 'POLICY_PROBE_OK';
  exception
    when others then
      if sqlerrm <> 'POLICY_PROBE_OK' then
        raise;
      end if;
      v_ok := true;
  end;

  if not v_ok then
    raise exception 'the probe did not run to completion.';
  end if;

  -- === 5. NOTHING SURVIVED ==========================================
  select count(*) into v_policy_after
    from public.app_settings where category = 'policy';
  if v_policy_after <> v_policy_before then
    raise exception
      'policy rows went from % to % -- a probe row survived, or this '
      'migration seeded one. Absent means default; nothing may be seeded.',
      v_policy_before, v_policy_after;
  end if;
  if exists (select 1 from public.org_members where user_id = v_member) then
    raise exception 'the probe org_members row survived.';
  end if;

  raise notice
    'PART 4 installed: app_settings writes are owner-only (proven against '
    'a constructed non-owner member, and the owner proven still able to '
    'write), org_policy_bool/num are the single reader, and '
    'revision_reason_required_after_confirm gates the reason requirement '
    'with default ON. No policy row seeded. Status remains coupled to '
    'has_order, not to the policy.';
end $$;

commit;

-- =====================================================================
-- AFTER THIS RUNS
-- ---------------------------------------------------------------------
-- Nothing changes for any tenant until an owner writes a policy row.
-- That is the design, not an omission.
--
--   -- switch the reason requirement off for one org
--   insert into app_settings (org_id, category, key, value)
--   values ('<org>', 'policy',
--           'revision_reason_required_after_confirm', 'false'::jsonb)
--   on conflict (org_id, category, key) do update set value = excluded.value;
--
-- The change is recorded by trg_audit_app_settings with old and new
-- value. Read it back with:
--
--   select entity_id, action, old_value->>'value' as was,
--          new_value->>'value' as now, actor, created_at
--     from audit_log
--    where entity_type = 'app_settings'
--    order by created_at desc limit 20;
--
-- STILL OWED, and deliberately not in this file
--   * A Settings screen for policy. Until one exists a policy can only be
--     set with SQL, which is fine for a first gate and is not fine for
--     the advance gate.
--   * The advance gate (require_advance_to_confirm +
--     minimum_advance_pct). It compares paid_total against a percentage
--     of the revenue base, and orders.advance_paid must be retired
--     first -- see the note below.
--   * PART 3 step 2, widening audit_row to orders and payment_entries.
--     That is also the measurement the retention decision needs; do not
--     pick a retention number before it.
--
-- orders.advance_paid -- COUNTED 15 SEPT 2026, AND THERE IS A LIVE BUG
--   8 orders exist. advance_paid is 0 on ALL of them; paid_total is
--   non-zero on 1. accounts_page_widget.dart:171 does
--   `collections += advancePaid`, so the Daily Accounts Register reports
--   Rs0 collected for the only order that has actually been paid. The
--   column carries no data, so retiring it costs no migration of values
--   -- only the eight read sites.
-- =====================================================================
