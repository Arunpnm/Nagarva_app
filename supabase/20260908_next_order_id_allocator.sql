-- Order ids move off the client and into the same allocator every other
-- number in this product already uses — plus two structural fixes to
-- `number_series` that Arun found in review and that matter more than
-- the feature.
--
-- `settings.order_id_seq` was read-modify-write from the device: READ the
-- counter, add one in Dart, UPSERT it back, across two network round
-- trips with no lock. Five copies of that code existed. Two devices
-- allocating at once both read 1001, both write 1002, and both return
-- the same id — the second `orders` INSERT then fails on the primary key
-- and that person loses their order.
--
-- ==========================================================================
-- BLOCKER A — number_series has no unique constraint on the series key
-- ==========================================================================
--
-- Only PRIMARY KEY (id) on a uuid, the prefix CHECK, and the branch FK.
-- Nothing stops two rows sharing (org_id, doc_type, branch, fy), and
-- `next_doc_number`'s `SELECT ... FOR UPDATE ... INTO` would then pick
-- one arbitrarily — repeating or regressing numbers in a series Rule
-- 46(b) requires to be consecutive. **That is a live invoice exposure
-- today, not a risk introduced by the order counter.**
--
-- It also defeated this file's own first postflight, which asserted a
-- counter row EXISTS per org. Two rows pass that. It now asserts exactly
-- one.
--
-- **Why a coalesce expression index and not `NULLS NOT DISTINCT`.** The
-- server is PostgreSQL 17.6, so both are available — but they do not mean
-- the same thing here. `next_doc_number` matches with
-- `coalesce(branch,'') = coalesce(p_branch,'')`, so a row with
-- `branch = NULL` and a row with `branch = ''` BOTH match one lookup and
-- the arbitrary pick is back. `NULLS NOT DISTINCT` would happily permit
-- that pair. The expression index mirrors the function's own matching
-- semantics exactly, which is the property that actually prevents the
-- bug. Same argument for `fy`.
--
-- The index deliberately covers ALL rows, not just `active` ones. A
-- partial `where active` index would allow a duplicate to sit dormant and
-- become live the moment somebody reactivated it — silently. Consequence
-- worth knowing: retiring a series and replacing it means UPDATING the
-- row, not inserting a second one. That is already the established
-- pattern (see `20260902_doc_prefix_identity.sql`, where prefix changes
-- are updates guarded on `last_number = 0`).
--
-- Bonus, and not incidental: the planned `roll_over_number_series` (see
-- CLAUDE.md's March 2027 section) specifies `ON CONFLICT DO NOTHING`,
-- which needs a unique index to have anything to conflict on. This
-- supplies it.
--
-- ==========================================================================
-- BLOCKER B — order ids are NOT financial-year scoped, deliberately
-- ==========================================================================
--
-- Every existing `number_series` row is `fy = '2026-27'`. Order ids carry
-- no year at all: `ARUN-PACKERS-AND-COURIERS-1002`, `APC-BENGALURU-1001`.
-- They are one continuous sequence.
--
-- Seeding the order counter with `fy = '2026-27'` to match its
-- neighbours would turn the known March 2027 rollover into a
-- **core-workflow outage** rather than a document-numbering one. On
-- 1 April 2027 either the lookup finds nothing and raises P0001 — so
-- nobody can create an ORDER, not merely an invoice — or a fresh row
-- starts at zero and every insert collides with `orders.id`, which is the
-- primary key.
--
-- So the order row is seeded `fy = NULL` and `next_order_id` matches on
-- `fy IS NULL`. It does NOT reuse `next_doc_number`'s FY lookup. The
-- postflight asserts the NULL, and the function carries a comment saying
-- this is intentional — so the 2027 rollover work does not "fix" it by
-- adding a year.
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
-- tenant — turning an argument into a cross-tenant write.
--
-- Granted to `authenticated` ONLY. PostgreSQL grants EXECUTE to PUBLIC by
-- default on CREATE FUNCTION, so the REVOKE below is load bearing, not
-- decoration.
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
-- `organizations.slug`, exactly as the Dart it replaces did. The CHECK
-- still requires a non-null prefix, so the row carries the literal
-- `ORD-` — see the seeding comment for what that value does and does not
-- mean.
--
-- **Existing id format is preserved byte-for-byte.**

begin;

-- ==========================================================================
-- PREFLIGHT — raises, never skips
-- ==========================================================================
do $pre$
declare
  v_bad text;
  v_dupes bigint;
begin
  if to_regclass('public.number_series') is null then
    raise exception 'PREFLIGHT: public.number_series is missing.';
  end if;
  if to_regprocedure('public.next_doc_number(uuid,text,text,text)') is null then
    raise exception
      'PREFLIGHT: next_doc_number is missing - this migration reuses its counter table and locking shape.';
  end if;
  if to_regprocedure('public.next_lr_number(uuid,text,text)') is null then
    raise exception 'PREFLIGHT: next_lr_number is missing - the revoke below targets it.';
  end if;

  -- Reusing the existing mechanism means matching its security model.
  if (select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='next_doc_number') then
    raise exception
      'PREFLIGHT: next_doc_number is now SECURITY DEFINER. Stop and re-decide the model for orders.';
  end if;

  if to_regprocedure('public.next_order_id(uuid)') is not null then
    raise exception 'PREFLIGHT: next_order_id already exists - this migration has already run.';
  end if;

  -- BLOCKER A: the unique index cannot be created over existing
  -- duplicates. Fail HERE naming them, rather than erroring out
  -- mid-migration on an index build with an opaque message.
  select count(*) into v_dupes from (
    select 1 from public.number_series
     group by org_id, doc_type, coalesce(branch,''), coalesce(fy,'')
    having count(*) > 1) d;

  if v_dupes > 0 then
    -- Grouped by EXACTLY the expression the count and the index use:
    -- coalesce(x,''). Grouping by the raw columns would split a NULL row
    -- and an empty-string row apart, and grouping by any other sentinel
    -- (say coalesce(x,'(null)')) would not collapse that pair either — so
    -- the message would report nothing about precisely the duplicate the
    -- count just found, and raise with an empty list.
    select string_agg(format('%s / %s / branch=%L / fy=%L x%s',
                             org_id, doc_type, b, f, n), '; ')
      into v_bad
      from (select org_id, doc_type,
                   coalesce(branch,'') as b,
                   coalesce(fy,'')     as f,
                   count(*)            as n
              from public.number_series
             group by org_id, doc_type, coalesce(branch,''), coalesce(fy,'')
            having count(*) > 1) x;
    raise exception
      'PREFLIGHT: % duplicate series key(s) already exist and must be merged by hand first: %. Two rows for one key means next_doc_number picks arbitrarily, which is how an invoice number repeats.',
      v_dupes, v_bad;
  end if;

  -- Every org needs a slug, because the printed id is built from it.
  select string_agg(name, ', ') into v_bad
    from public.organizations
   where coalesce(nullif(trim(slug), ''), '') = '';
  if v_bad is not null then
    raise exception
      'PREFLIGHT: org(s) with no slug: %. An order id cannot be composed without one.', v_bad;
  end if;

  -- Two orgs whose uppercased slug is identical would share an id space.
  --
  -- The subquery selects the GROUPED EXPRESSION, not the raw column.
  -- Written as `select slug ... group by upper(slug)` this raises 42803
  -- ("column organizations.slug must appear in the GROUP BY clause"),
  -- which aborts the whole migration in preflight — the run Arun saw
  -- fail on 8 Sept 2026.
  select string_agg(u, ', ') into v_bad
    from (select upper(slug) as u
            from public.organizations
           group by upper(slug)
          having count(*) > 1) x;
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
-- BLOCKER A — one row per series key, enforced
-- ==========================================================================
create unique index if not exists number_series_key_uniq
  on public.number_series (org_id, doc_type, coalesce(branch, ''), coalesce(fy, ''));

comment on index public.number_series_key_uniq is
  $c$One counter per (org, doc_type, branch, fy). Uses coalesce(x,'')
rather than NULLS NOT DISTINCT because next_doc_number matches with
coalesce(branch,'') = coalesce(p_branch,'') — so a NULL row and an
empty-string row both match one lookup, and the allocator would pick
between them arbitrarily. NULLS NOT DISTINCT permits exactly that pair;
this index does not. A duplicate here repeats or regresses a series
Rule 46(b) requires to be consecutive.$c$;

-- ==========================================================================
-- SEED — one counter per org, at or above every id already issued
-- ==========================================================================
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
--     the primary key, so a deleted `APC-1005` still makes 1005 unusable.
insert into public.number_series (org_id, doc_type, branch, fy, prefix, padding, suffix, last_number, active)
select
  o.id,
  'order',
  null,           -- org-wide, matching the 12 Aug numbering decision
  -- BLOCKER B: NULL, not '2026-27'. Order ids are one continuous
  -- sequence with no year in them. An FY here would break order creation
  -- outright on 1 April 2027. See the header.
  null,
  -- NOT the printed prefix, and nothing should display it as one. The
  -- CHECK requires a non-null 1-12 char value and the real prefix
  -- (`ARUN-PACKERS-AND-COURIERS-`) does not fit, so the printed prefix is
  -- derived from organizations.slug inside next_order_id instead. A
  -- future number-series settings screen must special-case doc_type
  -- 'order' and show the slug, not this column.
  'ORD-',
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
  -- `fy is null` IS THE CONTRACT, not an oversight.
  --
  -- Order ids are deliberately NOT financial-year scoped: they carry no
  -- year (`APC-1002`) and run as one continuous sequence. Every other
  -- doc_type in number_series is fy-scoped, so this looks like an
  -- omission and is not.
  --
  -- DO NOT "fix" this during the March 2027 FY rollover work by adding an
  -- fy match or cloning this row into '2027-28'. Doing so breaks ORDER
  -- CREATION on 1 April 2027 — either P0001 with no matching row, or a
  -- fresh counter at zero whose every insert collides with orders.id,
  -- which is the primary key. The rollover concerns documents, not
  -- orders.
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
      'No active order-id series configured for org=%. Seed number_series (doc_type=order, fy null) before creating orders.',
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

  -- Byte-identical to the Dart this replaces: '<SLUG>-<n>'. rec.prefix is
  -- deliberately NOT used — see the seeding comment. lpad with padding 4
  -- is a no-op for every value at or above 1000, which seeding guarantees.
  return slug || '-' || lpad(n::text, coalesce(rec.padding, 4), '0');
end;
$function$;

-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. This revoke is the
-- control, not a formality.
revoke all on function public.next_order_id(uuid) from public;
revoke all on function public.next_order_id(uuid) from anon;
grant execute on function public.next_order_id(uuid) to authenticated;

-- ==========================================================================
-- CLOSE THE SECOND PATH INTO THE ORDER COUNTER
-- ==========================================================================
-- Arun, 8 Sept 2026, reviewing the expression-index reasoning above and
-- following it one step further than I did.
--
-- The same `coalesce(fy,'') = coalesce(p_fy,'')` matching that justified
-- the expression index ALSO opens a second door. `p_branch` and `p_fy`
-- both default to NULL, and the order row is seeded branch NULL / fy
-- NULL — so `next_doc_number(org, 'order')` matches it exactly, takes the
-- same row lock, advances `last_number`, and returns
-- `coalesce(prefix,'') || lpad(...)` = **`ORD-1003`**.
--
-- That is worse than a duplicate row: it hands back a DIFFERENT STRING
-- from the one `next_order_id` composes (`APC-1003`) while burning the
-- same counter, so the two paths disagree about what the id is *and*
-- about what the next one will be. Two callable paths to one counter is
-- precisely the shape this whole migration exists to remove.
--
-- The guard is a doc_type check rather than anything cleverer because
-- the collision is about IDENTITY, not arguments: an order id is not a
-- document number and must not be reachable through the document
-- allocator, whatever branch/fy are passed.
--
-- Verified before writing: the five live `next_doc_number` call sites
-- pass invoice, receipt, proforma, voucher and receipt. None passes
-- 'order', so this guard breaks nothing that exists.
--
-- The body below is reproduced verbatim from `pg_get_functiondef` with
-- ONLY the guard prepended — same signature, same return type, same
-- SECURITY INVOKER, no `SET search_path` added. `CREATE OR REPLACE`
-- preserves the existing ACL; the revokes that follow are what change it.
create or replace function public.next_doc_number(
  p_org uuid, p_doc_type text, p_branch text default null::text, p_fy text default null::text)
returns text
language plpgsql
as $ndn$
declare rec record; n int;
begin
  -- Order ids are NOT document numbers. See the header above.
  if p_doc_type = 'order' then
    raise exception
      'next_doc_number cannot allocate order ids. Use next_order_id(org) instead - it composes <SLUG>-<n> from organizations.slug, while this function would return the ORD- marker prefix and burn the same counter.'
      using errcode = 'P0001';
  end if;

  select * into rec from number_series
   where org_id = p_org and doc_type = p_doc_type
     and coalesce(branch,'') = coalesce(p_branch,'')
     and coalesce(fy,'') = coalesce(p_fy,'')
     and active
   for update;

  if not found then
    raise exception
      'No active number series configured for org=%, doc_type=%, branch=%, fy=%. '
      'Configure one in number_series (or reactivate an existing row) before '
      'generating this document.',
      p_org, p_doc_type, coalesce(p_branch, '<none>'), coalesce(p_fy, '<none>')
      using errcode = 'P0001';
  end if;

  n := rec.last_number + 1;
  update number_series set last_number = n where id = rec.id;

  return coalesce(rec.prefix,'') || lpad(n::text, coalesce(rec.padding,4), '0')
         || coalesce(rec.suffix,'');
end;
$ndn$;

-- ==========================================================================
-- Close the anon/PUBLIC grants on the two existing allocators
-- ==========================================================================
-- Arun, 8 Sept 2026, after the read-only analysis: RLS on number_series
-- does hold today — `current_org_ids()` returns no rows for anon, so the
-- FOR UPDATE matches nothing and the function raises before any UPDATE.
-- An anonymous caller cannot burn a document number.
--
-- But that leaves ONE policy as the only thing standing between anon and
-- a Rule 46(b) consecutive series. The grants look like the CREATE
-- FUNCTION default nobody revoked rather than a decision, and no
-- legitimate caller is anonymous: every document is issued from an
-- authenticated session. Removing them costs nothing and removes the
-- dependency.
revoke all on function public.next_doc_number(uuid,text,text,text) from public;
revoke all on function public.next_doc_number(uuid,text,text,text) from anon;
grant execute on function public.next_doc_number(uuid,text,text,text) to authenticated;

revoke all on function public.next_lr_number(uuid,text,text) from public;
revoke all on function public.next_lr_number(uuid,text,text) from anon;
grant execute on function public.next_lr_number(uuid,text,text) to authenticated;

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
  v_guarded   boolean := false;
  v_msg       text;
begin
  -- 1. EXACTLY ONE counter per org. The first version of this asserted
  --    only that a row EXISTS, which two rows also satisfy — the precise
  --    hole Blocker A describes.
  select count(*) into v_orgs from public.organizations;
  select count(*) into v_counters from public.number_series where doc_type='order';
  if v_orgs <> v_counters then
    raise exception 'POSTFLIGHT: % orgs but % order counters.', v_orgs, v_counters;
  end if;

  select string_agg(o.name, ', ') into v_bad
    from public.organizations o
   where (select count(*) from public.number_series ns
           where ns.org_id = o.id and ns.doc_type = 'order') <> 1;
  if v_bad is not null then
    raise exception 'POSTFLIGHT: org(s) without exactly one order counter: %', v_bad;
  end if;

  -- 2. BLOCKER A: the unique index exists and is unique.
  if not exists (select 1 from pg_class c join pg_index i on i.indexrelid = c.oid
                  where c.relname = 'number_series_key_uniq' and i.indisunique) then
    raise exception 'POSTFLIGHT: number_series_key_uniq is missing or not unique.';
  end if;

  -- 3. BLOCKER B: the order counter is NOT FY-scoped.
  if exists (select 1 from public.number_series
              where doc_type = 'order' and (fy is not null or branch is not null)) then
    raise exception
      'POSTFLIGHT: an order counter carries an fy or branch. Order ids are not FY-scoped - an fy here breaks order creation at the 2027 rollover.';
  end if;

  -- 3b. ACTIVE. `next_order_id` inherits next_doc_number's `and active`
  --     predicate, so a row seeded with active null or false would pass
  --     every other assertion here and then fail on the very first real
  --     allocation — at a vendor creating an order, not at review time.
  if exists (select 1 from public.number_series
              where doc_type = 'order' and coalesce(active, false) = false) then
    raise exception
      'POSTFLIGHT: an order counter is not active. next_order_id filters on `active`, so allocation would fail on the first call.';
  end if;

  -- 4. No counter sits below an id already issued.
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

  -- 5. Prefix budget. Already AT the 12-char ceiling (`BLR/2026-27/`), so
  --    there is no headroom — and the 2027-28 form must be CHECKED, not
  --    assumed to be the same length.
  select string_agg(format('%s (%s chars)', prefix, length(prefix)), ', ')
    into v_bad
    from public.number_series
   where length(prefix) > 12 or prefix !~ '^[A-Za-z0-9/-]{1,12}$';
  if v_bad is not null then
    raise exception 'POSTFLIGHT: prefix outside the 12-char CHECK: %', v_bad;
  end if;

  select string_agg(format('%s -> %s', prefix, replace(prefix, '2026-27', '2027-28')), ', ')
    into v_bad
    from public.number_series
   where prefix like '%2026-27%'
     and length(replace(prefix, '2026-27', '2027-28')) > 12;
  if v_bad is not null then
    raise exception
      'POSTFLIGHT: advancing the FY segment would exceed 12 chars: %. The 2027 rollover cannot reuse these prefixes.', v_bad;
  end if;

  -- 6. Two successive calls must differ. Run against a real org, then
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
    raise exception 'POSTFLIGHT: composed id % does not match <SLUG>-<counter>.', v_b;
  end if;

  update public.number_series set last_number = v_seed
   where org_id = v_test_org and doc_type = 'order';

  -- 6b. THE SECOND PATH IS CLOSED — proven by calling it, not by reading
  --     the function body. Run AFTER the increment test above, so a
  --     missing guard would be caught here rather than silently burning
  --     a number earlier in this block.
  --
  --     The flag matters: bare `raise exception` defaults to SQLSTATE
  --     P0001, so writing this as `perform ...; raise exception 'did not
  --     raise'; exception when sqlstate 'P0001' then null;` would CATCH
  --     ITS OWN failure raise and report success. The whole assertion
  --     would then pass in exactly the case it exists to detect.
  begin
    perform public.next_doc_number(v_test_org, 'order');
  exception
    when sqlstate 'P0001' then
      v_guarded := true;
      get stacked diagnostics v_msg = message_text;
  end;

  if not v_guarded then
    raise exception
      'POSTFLIGHT: next_doc_number(org, ''order'') did not raise. The second path into the order counter is still open - it would return the ORD- marker prefix and burn the same counter next_order_id uses.';
  end if;

  if position('next_order_id' in coalesce(v_msg, '')) = 0 then
    raise exception
      'POSTFLIGHT: the order guard raised but does not name next_order_id as the correct entry point. Message was: %', v_msg;
  end if;

  -- The guard raises before the SELECT ... FOR UPDATE, so nothing was
  -- locked or incremented. Re-assert the counter is still where step 6
  -- left it, rather than assuming.
  if (select last_number from public.number_series
       where org_id = v_test_org and doc_type = 'order') <> v_seed then
    raise exception
      'POSTFLIGHT: the order counter moved during the guard test - next_doc_number reached the row before raising.';
  end if;

  -- 7. Security model: invoker, and unreachable by anon or PUBLIC.
  if (select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.proname='next_order_id') then
    raise exception 'POSTFLIGHT: next_order_id is SECURITY DEFINER. It must be INVOKER.';
  end if;

  select string_agg(fn, ', ') into v_bad
    from (values
      ('public.next_order_id(uuid)'),
      ('public.next_doc_number(uuid,text,text,text)'),
      ('public.next_lr_number(uuid,text,text)')
    ) as t(fn)
   where has_function_privilege('anon', fn, 'execute')
      or exists (select 1 from aclexplode((select proacl from pg_proc
                                            where oid = to_regprocedure(fn)::oid)) a
                  where a.grantee = 0);      -- 0 = PUBLIC
  if v_bad is not null then
    raise exception 'POSTFLIGHT: still reachable by anon or PUBLIC: %', v_bad;
  end if;

  -- The revoke must remove ONLY anon and PUBLIC. `service_role` and the
  -- owner hold explicit grants today (checked before writing this), so
  -- the Edge Functions are unaffected — but asserting it is cheap, and
  -- if that reading were wrong the failure would be document generation
  -- stopping in production rather than a migration refusing to commit.
  select string_agg(format('%s/%s', role_name, fn), ', ') into v_bad
    from (values
      ('authenticated', 'public.next_order_id(uuid)'),
      ('authenticated', 'public.next_doc_number(uuid,text,text,text)'),
      ('authenticated', 'public.next_lr_number(uuid,text,text)'),
      ('service_role',  'public.next_doc_number(uuid,text,text,text)'),
      ('service_role',  'public.next_lr_number(uuid,text,text)')
    ) as t(role_name, fn)
   where not has_function_privilege(role_name, fn, 'execute');

  if v_bad is not null then
    raise exception
      'POSTFLIGHT: a legitimate caller lost execute on an allocator - document or order generation would stop: %',
      v_bad;
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
-- Note the grant restoration is deliberately NOT included: re-granting
-- anon/PUBLIC on next_doc_number and next_lr_number would undo a
-- security fix that stands on its own merits, independent of the order
-- allocator.
-- begin;
--   drop function if exists public.next_order_id(uuid);
--   delete from public.number_series where doc_type = 'order';
--   drop index if exists public.number_series_key_uniq;
-- commit;
