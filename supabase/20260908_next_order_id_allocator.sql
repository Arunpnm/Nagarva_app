-- Order ids move off the client and into the same allocator every other
-- number in this product already uses.
--
-- `settings.order_id_seq` was read-modify-write from the device: READ the
-- counter, add one in Dart, UPSERT it back, across two network round
-- trips with no lock. Five copies of that code existed. Two devices
-- allocating at once both read 1001, both write 1002, and both return
-- the same id — the second `orders` INSERT then fails on the primary key
-- and that person loses their order.
--
-- ==========================================================================
-- SECURITY INVOKER, MATCHING next_doc_number — NOT definer
-- ==========================================================================
--
-- Introspected before writing (`prosecdef = false` on both
-- next_doc_number and next_lr_number): they are SECURITY INVOKER and lean
-- on the caller's RLS over `number_series`. This function does the same.
--
-- That is not merely consistency, it is the safer half of the trade: as
-- INVOKER the org_isolation policy applies to the caller, so a session
-- can only ever lock and increment a counter belonging to an org it is a
-- member of. A DEFINER version would run as the owner, bypass that
-- policy, and make `p_org` a parameter any caller could point at any
-- tenant — turning an argument into a cross-tenant write. Nothing here
-- needs definer, so nothing here gets it.
--
-- Granted to `authenticated` ONLY. Note that PostgreSQL grants EXECUTE to
-- PUBLIC by default on CREATE FUNCTION, so the REVOKE below is load
-- bearing, not decoration — without it this would be anon-callable the
-- moment it was created.
--
-- ==========================================================================
-- THE PREFIX DOES NOT FIT number_series.prefix, AND THAT IS DELIBERATE
-- ==========================================================================
--
-- `number_series_prefix_format` caps prefix at 12 characters
-- (`^[A-Za-z0-9/-]{1,12}$`). Live order ids carry a 26-character prefix:
-- `ARUN-PACKERS-AND-COURIERS-1001`. `APC-COIMBATORE-` is 15. Neither
-- fits, and widening the CHECK is the wrong fix — that cap exists to keep
-- GST document numbers inside Rule 46's 16-character limit, and loosening
-- it globally would weaken that guarantee for invoice and receipt rows to
-- solve an order-id problem. An order id is an internal reference, not a
-- tax document, and is not bound by that limit.
--
-- So for `doc_type = 'order'` the printed prefix is derived from
-- `organizations.slug`, exactly as the Dart it replaces did
-- (`currentOrgSlug.toUpperCase()`), and the counter row's own `prefix`
-- column is set to a marker that is NOT used in the output. The
-- postflight asserts the composed format so the two cannot drift.
--
-- **Existing id format is preserved byte-for-byte.** If you would rather
-- order ids became short (`APC-1003`) so the prefix could live in the
-- column like every other doc type, that is a product decision and a
-- different migration — it would leave historical ids in one shape and
-- new ones in another.
--
-- ==========================================================================
-- SEEDING IS THE DANGEROUS PART
-- ==========================================================================
--
-- `orders.id` is TEXT and is the PRIMARY KEY. A counter seeded below an
-- existing order sets up a collision that is invisible until an INSERT
-- fails. So each org seeds from GREATEST(settings value, max existing
-- order suffix, 1000) — never from the settings value alone.
--
-- Two details that would each be a silent bug:
--   * `settings.value` is jsonb holding a SCALAR STRING ("1001"), so it
--     needs `#>> '{}'` extraction. `value::int` on a jsonb string raises;
--     reading it as text would give `"1001"` WITH the quotes.
--   * Soft-deleted orders are NOT excluded. `deleted_at` does not release
--     the primary key, so a deleted `APC-1005` still makes 1005
--     unusable.

begin;

-- ==========================================================================
-- PREFLIGHT — raises, never skips
-- ==========================================================================
do $pre$
declare
  v_bad text;
begin
  if to_regclass('public.number_series') is null then
    raise exception 'PREFLIGHT: public.number_series is missing.';
  end if;
  if to_regprocedure('public.next_doc_number(uuid,text,text,text)') is null then
    raise exception
      'PREFLIGHT: next_doc_number is missing - this migration reuses its counter table and locking shape.';
  end if;

  -- Reusing the existing mechanism means matching its security model. If
  -- next_doc_number ever becomes DEFINER, this file's reasoning needs
  -- revisiting rather than silently diverging.
  if (select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='next_doc_number') then
    raise exception
      'PREFLIGHT: next_doc_number is now SECURITY DEFINER. Stop and re-decide the model for orders.';
  end if;

  if to_regprocedure('public.next_order_id(uuid)') is not null then
    raise exception 'PREFLIGHT: next_order_id already exists - this migration has already run.';
  end if;

  -- Every org needs a slug, because the printed id is built from it.
  -- Seeding a counter for an org that cannot produce an id would leave a
  -- row that only fails at allocation time.
  select string_agg(name, ', ') into v_bad
    from public.organizations
   where coalesce(nullif(trim(slug), ''), '') = '';
  if v_bad is not null then
    raise exception
      'PREFLIGHT: org(s) with no slug: %. An order id cannot be composed without one.', v_bad;
  end if;

  -- Two orgs whose uppercased slug is identical would share an id space.
  select string_agg(upper(slug), ', ') into v_bad
    from (select slug from public.organizations
           group by upper(slug) having count(*) > 1) x;
  if v_bad is not null then
    raise exception 'PREFLIGHT: orgs share an uppercased slug: %.', v_bad;
  end if;

  if exists (select 1 from public.number_series where doc_type = 'order') then
    raise exception
      'PREFLIGHT: number_series already holds doc_type=order rows. Inspect them before seeding.';
  end if;
end
$pre$;

-- ==========================================================================
-- SEED — one counter per org, at or above every id already issued
-- ==========================================================================
insert into public.number_series (org_id, doc_type, branch, fy, prefix, padding, suffix, last_number, active)
select
  o.id,
  'order',
  null,           -- org-wide, matching the 12 Aug numbering decision
  null,           -- order ids are not FY-scoped
  'ORD-',         -- NOT used in the output; see the header. The CHECK
                  -- requires a non-null 1-12 char value.
  4,
  null,
  greatest(
    -- the client-side counter, if it holds a plain integer
    coalesce((select (s.value #>> '{}')::bigint
                from public.settings s
               where s.org_id = o.id
                 and s.key = 'order_id_seq'
                 and (s.value #>> '{}') ~ '^[0-9]+$'), 1000),
    -- and the highest suffix actually issued, DELETED ROWS INCLUDED
    coalesce((select max((substring(ord.id from '([0-9]+)$'))::bigint)
                from public.orders ord
               where ord.org_id = o.id
                 and ord.id ~ '[0-9]+$'), 1000),
    1000
  ),
  true
from public.organizations o;

-- ==========================================================================
-- THE ALLOCATOR
-- ==========================================================================
-- Same shape as next_doc_number: SELECT ... FOR UPDATE, increment, UPDATE.
-- The row lock is what the Dart version never had — a second caller
-- blocks here until the first commits, then reads the incremented value.
create or replace function public.next_order_id(p_org uuid)
returns text
language plpgsql
volatile
as $function$
declare
  rec  record;
  n    bigint;
  slug text;
begin
  select * into rec
    from number_series
   where org_id = p_org
     and doc_type = 'order'
     and branch is null
     and fy is null
     and active
   for update;

  if not found then
    raise exception
      'No active order-id series configured for org=%. Seed number_series (doc_type=order) before creating orders.',
      p_org
      using errcode = 'P0001';
  end if;

  -- Read under the same RLS as the counter. An org the caller cannot see
  -- would already have failed the FOR UPDATE above.
  select upper(o.slug) into slug from organizations o where o.id = p_org;

  if coalesce(slug, '') = '' then
    raise exception
      'Org % has no slug, so an order id cannot be composed. Set organizations.slug.', p_org
      using errcode = 'P0001';
  end if;

  n := rec.last_number + 1;
  update number_series set last_number = n where id = rec.id;

  -- Byte-identical to the Dart this replaces: '<SLUG>-<n>'. lpad with
  -- padding 4 is a no-op for every value at or above 1000, which the
  -- seeding guarantees.
  return slug || '-' || lpad(n::text, coalesce(rec.padding, 4), '0');
end;
$function$;

-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. This revoke is the
-- control, not a formality.
revoke all on function public.next_order_id(uuid) from public;
revoke all on function public.next_order_id(uuid) from anon;
grant execute on function public.next_order_id(uuid) to authenticated;

-- ==========================================================================
-- POSTFLIGHT — assertions, inside the transaction
-- ==========================================================================
do $post$
declare
  v_orgs      bigint;
  v_counters  bigint;
  v_bad       text;
  v_test_org  uuid;
  v_seed      bigint;
  v_a         text;
  v_b         text;
begin
  -- 1. A counter for every org.
  select count(*) into v_orgs     from public.organizations;
  select count(*) into v_counters from public.number_series where doc_type='order';
  if v_orgs <> v_counters then
    raise exception 'POSTFLIGHT: % orgs but % order counters.', v_orgs, v_counters;
  end if;

  -- 2. No counter sits below an id already issued. This is the assertion
  --    that prevents a primary-key collision on the first new order.
  select string_agg(format('%s (counter %s < issued %s)', o.name, ns.last_number, mx.hi), '; ')
    into v_bad
    from public.organizations o
    join public.number_series ns
      on ns.org_id = o.id and ns.doc_type = 'order'
    join lateral (
      select coalesce(max((substring(ord.id from '([0-9]+)$'))::bigint), 0) as hi
        from public.orders ord
       where ord.org_id = o.id and ord.id ~ '[0-9]+$'
    ) mx on true
   where ns.last_number < mx.hi;

  if v_bad is not null then
    raise exception 'POSTFLIGHT: counter seeded below an issued order id: %', v_bad;
  end if;

  -- 3. Two successive calls must differ. Run against a real org, then
  --    restore the counter so the assertion does not burn two ids.
  select org_id, last_number into v_test_org, v_seed
    from public.number_series where doc_type='order' order by org_id limit 1;

  v_a := public.next_order_id(v_test_org);
  v_b := public.next_order_id(v_test_org);

  if v_a = v_b then
    raise exception 'POSTFLIGHT: two calls returned the same id (%). The allocator does not increment.', v_a;
  end if;
  if v_b <> (select upper(o.slug) from public.organizations o where o.id = v_test_org)
              || '-' || lpad((v_seed + 2)::text, 4, '0') then
    raise exception
      'POSTFLIGHT: composed id % does not match <SLUG>-<counter>.', v_b;
  end if;

  update public.number_series set last_number = v_seed
   where org_id = v_test_org and doc_type = 'order';

  -- 4. Security model: invoker, and unreachable by anon or PUBLIC.
  if (select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='next_order_id') then
    raise exception 'POSTFLIGHT: next_order_id is SECURITY DEFINER. It must be INVOKER.';
  end if;

  if has_function_privilege('anon', 'public.next_order_id(uuid)', 'execute') then
    raise exception 'POSTFLIGHT: anon can execute next_order_id.';
  end if;

  if exists (
    select 1 from aclexplode((select proacl from pg_proc p
                                join pg_namespace n on n.oid=p.pronamespace
                               where n.nspname='public' and p.proname='next_order_id')) a
     where a.grantee = 0)          -- 0 = PUBLIC
  then
    raise exception 'POSTFLIGHT: next_order_id is still granted to PUBLIC.';
  end if;

  if not has_function_privilege('authenticated', 'public.next_order_id(uuid)', 'execute') then
    raise exception 'POSTFLIGHT: authenticated cannot execute next_order_id.';
  end if;
end
$post$;

commit;

-- AFTER RUNNING: set kServerSideOrderIds = true in
-- lib/config/app_config.dart and ship a build.
--
-- settings.order_id_seq rows are deliberately LEFT IN PLACE as seed
-- evidence. Clear them once the new allocator has minted a number in
-- every org.

-- ==========================================================================
-- ROLLBACK
-- ==========================================================================
-- begin;
--   drop function if exists public.next_order_id(uuid);
--   delete from public.number_series where doc_type = 'order';
-- commit;
