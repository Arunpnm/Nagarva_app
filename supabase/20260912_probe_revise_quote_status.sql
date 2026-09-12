-- =====================================================================
-- 20260912_probe_revise_quote_status.sql        DIAGNOSTIC, NOT A CHANGE
--
-- Answers ONE question by BEHAVIOUR: does the live revise_quote()
-- preserve an accepted quote's status, or overwrite it?
--
-- WHY THIS FILE EXISTS. A string match over pg_get_functiondef was run
-- and came back true. It could not answer this question:
-- `v_reason_required` appears FOUR times in the already-applied version
-- (it is the reason gate), so matching it proves only that the reason
-- rule exists — which it did before the conditional was written. That
-- is the wrong-question pattern this repo has catalogued five times.
--
-- WHAT MAKES THIS BEHAVIOURAL. It calls the function on a real quote
-- that a live order references and reads the status back. No text is
-- inspected. Then it ROLLS BACK, so the version row, the status and the
-- audit row all disappear.
--
-- THE WHOLE FILE IS ONE TRANSACTION THAT ENDS IN ROLLBACK. There is no
-- COMMIT anywhere in it. Read the last line before running it.
--
-- Safe to run before OR after 20260911_revise_quote_status_conditional
-- .sql — it reports which behaviour is live either way rather than
-- asserting one.
-- =====================================================================

begin;

set local search_path = public, pg_catalog;

do $$
declare
  v_id      text;
  v_before  text;
  v_after   text;
  v_res     jsonb;
begin
  select q.id, q.status into v_id, v_before
    from quotations q
   where q.deleted_at is null
     and q.status = 'accepted'
     and exists (select 1 from orders o
                  where o.quotation_id = q.id
                    and o.deleted_at is null
                    and coalesce(o.status, '') <> 'cancelled')
   limit 1;

  if v_id is null then
    raise exception
      'no accepted quotation with a live order exists, so the behaviour '
      'cannot be observed. Refusing rather than reporting a verdict that '
      'proved nothing.';
  end if;

  v_res := public.revise_quote(
             v_id,
             jsonb_build_object('total', 111111),
             'diagnostic probe -- this transaction is rolled back');

  select status into v_after from quotations where id = v_id;

  raise notice '--------------------------------------------------------';
  raise notice 'quote            : %', v_id;
  raise notice 'status before    : %', v_before;
  raise notice 'status after     : %', v_after;
  raise notice 'returned version : %', v_res ->> 'version';
  raise notice 'returns "status" : %',
               case when v_res ? 'status' then 'YES' else 'NO' end;
  raise notice '--------------------------------------------------------';

  if v_after = v_before then
    raise notice 'VERDICT: CONDITIONAL status is LIVE.';
    raise notice '  An accepted quote kept its status through a revision.';
    raise notice '  20260911_revise_quote_status_conditional.sql HAS run.';
  else
    raise notice 'VERDICT: UNCONDITIONAL status is live (% -> %).',
                 v_before, v_after;
    raise notice '  The migration has NOT run. Run it before shipping a';
    raise notice '  build carrying the Revise button, or the first';
    raise notice '  revision of an accepted quote destroys that status';
    raise notice '  with nothing able to put it back.';
  end if;
end $$;

-- NOT a commit. Everything above is discarded: the version row, the
-- status write and the audit row the trigger produced.
rollback;

-- =====================================================================
-- AFTER RUNNING, confirm the rollback actually took (one read, no
-- transaction) -- the point of a probe is that it leaves nothing:
--
--   select (select count(*) from quote_versions)                 as versions,
--          (select status || ':' || count(*)::text
--             from quotations where deleted_at is null
--            group by status order by status limit 1)            as a_status,
--          (select count(*) from audit_log
--            where entity_type = 'quotations')                   as quote_audit;
--
-- versions must be 0 and the status counts must still read
-- accepted:4 / draft:2.
-- =====================================================================
