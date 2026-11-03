-- 3 Nov 2026 — Quote-stage follow-up responses (Arun).
--
-- Lead -> Quote -> Order or Cancelled. In the Quote stage each follow-up
-- records the customer's response: Accepted, Negotiation, Rejected or
-- No response. follow_up_logs.outcome only allowed the call results
-- (connected, no_answer, busy, callback_requested, not_interested,
-- converted), so those four are added. Nothing existing changes.
-- Safe to re-run.

begin;

alter table public.follow_up_logs
  drop constraint if exists follow_up_logs_outcome_check;

alter table public.follow_up_logs
  add constraint follow_up_logs_outcome_check
  check (outcome = any (array[
    -- call results (Lead stage)
    'connected', 'no_answer', 'busy', 'callback_requested',
    'not_interested', 'converted',
    -- customer's response (Quote stage)
    'accepted', 'negotiation', 'rejected', 'no_response'
  ]));

commit;

select pg_get_constraintdef(oid)
  from pg_constraint
 where conname = 'follow_up_logs_outcome_check';
