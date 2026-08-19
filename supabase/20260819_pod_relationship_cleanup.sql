-- Nagarva — POD relationship cleanup (19 Aug 2026)
--
-- WHY
-- ---
-- `pod_records.relationship` was written unconditionally by the
-- supervisor completion flow, and the picker defaults to 'self'. So a
-- job completed WITHOUT a customer signature stored:
--
--     received_by_name   = null
--     completion_method  = 'not_available'
--     relationship       = 'self'      <-- asserts a relationship to
--                                          somebody who never received
--                                          the goods
--
-- Found 19 Aug 2026 on APC-1002, whose POD PDF printed "Relationship:
-- self" directly opposite "Received by: —".
--
-- Both code paths are already fixed (19 Aug 2026):
--   * lib/supervisor_job_page/supervisor_job_page_widget.dart writes
--     `relationship` only when completion_method = 'signature'
--   * lib/components/pod_pdf.dart suppresses the phone/relationship
--     rows for a non-signature POD at RENDER time, so rows written
--     before the fix already print correctly
--
-- This migration fixes the DATA, which the render guard does not: a
-- row asserting a relationship to a person who never took delivery is
-- wrong regardless of what any document happens to print today. Any
-- future reader of this table — an export, a dispute, a report nobody
-- has written yet — sees the truth rather than a leaked UI default.
--
-- SAFETY
-- ------
-- Touches only rows where completion_method is NOT 'signature', i.e.
-- 'not_available' and the legacy 'otp' rows. A signed POD's
-- relationship is real evidence and is never touched. Nulling this
-- column loses nothing: on a non-signature POD there is no receiver
-- for it to describe.
--
-- Idempotent — re-running matches zero rows.
--
-- BLAST RADIUS, measured live 19 Aug 2026 before writing this:
--   completion_method='signature'      1 row  — NOT touched
--   completion_method='not_available'  1 row  — APC-1002, cleared
--   completion_method='otp'            2 rows — 1 cleared (no receiver
--                                              named), 1 PRESERVED
--
-- DECIDED (Arun, 19 Aug 2026): of the two legacy 'otp' rows, one HAS a
-- `received_by_name` — somebody really did take delivery on that job,
-- so its `relationship` is a genuine record, not a leaked default. It
-- is PRESERVED. This migration therefore touches 2 rows, not 3:
-- APC-1002 and the one unnamed legacy OTP row.

begin;

-- What is about to change, for the record.
do $$
declare
  n_total  int;
  n_absent int;
begin
  select count(*) into n_total
    from public.pod_records
   where completion_method is distinct from 'signature'
     and relationship is not null;

  select count(*) into n_absent
    from public.pod_records
   where completion_method is distinct from 'signature'
     and relationship is not null
     and received_by_name is null;

  raise notice 'pod_records rows to clear: % (of which % have no received_by_name)',
    n_total, n_absent;
end $$;

-- NARROWER PREDICATE, per Arun 19 Aug 2026: "only null relationship
-- where received_by_name IS NULL. If someone actually received the
-- goods, the relationship is real data."
--
-- So this clears the leaked picker default and nothing else. The one
-- legacy 'otp' row that names a real receiver keeps its relationship,
-- because on that job somebody genuinely did take delivery and the
-- field describes them truthfully.
update public.pod_records
   set relationship = null
 where completion_method is distinct from 'signature'
   and received_by_name is null
   and relationship is not null;

-- Verify: must return 0.
do $$
declare
  leftover int;
begin
  select count(*) into leftover
    from public.pod_records
   where completion_method is distinct from 'signature'
     and received_by_name is null
     and relationship is not null;

  if leftover <> 0 then
    raise exception 'pod_records cleanup incomplete: % rows still carry a relationship', leftover;
  end if;
end $$;

commit;
