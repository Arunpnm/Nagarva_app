-- next_lr_number() fail-loud fix (RLS/numbering audit, 12 Aug 2026).
-- Handed over for Arun to review and run — not executed from this session.
--
-- Same bug, same fix, sibling function to next_doc_number() (see
-- 20260812_next_doc_number_fail_loud.sql). next_lr_number() (migration
-- 007) has the identical silent-insert-on-miss body — a miss on
-- (org, branch, fy) INSERTs a brand-new lr_series row starting at 1
-- instead of erroring, which is exactly what turned the currentFy()
-- client bug into invisible drift for invoice numbering. It would do the
-- same for LR numbering going forward if left as-is; not touched by the
-- next_doc_number() migration since it's a separate function against a
-- separate table (lr_series, not number_series — migration 007's own
-- comment: "the two aren't consolidated yet").
--
-- Same signature and return type as the existing function (uuid, text
-- default null, text default null) -> text — CREATE OR REPLACE is
-- sufficient, no DROP needed.
--
-- Same active-column behaviour change as next_doc_number()'s fix, for the
-- same reason: it's what makes 20260812_number_series_cleanup.sql's
-- `active = false` on the stray Chennai/2627 lr_series row actually mean
-- something, rather than being cosmetic.

begin;

create or replace function next_lr_number(
  p_org uuid, p_branch text default null, p_fy text default null
) returns text as $$
declare rec record; n int;
begin
  select * into rec from lr_series
   where org_id = p_org
     and coalesce(branch,'') = coalesce(p_branch,'')
     and coalesce(fy,'')     = coalesce(p_fy,'')
     and active
   for update;

  if not found then
    raise exception
      'No active LR series configured for org=%, branch=%, fy=%. '
      'Configure one in lr_series (or reactivate an existing row) before '
      'generating this document.',
      p_org, coalesce(p_branch, '<none>'), coalesce(p_fy, '<none>')
      using errcode = 'P0001';
  end if;

  n := rec.last_number + 1;
  update lr_series set last_number = n where id = rec.id;

  return coalesce(rec.prefix, 'LR') || lpad(n::text, 4, '0');
end;
$$ language plpgsql;

commit;

-- Verify after running, and after the Dart branch:null + fy fix has
-- shipped/rolled out:
--   -- should succeed and return e.g. '2026/0001':
--   select next_lr_number(
--     (select id from organizations where slug = 'apc'), null, '2026-27');
--
--   -- should now RAISE (was previously silent-succeed with a fresh row):
--   select next_lr_number(
--     (select id from organizations where slug = 'apc'), 'Chennai', '2627');
--
-- Same ordering as every other migration in this pass: Dart ships and is
-- confirmed on device -> next_doc_number() fail-loud ->
-- next_lr_number() fail-loud (this file) -> number_series/lr_series
-- cleanup. Running this before the Dart fix would make LR generation
-- fail loudly instead of drifting silently — correct in principle, wrong
-- order.
