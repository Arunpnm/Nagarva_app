-- =====================================================================
-- SECURITY INVARIANT LINT -- read-only, raises on violation.
-- (15 Sept 2026)
--
-- WHY THIS FILE EXISTS, AND WHY IT IS NOT ANOTHER CLAUDE.md ENTRY.
--
-- Twice in one week a CLAUDE.md rule failed to stop the person who WROTE
-- it. Arun recorded the anon-vs-PUBLIC revoke trap in this project and
-- then issued an instruction to revoke from anon; the to_regproc
-- diagnosis went the same way days earlier. The entries were correct,
-- present, and findable. They did not fire, because a rule only helps if
-- somebody rereads it AT THE MOMENT OF THE DECISION, and at that moment
-- everyone is acting rather than reading.
--
-- So the lesson is not "write a better entry". It is: where an invariant
-- can be CHECKED, a check beats a paragraph. This file is the checkable
-- form of four rules already written down elsewhere.
--
-- HOW TO RUN: paste the whole file into the SQL editor. It reads
-- catalogues only -- no DDL, no DML, no function calls. It either prints
-- one OK notice or raises with every violation it found. Run it after
-- any migration that touches a function, a grant, a view or a table.
--
-- IT IS EXPECTED TO BE RED until 20260915_set_staff_pin_fail_open.sql is
-- applied: set_staff_pin trips checks 1 and 2 today. That is the point --
-- a lint that is green before and after a fix is not a check.
-- =====================================================================

do $$
declare
  v_findings text[] := '{}';
  r          record;

  -- Check 2's allow-list: SECURITY DEFINER functions that WRITE and are
  -- deliberately reachable by PUBLIC/anon. Each was reviewed; a name
  -- appearing here is a decision, not an oversight.
  --   is_invite_code_valid   -- pre-signup by design; writes only its own
  --                             per-IP rate-limit row; returns one bit.
  --   seed_org_*             -- ungated org bootstrap writers. Guarded
  --                             against an already-seeded org, so they
  --                             no-op on an established tenant. REPORTED
  --                             AS AN OPEN ITEM, not endorsed: they take
  --                             an org_id that resolve_org_by_slug hands
  --                             out to anyone. They want a membership
  --                             check; until then they sit here so a NEW
  --                             ungated writer is what this lint shouts
  --                             about.
  -- set_staff_pin is DELIBERATELY ABSENT -- it is being revoked.
  v_allowed_public_writers text[] := array[
    'is_invite_code_valid',
    'seed_org_default_branch',
    'seed_org_document_settings',
    'seed_org_lr_series',
    'seed_org_number_series'
  ];
begin

  -- -------------------------------------------------------------------
  -- CHECK 1 -- a guard that cannot fire.
  --
  -- `if not ( X or <col> = auth.uid() )` is UNKNOWN, not false, whenever
  -- <col> or auth.uid() is NULL -- and plpgsql does not take a NULL IF,
  -- so the raise is skipped and execution continues INTO the privileged
  -- body. Proven against set_staff_pin by calling it, 15 Sept 2026.
  --
  -- The fix is coalesce(<whole condition>, false). This check therefore
  -- looks for the shape WITHOUT a coalesce anywhere in the body. It is
  -- deliberately crude: a false positive costs one read, a false
  -- negative costs a credential.
  -- -------------------------------------------------------------------
  for r in
    select n.nspname || '.' || p.proname as fn
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~* 'if\s+not\s*\('
      and pg_get_functiondef(p.oid) ~* 'auth\.uid\(\)'
      and pg_get_functiondef(p.oid) !~* 'coalesce'
    order by 1
  loop
    v_findings := v_findings ||
      ('[1 FAIL-OPEN GUARD] ' || r.fn ||
       ' has an `if not (...)` guard mentioning auth.uid() and no coalesce. ' ||
       'If either side of a uid comparison can be NULL the guard cannot fire. ' ||
       'Wrap the WHOLE condition in coalesce(..., false) -- NOT `is not distinct from`, ' ||
       'which is TRUE when both sides are NULL and would authorise everyone.');
  end loop;

  -- -------------------------------------------------------------------
  -- CHECK 2 -- an unauthenticated caller can reach a SECURITY DEFINER
  -- function that writes.
  --
  -- PUBLIC is the grantee that matters. Every function is created with
  -- EXECUTE granted to PUBLIC, which shows in the ACL as `=X/owner`, and
  -- anon inherits it. A `revoke ... from anon` against such a function
  -- succeeds and changes nothing. 50 of 81 functions in public currently
  -- carry the PUBLIC grant, so this check is narrowed to the ones that
  -- are SECURITY DEFINER *and* write *and* are callable over PostgREST
  -- (trigger functions are excluded -- they cannot be invoked directly).
  -- -------------------------------------------------------------------
  for r in
    select p.proname as fn,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
      and p.prorettype <> 'trigger'::regtype
      and pg_get_functiondef(p.oid) ~* '(insert into|update\s+public\.|delete from)'
      and exists (
        select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        where a.privilege_type = 'EXECUTE' and a.grantee = 0   -- 0 = PUBLIC
      )
      and p.proname <> all (v_allowed_public_writers)
    order by 1
  loop
    v_findings := v_findings ||
      ('[2 PUBLIC-REACHABLE WRITER] public.' || r.fn || '(' || r.args || ')' ||
       ' is SECURITY DEFINER, writes, and PUBLIC holds EXECUTE (anon inherits it). ' ||
       'Revoke from PUBLIC -- revoking from anon alone reports success and changes nothing. ' ||
       'If it is meant to be public, add it to v_allowed_public_writers with a reason.');
  end loop;

  -- -------------------------------------------------------------------
  -- CHECK 3 -- a view that lost security_invoker.
  --
  -- It lives in pg_class.reloptions, not in the view body, and a bare
  -- CREATE OR REPLACE VIEW discards any option the new statement does
  -- not restate. The loss is silent: same columns, same data, every
  -- tenant's rows readable with the anon key.
  -- -------------------------------------------------------------------
  for r in
    select c.relname as v
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'v'
      and coalesce(array_to_string(c.reloptions, ','), '') !~ 'security_invoker=(on|true)'
    order by 1
  loop
    v_findings := v_findings ||
      ('[3 VIEW RUNS AS OWNER] public.' || r.v ||
       ' has no security_invoker=on in reloptions, so it bypasses RLS. ' ||
       'Restate `with (security_invoker = on)` in the CREATE OR REPLACE.');
  end loop;

  -- -------------------------------------------------------------------
  -- CHECK 4 -- a table in public with RLS off.
  --
  -- A new table in public inherits default grants that make it
  -- anon-writable on this project. This is the count that caught the
  -- accidental `v_rules` table created by running a migration fragment
  -- on its own (9 Sept 2026).
  -- -------------------------------------------------------------------
  for r in
    select c.relname as t
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
    order by 1
  loop
    v_findings := v_findings ||
      ('[4 TABLE WITHOUT RLS] public.' || r.t ||
       ' has RLS disabled. If this is an accidental artefact, drop it; ' ||
       'if it is real, enable RLS and give it a policy.');
  end loop;

  -- -------------------------------------------------------------------
  if array_length(v_findings, 1) is not null then
    raise exception E'SECURITY INVARIANT LINT: % finding(s)\n\n%',
      array_length(v_findings, 1),
      array_to_string(v_findings, E'\n\n');
  end if;

  raise notice 'SECURITY INVARIANT LINT: clean. (1) no fail-open uid guards, (2) no un-allow-listed PUBLIC-reachable SECURITY DEFINER writers, (3) all views security_invoker=on, (4) all public tables have RLS.';
end;
$$;
