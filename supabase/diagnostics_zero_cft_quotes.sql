-- ============================================================================
-- diagnostics_zero_cft_quotes.sql — READ-ONLY. Nothing here writes.
--
-- Finds quotes saved before the custom-item CFT fix (28 Jul 2026), where a
-- line was persisted with cft = 0.
--
-- WHY THEY EXIST: the quote builder used to keep only quantities and
-- resolve CFT at total time by walking the org's `pricing_config`
-- catalogue. A custom item is by definition not in that catalogue, so the
-- lookup returned 0 — the line saved with cft 0, contributed nothing to
-- `_totalCft`, and the suggested package/vehicle came out too small. The
-- money on the quote was still whatever was typed into the charges
-- section, so the *price* is not necessarily wrong; the CFT, suggested
-- package and vehicle sizing are.
--
-- DELIBERATELY NOT REWRITTEN. There is no safe way to infer what CFT a
-- surveyor meant for a one-off item months later, and silently editing a
-- quote a customer has already been shown (or signed) is worse than
-- leaving it visibly wrong. Review these by hand and re-quote the ones
-- that matter.
-- ============================================================================

-- 1) Affected quotes, one row each, newest first.
select q.id,
       q.customer,
       q.created_at,
       q.total,
       (q.charges ->> '_totalCft')          as recorded_total_cft,
       (q.charges ->> '_suggestedPackage')  as suggested_package,
       count(*) filter (where (li ->> 'cft')::numeric = 0) as zero_cft_lines,
       jsonb_agg(li ->> 'item')
         filter (where (li ->> 'cft')::numeric = 0)        as zero_cft_items
from public.quotations q
cross join lateral jsonb_array_elements(
  case when jsonb_typeof(q.items) = 'array' then q.items else '[]'::jsonb end
) as li
where (li ->> 'cft') is not null
  and (li ->> 'cft') ~ '^[0-9.]+$'
  and (li ->> 'cft')::numeric = 0
group by q.id, q.customer, q.created_at, q.total, q.charges
order by q.created_at desc;

-- 2) Same thing as a one-line count, to see whether this is worth a pass.
select count(distinct q.id) as affected_quotes
from public.quotations q
cross join lateral jsonb_array_elements(
  case when jsonb_typeof(q.items) = 'array' then q.items else '[]'::jsonb end
) as li
where (li ->> 'cft') ~ '^[0-9.]+$'
  and (li ->> 'cft')::numeric = 0;

-- 3) Orders converted from an affected quote — these are the ones where a
--    too-small vehicle may actually have been dispatched, so they matter
--    more than an unconverted quote sitting in the list.
select o.id            as order_ref,
       o.customer,
       o.move_date,
       o.status,
       q.id            as quotation_id,
       (q.charges ->> '_suggestedPackage') as suggested_package
from public.orders o
join public.quotations q on q.id = o.quotation_id
where exists (
  select 1
  from jsonb_array_elements(
    case when jsonb_typeof(q.items) = 'array' then q.items else '[]'::jsonb end
  ) li
  where (li ->> 'cft') ~ '^[0-9.]+$'
    and (li ->> 'cft')::numeric = 0
)
order by o.move_date desc;
